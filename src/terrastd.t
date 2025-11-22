--Once you have added dependency 'X' to your dependencies in your 
--'Project.lua' file, simply add a dependency as follows:
-- local X = require("X")

local C = terralib.includecstring [[
   #include <stdio.h>
]]

local terrastd = {}

terra terrastd.hello()
    C.printf("Hello world!. Greetings from Terra terrastd.\n")
end

return terrastd