-- -- Organized Lua standard library modules into a big "std" table,
-- -- loosely following C++ standard library categories.

local libmap = {
    --directly accessible modules
    alloc = "alloc",
    atomics = "atomics",
    base = "base",
    compile = "compile",
    concepts = "concepts",
    fun = "fun",
    interfaces = "interface",
    lambda = "lambda",
    parametrized = "parametrized",
    span = "span",
    ranges = "range",
    threads = "thread",
    tuple = "tuple",
    -- bundled modules
    debug = "assert",
    io = "std_io",
    scalar = "std_scalar",
    vector = "std_vector",
    containers = "std_containers",
}

return setmetatable({}, {
    __index = function(t, key)
        if libmap[key] then
            return require("std@v0/" .. libmap[key])
        else
            error("No such library std@v0/" .. tostring(key))
        end
    end
})