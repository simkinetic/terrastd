-- SPDX-FileCopyrightText: 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local atomics = require("atomics")

import "terratest@v1/terratest"

for _, T in ipairs{bool, int32, uint32, int64, uint64, float, double} do
    testenv(T) "Atomic instructions" do
        testset "Atomic store" do
            terracode
                var a: T = escape if T == bool then emit `false else emit `0 end end
                var b: T = escape if T == bool then emit `true else emit `1 end end
                atomics.store(&a, b)
            end
            test a == b
        end
    end
end
