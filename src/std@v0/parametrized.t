-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local concepts = require("std@v0/concept-impl")
local serde = require("std@v0/serde")

local function admissible(arg)
    -- Checks if arg is convertible to a raw table.
    local islist = {
        default = true,
        [terralib.newlist] = true,
    }
    local mt = getmetatable(arg)
    return islist[mt or "default"] or false
end

local function israwtable(arg)
    -- For terra, an argument of type "table" can be a raw lua table,
    -- a lua table with a custom metatable, a terralib.List or a terra type
    -- For serialization, we only need to take care of the first two options,
    -- the other caseses are assumed to be safe for caching.
    if type(arg) ~= "table" or terralib.types.istype(arg) then
        return false
    else
        return admissible(arg)
    end
end

local function wrap(arg)
    -- Wrap arguments for terralib.memoize. This means we have to convert
    -- tables to strings.
    return israwtable(arg) and serde.serialize_table(arg) or arg
end

local function unwrap(arg)
    -- Inverse of wrap(). Take the cachable representation and unwrap the
    -- underlying lua data
    if type(arg) == "string" then
        local ok, ret = serde.deserialize_table(arg)
        return ok and ret or arg
    else
        return arg
    end
end

local type = function(f, options)
    -- The function f possibly takes tables as input. For terralib.memoize,
    -- we need function parameters that comparable (numbers, strings, ...)
    -- and don't change at every creation of a new instance. So in a first
    -- step we create a wrapper that takes wrapped input, unwraps it and
    -- passes it to the original function.
    local function fs(...)
        local sarg = terralib.newlist{...}
        local arg = sarg:map(unwrap)
        return f(unpack(arg))
    end
    local fc = terralib.memoize(fs)

    -- Calls to parametric types are also possible with lazy types like
    -- concepts.
    local function call(...)
        local arg = terralib.newlist{...}
        -- The option array is optional. If it's defined, then it contains
        -- the default values of named options for the type generation.
        if options then
            if not israwtable(arg[#arg]) then
                arg[#arg + 1] = {}
            end
            local n = #arg
            for name, reference in pairs(options) do
                local actual = arg[n][name]
                if actual == nil then
                    arg[n][name] = reference
                end
            end
        end

        -- Promote all compile time constants to concepts. This is necessary
        -- for the dispatch mechanism for function templates, aka terraform
        -- functions.
        local carg = terralib.newlist()
        for i, a in ipairs(arg) do
            if type(a) ~= "table" then
                carg[i] = concepts.casttoconcept(a)
            else
                carg[i] = a
            end
        end
        
        local sarg = arg:map(wrap)
        local T
        if arg:exists(concepts.isconcept) then
            -- Give a unique name to the concept as the result of newconcept
            -- is cached based on its name.
            T = concepts.newconcept(
                "ParametrizedType[" .. tostring(f) .. "]" ..
                "(" .. table.concat(sarg:map(tostring), ",") .. ")"
            )
        else
            T = fc(unpack(sarg))
        end
        T.generator = f
        T.parameters = carg
        return T
    end
    return call
end

return {
    type = type,
}

