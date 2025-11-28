-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require "terralibext"

local alloc = require("alloc")
local atomics = require("atomics")
local base = require("base")
local parametrized = require("parametrized")
local pthread = require("pthread")
local queue = require("queue")
local span = require("span")
local stack = require("stack")

import "terraform"

local cond = pthread.cond
local hardware_concurrency = pthread.hardware_concurrency
local lock_guard = pthread.lock_guard
local mutex = pthread.mutex
local omp_get_num_threads = pthread.omp_get_num_threads
local sched = terralib.includec("sched.h")

-- A thread has a unique ID that executes a given function with signature FUNC.
-- Its argument is stored as a managed pointer on the (global) heap. This way,
-- threads can be passed to other functions and executed there. The life time
-- of the argument arg is thus not bound to the life time of the local stack.
local FUNC = &opaque -> &opaque
local struct thread {
    id: pthread.C.pthread_t
    func: FUNC
    arg: alloc.SmartBlock(int8)
}
base.AbstractBase(thread)

--auto-generate `__init`
terralib.ext.addmissing.__init(thread)
terralib.ext.addmissing.__dtor(thread)
terralib.ext.addmissing.__move(thread)

terra thread.metamethods.__eq(self: &thread, other: &thread)
    return pthread.C.equal(self.id, other.id)
end

-- Pause the calling thread for a short period and resume afterwards.
thread.staticmethods.yield = sched.sched_yield

-- Exit thread with given the return value res.
terra thread.staticmethods.exit()
    return pthread.C.exit(nil)
end

-- After a new thread is created, it forks from the calling thread. To access
-- results of the forked thread we have to join it with the calling thread.
terra thread:join()
    return pthread.C.join(self.id, nil)
end

-- This is the heart of the thread module.
-- Given an allocator instance for memory management and a callable and
-- copyable instance (a function pointer, a lambda, a struct instance with
-- an overloaded apply, or a terraform function) and a list of copyable
-- arguments, it generates a terra function with signature FUNC and a datatype
-- that stores the function arguments. It returns a thread instance but not
-- starting the thread.
local terraform submit(allocator, func, arg...)
    var t: thread
    -- We do not set t.id as it will be set by thread.new
    --t.id = 0 -- Will be set up thread.create
    escape
        local struct packed {
            func: func.type
            arg: arg.type
        }
        local smartpacked = alloc.SmartObject(packed)
        smartpacked:complete()
        terralib.ext.addmissing.__init(smartpacked)
        terralib.ext.addmissing.__move(smartpacked)
        emit quote
            t.func = [
                terra(parg: &opaque)
                    var p = [&packed](parg)
                    p.func(unpacktuple(p.arg))
                    return parg
                end
            ]
            var smrtpacked = [alloc.SmartObject(packed)].new(allocator)
            smrtpacked.arg = __move__(arg)
            smrtpacked.func = __move__(func)
            t.arg = __move__(smrtpacked)
        end
    end
    return t
end

terraform thread.staticmethods.new(allocator, func, arg...)
    var t = submit(allocator, func, unpacktuple(arg))
    pthread.C.create(&t.id, nil, t.func, &t.arg(0))
    return t
end

-- A join_threads struct is an abstraction over a block of threads that
-- automatically joins all threads when the threads go out of scope.
local struct join_threads {
    data: span.Span(thread)
}

terra join_threads:__dtor()
    for i = 0, self.data:size() do
        self.data(i):join()
    end
end

local Q = queue.MutexQueue(thread)
local block_thread = alloc.SmartBlock(thread)
local struct threadpool {
    -- Signals all threads to exit when the thread pool is destroyed
    shutdown: bool
    joiner: join_threads
    -- Physical worker threads running on the CPU
    threads: block_thread
    -- Collection of work items submitted to the thread pool
    queue: Q
    queue_lock: mutex
    -- Check if queue is empty during shutdown
    queue_empty: cond
    -- Check for new work items
    queue_not_empty: cond
    -- Counts work items left in the queue
    remaining_work: int64
}
base.AbstractBase(threadpool)

terra threadpool.staticmethods.workerthread(parg: &opaque)
    var tp = [&threadpool](parg)
    while true do
        tp.queue_lock:lock()
        while tp.remaining_work == 0 and not tp.shutdown do
            tp.queue_not_empty:wait(&tp.queue_lock)
        end
        if tp.shutdown then
            tp.queue_lock:unlock()
            return thread.exit()
        end
        var t: thread
        tp.queue:pop(&t)
        atomics.sub(&tp.remaining_work, 1)
        if tp.remaining_work == 0 then
            tp.queue_empty:signal()
        end
        tp.queue_lock:unlock()
        t.func(&t.arg(0))
    end
end

-- The program already runs concurrently when new work is submitted. Hence,
-- we need to be careful when adding it to the thread pool.
-- Firstly, we need to signal to the physical threads that a new work item
-- is available and, secondly, need to add it to the work queue.
terraform threadpool:submit(allocator, func, arg...)
    self.queue:push(submit(allocator, func, unpacktuple(arg)))
    atomics.add(&self.remaining_work, 1)
    self.queue_not_empty:broadcast()
end

terra threadpool:__dtor()
    do
        var guard: lock_guard = self.queue_lock
        while self.remaining_work > 0 do
            self.queue_empty:wait(&self.queue_lock)
        end
        self.shutdown = true
        -- Trigger check for shutdown flag in workerthread
    end
    self.queue_not_empty:broadcast()
    self.joiner:__dtor()

    self.threads:__dtor()
    self.queue:__dtor()
    self.queue_lock:__dtor()
    self.queue_empty:__dtor()
    self.queue_not_empty:__dtor()
end

terraform threadpool.staticmethods.new(allocator, nthreads)
    var tp = [alloc.SmartObject(threadpool)].new(allocator)
    tp.shutdown = false
    tp.remaining_work = 0
    tp.threads = allocator:new(nthreads, sizeof(thread))
    tp.joiner = join_threads {{&tp.threads(0), nthreads}}
    tp.queue = Q.new(allocator, nthreads)

    -- Mutex and conditions are already initialized by the default __init,
    -- so we don't need to initialize them here

    for i = 0, nthreads do
        tp.threads(i) = thread.new(
            allocator,
            [threadpool.staticmethods.workerthread],
            tp.ptr
        )
    end
    return tp
end

local terraform parfor(alloc, rn, go, nthreads)
    var tp = threadpool.new(alloc, nthreads)
    for it in rn do
        tp:submit(alloc, go, it)
    end
end

terraform parfor(alloc, rn, go)
    var nthreads = omp_get_num_threads()
    parfor(alloc, rn, go, nthreads)
end

return {
    thread = thread,
    join_threads = join_threads,
    mutex = mutex,
    lock_guard = lock_guard,
    cond = cond,
    threadpool = threadpool,
    max_threads = hardware_concurrency,
    omp_get_num_threads = omp_get_num_threads,
    parfor = parfor,
}
