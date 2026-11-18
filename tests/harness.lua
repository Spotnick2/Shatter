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

-- FINDING (Shatter#70): three help lines print a bare "|" between the
-- choices ("/shatter learn on|off|clear", "/shatter tooltip always|...",
-- "/shatter skin forever|..."), which the client reads as an escape. done()
-- fails on any stray "|"; a test that prints one lets exactly those lines
-- through until it's fixed, so any other stray still fails. Checks it let
-- at least one through, and returns how many.
local KNOWN_STRAYS = { "Use /shatter learn on|off|clear.", "Use /shatter tooltip always|modifier|never.",
                       "Use /shatter skin forever|clear|smoked|flat." }
function H.acceptKnownStrays()
    local keep, known = {}, 0
    for _, line in ipairs(WoW.strays) do
        local isKnown = false
        for _, s in ipairs(KNOWN_STRAYS) do
            if line:find(s, 1, true) then isKnown = true break end
        end
        if isKnown then known = known + 1 else keep[#keep + 1] = line end
    end
    WoW.strays = keep
    check(known > 0, "a known stray-| help line (FINDING Shatter#70) was printed")
    return known
end

return H
