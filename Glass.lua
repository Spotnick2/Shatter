local _, Shatter = ...

-- Shatter's instance of the "liquid glass" material (#14).
--
-- The material is the embedded library LibGlass-1.0 (Libs\LibGlass-1.0, from
-- github.com/Spotnick2/LibGlass through .pkgmeta externals; the TOC loads it
-- first). Material changes are LibGlass PRs, not edits here. An instance, not
-- the library: its STYLE is Shatter's own and never touches another glass
-- addon's surfaces.
--
-- Pearl, the Glass suite's theme (LibGlass r11), whether or not Shatter
-- follows Glass UI (Suite.lua): following changes the body and the accent,
-- never the material. The newest loaded copy of the library wins; when that
-- is older than r11 (Shatter itself embeds r11), the material is the classic
-- one and Suite.lua reports Pearl as "library-too-old".
--
-- Looked up quietly: a copy installed from a git clone has no Libs folder,
-- and then Shatter.Glass is nil and every skin renders flat (Skin.lua).
Shatter.PEARL_MINOR = 11
Shatter.GlassPreset = nil   -- "pearl" or "classic": what Shatter.Glass was built as
Shatter.GlassMinor = nil    -- the winning library's MINOR

local lib, minor
if LibStub then lib, minor = LibStub("LibGlass-1.0", true) end
if lib then
    Shatter.GlassMinor = minor
    if type(minor) == "number" and minor >= Shatter.PEARL_MINOR then
        local ok, inst = pcall(lib.New, lib, { preset = "pearl" })
        if ok then Shatter.Glass, Shatter.GlassPreset = inst, "pearl" end
    end
    if not Shatter.Glass then
        local ok, inst = pcall(lib.New, lib)
        if ok then Shatter.Glass, Shatter.GlassPreset = inst, "classic" end
    end
end
