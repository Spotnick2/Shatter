------------------------------------------------------------
-- test_manifest.lua - the TOC, .pkgmeta and deploy script describe a Forever
-- build, and every file the TOC loads exists with the exact case it is named
-- by (Windows forgives a case mismatch; the zip and other clients do not).
------------------------------------------------------------

local H = dofile("tests/harness.lua")

H.eq(H.directive("Interface"), "16001",
    "Interface is 16001 (1.60.1 -> %d%02d%02d); 11601 is a transposed-digit bug")
H.eq(H.directive("Version"), "@" .. "project-version" .. "@",
    "Version is the packager token; a literal version must never be committed over it")
H.eq(H.directive("SavedVariables"), "ShatterDB", "one account-wide SavedVariables table")
H.eq(H.directive("X-Curse-Project-ID"), "1545161",
    "the CurseForge project shared with the TBC addon (files told apart by flavor)")

-- Every TOC entry exists, segment by segment, with matching case.
local function listDir(dir)
    local names = {}
    local p = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '" 2>nul')
    if p then
        for name in p:lines() do names[#names + 1] = name end
        p:close()
    end
    return names
end
local onWindows = package.config:sub(1, 1) == "\\"
for _, file in ipairs(H.tocFiles()) do
    local path = file:gsub("\\", "/")
    local f = io.open(path, "rb")
    H.check(f ~= nil, "TOC entry exists: " .. file)
    if f then f:close() end
    if onWindows then
        local dir = "."
        for segment in path:gmatch("[^/]+") do
            local found = false
            for _, name in ipairs(listDir(dir)) do
                if name == segment then found = true break end
            end
            H.check(found, "TOC entry case matches disk: " .. file .. " (" .. segment .. ")")
            dir = dir .. "/" .. segment
        end
    end
end

-- No shipped Lua holds a packager keyword whole: the packager rewrites it in
-- every file, so a "dev copy" check written against it ships as a release
-- comparing against its own version (porting guide, section 4).
for _, file in ipairs(H.tocFiles()) do
    local text = H.readFile((file:gsub("\\", "/"))) or ""
    H.check(not text:find("@project%-[%w-]+@") and not text:find("@file%-[%w-]+@"),
        "no packager keyword in " .. file)
end

-- .pkgmeta: dev files stay out, LICENSE ships.
local pkgmeta = assert(H.readFile(".pkgmeta"))
H.check(pkgmeta:find("\npackage%-as: Shatter\n") or pkgmeta:find("^package%-as: Shatter\n"), "package-as Shatter")
local ignored = {}
for entry in pkgmeta:gmatch("\n  %- ([^\n]+)") do ignored[entry] = true end
for _, dev in ipairs({ "tests", "Tools", "docs", ".github", ".claude", "AGENTS.md", "CLAUDE.md", "SPEC.md", "CHANGELOG.md" }) do
    H.check(ignored[dev], ".pkgmeta ignores " .. dev)
end
H.check(not ignored["LICENSE"], "LICENSE ships with the package")

-- The deploy script targets the Forever client and refuses the TBC one.
local deploy = assert(H.readFile("Tools/deploy.ps1"))
H.check(deploy:find("_classic_beta_", 1, true), "deploy targets _classic_beta_")
H.check(deploy:find("Refusing to deploy the Forever build into the TBC", 1, true), "deploy refuses _anniversary_")

H.done("test_manifest")
