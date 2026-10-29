# ShatterProbe: what was measured in game

ShatterProbe (`Tools/ShatterProbe`) is Shatter's throwaway measurement module on ForeverProbe
(`/fp sh`; `C:\Projects\WoW\ForeverProbe\docs\GUIDE.md`). It isn't packaged (`.pkgmeta` ignores
`Tools`), and its tests (`tests/test_probe.lua`) run locally only, because ForeverProbe is private.

## Running it

1. `pwsh Tools\deploy.ps1 -Probe` (Shatter, ForeverProbe and ShatterProbe), then `/reload`.
2. `/fp steps sh skill` or `/fp steps sh refuse`, and follow the panel's buttons. Type what you
   see into the Note box.
3. `/reload` at the end. The session reads `SavedVariables\ShatterProbe.lua` and
   `ForeverProbe.lua` (`steps.records`) itself.

Commands: `/fp sh skill` (read Enchanting both ways), `/fp sh watch on|off` (record casts, UI
errors and loot events), `/fp sh events`, `/fp sh clear`.

## Open questions

| Question | Procedure | Status |
|---|---|---|
| **#5:** does `C_SkillInfo.GetSkillLineInfoByID(333)` give Enchanting's rank, and does it agree with walking `GetSkillLineInfo(i)`? Does a collapsed header hide Enchanting from the walk? | `skill` | not measured |
| **#5:** does the server refuse a high item level at low skill? The client's ItemDisenchantLoot has `SkillRequired` 0 on every row. One success doesn't clear every quality and bracket, and one refusal doesn't give a table | `refuse`, step 6 | not measured |
| **#6:** is an item the client flags (ItemSparse `Flags_0 & 0x8000`) refused, while an unflagged green (the control) is accepted? Gates the next release with `USE_NO_DISENCHANT_LIST` on | `refuse`, steps 2-5 | not measured |
| **#6:** what does the refusal look like: `UI_ERROR_MESSAGE` type, text and name (`GetGameMessageInfo`), and its order against `UNIT_SPELLCAST_FAILED`? Decides whether refusals can be learned automatically | `refuse`, step 4 | not measured |

Write each answer here with the build, then update `docs/forever-api-notes.md`.
