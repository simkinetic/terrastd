-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terraform"
local concepts = require("concepts")

local terraform atomic_store(trg: &T, src: T) where {T: concepts.Primitive}
    escape
        if T ~= bool then
            emit `terralib.atomicrmw("xchg", trg, src, {ordering = "acq_rel"})
        else
            emit `terralib.atomicrmw("xchg", [&uint8](trg), [uint8](src), {ordering = "acq_rel"})
        end
    end
end

local terraform atomic_add(src: &T, inc: T) where {T: concepts.Integer}
    return terralib.atomicrmw("add", src, inc, {ordering = "acq_rel"})
end

terraform atomic_add(src: &T, inc: T) where {T: concepts.Float}
    return terralib.atomicrmw("fadd", src, inc, {ordering = "acq_rel"})
end

local terraform atomic_sub(src: &T, inc: T) where {T: concepts.Integer}
    return terralib.atomicrmw("sub", src, inc, {ordering = "acq_rel"})
end

terraform atomic_sub(src: &T, inc: T) where {T: concepts.Float}
    return terralib.atomicrmw("fsub", src, inc, {ordering = "acq_rel"})
end

local terraform atomic_cmpxchg(ref: &T, old: T, new: T) where {T: concepts.Integer}
    return terralib.cmpxchg(
        ref, old, new,
        {success_ordering = "acq_rel", failure_ordering = "monotonic"}
    )
end

return {
    store = atomic_store,
    cmpxchg = atomic_cmpxchg,
    add = atomic_add,
    sub = atomic_sub,
}
