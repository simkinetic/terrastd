-- Organized Lua standard library modules into a big "std" table,
-- loosely following C++ standard library categories.
return {
    alloc           = require("alloc"),
    atomics         = require("atomics"),
    base            = require("base"),
    compile         = require("compile"),
    concepts        = require("concepts"),
    interfaces      = require("interface"),
    lambda          = require("lambda"),
    parametrized    = require("parametrized"),
    span            = require("span"),
    ranges          = require("range"),
    diagnostics     = require("assert"),
    threads         = require("thread"),
    containers = {
        hashset     = require("hash"),
        queue       = require("queue"),
        stack       = require("stack"),
        tree        = require("tree")
    },
    scalar = {
        complex     = require("complex"),
        dual        = require("dual"),
        nfloat      = require("nfloat"),
        random      = require("random"),
        math        = require("tmath"),
    },
    vector = {
        unpack(require("simd")),
        math = require("vecmath"),
        random = require("vecrandom")
    },
    io = {
        json = require("json")
    },
}