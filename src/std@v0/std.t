-- -- Organized Lua standard library modules into a big "std" table,
-- -- loosely following C++ standard library categories.

local libmap = {
    alloc = "alloc",
    atomics = "atomics",
    base = "base",
    compile = "compile",
    concepts = "concepts",
    interfaces = "interface",
    lambda = "lambda",
    parametrized = "parametrized",
    span = "span",
    ranges = "range",
    assert = "assert",
    threads = "thread",
}

-- Get any of the libraries in the table above
local function getcorelib(t, key)
    if libmap[key] then
        local success, value = pcall(require, "std@v0/" .. libmap[key])
        if success then
            rawset(t, key, value)
            return value
        end
    end
    return nil  -- Explicit nil if not found or failed
end

-- Get any of the libraries that start with std_... 
local function getspecializedlib(t, key)
    local success, value = pcall(require, "std@v0/std_" .. key)
    if success then
        rawset(t, key, value)
        return value
    end 
    return nil
end

return setmetatable({}, {
    __index = function(t, key)
        return rawget(t, key) or getcorelib(t, key) or getspecializedlib(t, key) or error("CompileError: not a valid library.")
    end
})