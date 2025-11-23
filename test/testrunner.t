-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local prefix = arg[-1]

-- Is this a test file?
local function istestfile(filename)
    return string.sub(filename, 1, 4) == "test" and filename ~= "testrunner.t"
end

-- Turn list into a set
local function dictionary(list)
    local dict = {}
    for i, v in ipairs(list) do
        dict[v] = true
    end
    return dict
end

-- Define colors for printing test statistics
format = terralib.newlist()
format.normal = "\27[0m"
format.bold = "\27[1m"
format.red = "\27[31m"
format.green = "\27[32m"
format.yellow = "\27[33m"
format.header = format.bold .. format.yellow

-- Print the header
print(format.header)
print(string.format("%-25s%-50s%-30s", "Filename", "Test-environment", "Test-result"))
print(format.normal)

-- List files to be skipped
local files_to_skip = dictionary{
    "test3.t"
}

-- Global - use silent output - only testenv summary
__silent__ = true

-- Initialize totals
local total_passed = 0
local total_failed = 0

-- Function to parse test output with multiple lines (e.g., "6/8 tests passed")
local function parse_test_output(output)
    local file_passed = 0
    local file_failed = 0
    -- Iterate over each line
    for line in output:gmatch("[^\r\n]+") do
        local passed, total = line:match("(%d+)/(%d+)%s+tests passed")
        if passed and total then
            file_passed = file_passed + tonumber(passed)
            file_failed = file_failed + (tonumber(total) - tonumber(passed))
        end
    end
    return file_passed, file_failed
end

-- Run test files and capture output
for filename in io.popen("ls -p test"):lines() do
    print(filename)
    if istestfile(filename) and not files_to_skip[filename] then
        local execstring = prefix .. " test/" .. filename .. " --test --silent"
        -- Open a pipe to capture output
        local pipe = io.popen(execstring .. " 2>&1", "r")
        if pipe then
            local output = pipe:read("*all")
            local exitcode = pipe:close() and 0 or 1  -- 0 if successful, 1 if failed
            if exitcode ~= 0 then
                local message = format.bold .. format.red .. "Process exited with exitcode " .. tostring(exitcode)
                io.stdout:write(string.format("%-25s%-50s%-30s\n", filename, message, "NA" .. format.normal))
            else
                -- Parse output for pass/fail counts
                local passed, failed = parse_test_output(output)
                total_passed = total_passed + passed
                total_failed = total_failed + failed
                -- Print the original output
                io.stdout:write(output)
            end
        else
            local message = format.bold .. format.red .. "Failed to execute " .. filename
            io.stdout:write(string.format("%-25s%-50s%-30s\n", filename, message, "NA" .. format.normal))
        end
    end
end

-- Print total results
print(format.header)
print(string.format("Total Tests Passed: %d", total_passed))
print(string.format("Total Tests Failed: %d", total_failed))
print(format.normal)

-- Exit with non-zero code if tests failed
if total_failed > 0 then
    os.exit(1)
end