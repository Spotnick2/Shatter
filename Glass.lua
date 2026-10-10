local _, Shatter = ...

-- Shatter's instance of the "liquid glass" material (#14).
--
-- The material is the embedded library LibGlass-1.0 (Libs\LibGlass-1.0, from
-- github.com/Spotnick2/LibGlass through .pkgmeta externals; the TOC loads it
-- first). Material changes are LibGlass PRs, not edits here. An instance, not
-- the library: its STYLE is Shatter's own and never touches another glass
-- addon's surfaces.
--
-- Looked up quietly: a copy installed from a git clone has no Libs folder,
-- and then Shatter.Glass is nil and every skin renders flat (Skin.lua).
local lib = LibStub and LibStub("LibGlass-1.0", true)
Shatter.Glass = lib and lib:New() or nil
