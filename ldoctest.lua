--- ldoctest.py
-- This script parses lua files passed as input and executes all code within
-- `ldoc` style @usage blocks in order to test its validity.
--
-- Example code is executed inside an ENV returned by a `.ldoctest` file
-- located within the directory that `ldoctest` is run. If such a file is not
-- present, an empty ENV table will be used.
--
-- The results are printed to stdout in TAP format. The script will return a 0
-- if all tests are passed, and 1 otherwise.
--
-- Limitations:
-- Lua block-style comments are not supported
-- There may be many more, this is a bit of a quick-and-dirty attempt at the idea
--
-- Requirements:
-- Lua 5.3
--
-- Usage: lua ldoctest.lua ./*.lua
local args = {...}

-- Extract all contiguous comment blocks from a file
local function extract_comment_blocks(filename)
    local current_comment = {}
    local all_comments    = {}
    for line in io.lines(filename) do
        if line:sub(1,2) == '--' then
            -- Removes comment and leading whitespace
            local trim = line:sub(3):gsub("^%s*", "")
            table.insert(current_comment, trim)
        elseif #current_comment > 0 then
            table.insert(all_comments, current_comment)
            current_comment = {}
        end
    end
    return all_comments
end

-- Returns contiguous ldoc @usage blocks from a list
-- of common_blocks provided by `extract_comment_blocks`
local function extract_usage_blocks(comment_blocks)
    local all_examples = {}
    for _, comment_block in ipairs(comment_blocks) do
        local current_example = nil
        for _, line in ipairs(comment_block) do
            -- Breaks current active example
            if line:sub(1,1) == '@' then
                if current_example ~= nil then
                    table.insert(all_examples, current_example)
                end
                current_example = nil
            end
            -- New current example
            if line:sub(1,6) == '@usage' then
                current_example = {}
            -- Ordinary text
            elseif current_example ~= nil then
                table.insert(current_example, line)
            end
        end
        -- Add final active usage example
        if current_example ~= nil then
            table.insert(all_examples, current_example)
        end
    end
    return all_examples
end

-- Read the target environment from file
local function load_env()
    local env_fn = loadfile(".ldoctest")
    if env_fn == nil then
        return {}
    else
        return env_fn()
    end
end

local ENV = load_env()
local file_tests = {} -- List of test example code per file
local total_tests = 0 -- Total number of tests
for _, filename in ipairs(args) do -- Loop over arguments and parse them for example code
    local blocks = extract_comment_blocks(filename)
    local usage  = extract_usage_blocks(blocks)
    if #usage > 0 then
        file_tests[filename] = usage
        total_tests = total_tests + #usage
    end
end

-- TAP format initialiser (1 .. N)
print("1.."..tostring(total_tests))

-- Loop through tests, executing them one-by-one
local itest_total = 1
local passed_all_tests = true
for filename, tests in pairs(file_tests) do
    print("# Testing file: " .. filename)
    for itest, test in ipairs(tests) do
        local test_code = table.concat(test, '\n')
        local test_function = load(test_code, filename..'-'..itest, 't', ENV)
        if setfenv then -- Lua5.1
            setfenv(test_function, ENV)
        end
        local result, msg = pcall(test_function)
        if test_function == nil then msg = "Failed to parse usage example" end
        if result == false then -- Print error message and commented section of code
            print("not ok " .. itest_total .. " " ..filename)
            print("# Error: " .. msg)
            for _, line in ipairs(test) do print( "# " .. line) end
        else
            print("ok " .. itest_total .. " " ..filename)
        end
        itest_total = itest_total + 1
        passed_all_tests = passed_all_tests and result
    end
end

print("# Testing complete")
if passed_all_tests == true then
    os.exit(0)
else
    os.exit(1)
end
