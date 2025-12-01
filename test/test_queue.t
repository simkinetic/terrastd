-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local alloc = require("std@v0/alloc")
local atomics = require("std@v0/atomics")
local thread = require("std@v0/thread")
local queue = require("std@v0/queue")

import "terratest@v1/terratest"

for _, Key in ipairs{"LockFreeQueue"} do
    testenv(Key) "Multi producer, multi consumer queue" do
        for _, T in ipairs{int32, int64, float, double} do
            local ITEMS = math.floor(1024 * 32)
            local Q = queue[Key](T)
            local terra producer(q: &Q, S: &T)
                for i = 0, [int](ITEMS) do
                   q:push(1)
                end
                q:push(-1)
                atomics.add(S, [T](ITEMS))
            end
            local terra consumer(q: &Q, S: &T)
                var s: int = 0
                while true do
                    var item: T
                    q:pop(&item)
                    if item < 0 then
                        break
                    end
                    s = s - 1
                end
                atomics.add(S, [T](s))
            end

            local THREADS = 16
            local STACKSIZE = 64
            testset(T) "Synchronization" do
                terracode
                    var A: alloc.DefaultAllocator()
                    var q = Q.new(&A, STACKSIZE)
                    var S: T = 0

                    var producers: thread.thread[THREADS / 2]
                    var consumers: thread.thread[THREADS / 2]

                    for i = 0, THREADS / 2 do
                        producers[i] = thread.thread.new(&A, producer, &q, &S)
                        consumers[i] = thread.thread.new(&A, consumer, &q, &S)
                    end

                    for i = 0, THREADS / 2 do
                        consumers[i]:join()
                    end
                end

                test S == 0
            end
        end
    end
end
