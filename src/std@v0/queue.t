-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

require "terralibext"

local alloc = require("std@v0/alloc")
local atomics = require("std@v0/atomics")
local base = require("std@v0/base")
local parametrized = require("std@v0/parametrized")
local stack = require("std@v0/stack")
local pthread = require("std@v0/pthread")

local sched = terralib.includec("sched.h")

local LockFreeQueue = parametrized.type(function(T)
    -- Design inspired by https://github.com/bittnkr/uniq
    local S = alloc.SmartBlock(T)
    local B = alloc.SmartBlock(bool)
    local struct queue {
        buffer: S
        isfree: B
        size: int64
        mask: int64
        in_: int64
        out: int64
    }

    terralib.ext.addmissing.__init(queue)
    terralib.ext.addmissing.__move(queue)
    terralib.ext.addmissing.__dtor(queue)

    function queue.metamethods.__typename()
        return ("LockFreeQueue(%s)"):format(tostring(T))
    end

    base.AbstractBase(queue)

    terra queue.staticmethods.new(A: alloc.Allocator, size: uint64)
        var q: queue
        q.buffer = A:new(size, sizeof(T))
        q.isfree = A:new(size, sizeof(bool))
        for i = 0, size do
            q.isfree(i) = true
        end
        q.size = size
        q.mask = size - 1
        q.in_ = 0
        q.out = 0

        return q
    end

    terra queue:push(item: T)
        var i: int64
        repeat
            i = self.in_
            while i - self.out == self.size do
                sched.sched_yield()
            end
        until (
            self.isfree(i and self.mask)
            and atomics.cmpxchg(&self.in_, i, i + 1)._1
        )
        i = i and self.mask
        self.buffer(i) = item
        self.isfree(i) = false
    end

    terra queue:pop(item: &T)
        var o: int64
        repeat
            o = self.out
            while o == self.in_ do
                sched.sched_yield()
            end
        until (
            not self.isfree(o and self.mask)
            and atomics.cmpxchg(&self.out, o, o + 1)._1
        )
        o = o and self.mask
        @item = self.buffer(o)
        self.isfree(o) = true
        return item
    end

    return queue
end)

local MutexQueue = parametrized.type(function(T)
    local S = stack.DynamicStack(T)
    local struct queue {
        buffer: S
        mtx: pthread.mutex
    }

    terralib.ext.addmissing.__init(queue)
    terralib.ext.addmissing.__move(queue)
    terralib.ext.addmissing.__dtor(queue)

    function queue.metamethods.__typename()
        return ("MutexQueue(%s)"):format(tostring(T))
    end

    base.AbstractBase(queue)

    terra queue.staticmethods.new(A: alloc.Allocator, capacity: uint64)
        var q: queue
        q.buffer = S.new(A, capacity)
        return q
    end

    terra queue:push(t: T)
        var guard: pthread.lock_guard = self.mtx
        self.buffer:push(__move__(t))
    end

    terra queue:pop(t: &T)
        var guard: pthread.lock_guard = self.mtx
        @t = self.buffer:pop()
    end

    return queue
end)

return {
    LockFreeQueue = LockFreeQueue,
    MutexQueue = MutexQueue,
}
