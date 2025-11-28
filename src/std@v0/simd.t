-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concepts = require("concepts")
local parametrized = require("parametrized")

local SIMD = parametrized.type(function(T, N) return vector(T, N) end)

import "terraform"

local load = terralib.memoize(function(N)
    local load
    terraform load(a: &T) where {T: concepts.Primitive}
        escape
            local arg = {}
            for i = 1, N do
                arg[i] = `a[i - 1]
            end
            emit quote return vectorof(T, [arg]) end
        end
    end
    terraform load(a: T) where {T: concepts.Primitive}
        return [SIMD(T, N)](a)
    end
    return load
end)

local terraform store(a: &T, v: V) where {
    T: concepts.Primitive,
    V: SIMD(concepts.Primitive, concepts.Value)
}
    escape
        for i = 0, V.N - 1 do
            emit quote a[i] = v[i] end
        end
    end
end

local terraform hsum(v: V) where {V: SIMD(concepts.Primitive, concepts.Value)}
        var res = [V.type](0)
        escape
            for j = 0, V.N - 1 do
                emit quote res = res + v[j] end
            end
        end
        return res
end

return {
    SIMD = SIMD,
    load = load,
    store = store,
    hsum = hsum,
}
