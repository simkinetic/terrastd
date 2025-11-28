-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local simd = require("simd")

import "terratest@v1/terratest"

for _, T in pairs{int32, int64, float, double} do
    for _, N in pairs{4, 8, 16, 32, 64} do
        testenv(T, N) "SIMD" do
            local SIMD = simd.SIMD(T, N)
            testset "Load from scalar" do
                terracode
                    var a = [T](-2)
                    var v: SIMD = [simd.load(N)](a)
                end
                for i = 0, N - 1 do
                    test v[i] == a
                end
            end

            testset "Load from pointer" do
                terracode
                    var a = escape
                        local arg = terralib.newlist()
                        for i = 0, N - 1 do
                            arg:insert(`[T](i))
                        end
                        emit `arrayof(T, [arg])
                    end
                    var v = [simd.load(N)](&a[0])
                end
                for i = 0, N - 1 do
                    test v[i] == a[i]
                end
            end

            testset "Store to pointer" do
                terracode
                    var a: T[N]
                    var v = escape
                        local arg = terralib.newlist()
                        for i = 0, N - 1 do
                            arg:insert(`[T](i))
                        end
                        emit `vectorof(T, [arg])
                    end
                    simd.store(&a[0], v)
                end
                for i = 0, N - 1 do
                    test v[i] == a[i]
                end
            end

            testset "Horizontal sum" do
                terracode
                    var v= escape
                        local arg = terralib.newlist()
                        for i = 0, N - 1 do
                            arg:insert(`i)
                        end
                        emit `vectorof(T, [arg])
                    end
                    var sum = simd.hsum(v)
                end
                test sum == (N * (N - 1)) / 2
            end
        end
    end
end
