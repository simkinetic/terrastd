-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest@v1/terratest"
import "std@v0/terraform"

local std = require("std@v0/std")


-- test the public API
testenv "std" do

    testset "terraform" do
        terraform product(x, y)
            return x * y
        end
        test product(2, 3) == 6
    end

    testset "core" do
        --test access to allocator library
        local DefaultAllocator = std.alloc.DefaultAllocator()
    end


    local complex_t = std.scalar.complex.complex(double)
    local im = complex_t:unit()

    testset "scalar" do
        terracode
            var x = complex_t.from(1, 2) 
            var y = 1 + 2 * im
        end
        test x == y
    end

    testset "debug" do
        terracode
            std.debug.assert(10 > 1)
        end
        test 1 == 1
    end

end
