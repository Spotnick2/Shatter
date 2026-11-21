------------------------------------------------------------
-- harness.lua - file and TOC helpers for the tests. The assertions are
-- WowTestKit's globals (check, eq, done), loaded by tests/wow_stubs.lua, or
-- here for a test that loads no stub.
--
--     local H = dofile("tests/harness.lua")
--     eq(actual, expected, "what this proves")
--     done("test_thing")
--
-- Run from the repo root so the relative paths resolve.
------------------------------------------------------------

if not rawget(_G, "Kit") then dofile("tests/kit.lua") end

local H = {}

local TOC = "Shatter.toc"

-- Runs fn and checks it does not raise.
function H.ok(fn, msg)
    local ok, err = pcall(fn)
    check(ok, (msg or "unexpected error") .. ": " .. tostring(err))
    return ok
end

-- A whole file as text with CRLF normalised, or nil if it does not exist.
function H.readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end

-- The TOC as a list of lines, trailing whitespace stripped (blank and `#`
-- lines included: the directives are read from it).
function H.tocLines()
    local toc = assert(H.readFile(TOC), TOC .. " not found - run from the repo root")
    local lines = {}
    for line in (toc .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = (line:gsub("%s+$", ""))
    end
    return lines
end

-- The value of a `## Name: value` directive, or nil.
function H.directive(name)
    -- Escape the name: "X-Curse-Project-ID" contains "-", a Lua pattern
    -- quantifier, so an unescaped match silently finds nothing.
    local escaped = name:gsub("(%W)", "%%%1")
    for _, line in ipairs(H.tocLines()) do
        local value = line:match("^##%s*" .. escaped .. ":%s*(.*)$")
        if value then return value end
    end
    return nil
end

-- Every file the TOC loads, in order, with the TOC's backslashes.
-- The addon's own TOC files (in the repo), or with `libs` the embedded
-- libraries' entries (Libs\..., fetched by the packager, never committed).
function H.tocFiles(libs)
    local files = {}
    for _, file in ipairs(Kit.tocLines(TOC)) do
        if (file:match("^Libs\\") ~= nil) == (libs == true) then files[#files + 1] = file end
    end
    return files
end

return H
