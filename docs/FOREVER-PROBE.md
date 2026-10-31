# ShatterProbe: what was measured in game

ShatterProbe (`Tools/ShatterProbe`) is Shatter's throwaway measurement module on ForeverProbe
(`/fp sh`; `C:\Projects\WoW\ForeverProbe\docs\GUIDE.md`). It isn't packaged (`.pkgmeta` ignores
`Tools`), and its tests (`tests/test_probe.lua`) run locally only, because ForeverProbe is private.

## Running it

1. `pwsh Tools\deploy.ps1 -Probe` (Shatter, ForeverProbe and ShatterProbe), then `/reload`.
2. `/fp steps sh <procedure>`, and follow the panel's buttons. Type what you see into the Note
   box.
3. `/reload` at the end. The session reads `SavedVariables\ShatterProbe.lua` and
   `ForeverProbe.lua` (`steps.records`) itself.

| Procedure | What it checks (#31) |
|---|---|
| `skill` | #5: how the client gives the Enchanting rank |
| `refuse` | #5, #6: a refused Disenchant, against an accepted control |
| `loot` | #10: the loot events' order and timing for a Disenchant, with Auto Loot on, off (slow to loot) and two quick Shatter Next clicks. Each step waits 3 s after the last event, so a late window is caught. Turn on `/shatter trace` too: Shatter's own view lands in `ShatterDB.debugLog` |
| `mail` | #26: `MailFrame` / `InboxFrame` a second after the mailbox closes, and Shatter's status then and after reopening |
| `sets` | #36: whether the client has equipment sets, what the bag slot call says for an item saved in one, and whether Shatter leaves it out of the queue and brings it back |
| `guid` | Item identity: a GUID followed across a drag, a bag sort and a `/reload` |
| `next` | The secure Shatter Next: one left click sends one Disenchant, armed only in the up edge's PreClick and disarmed after its PostClick; a right click and a press released off the button send nothing; a bound key (#35) sends one, and nothing with the window closed |
| `looks` | #28, #24: each look over a bright and a dark background, and the Mail launch panel (screenshots). It switches looks through `/shatter skin` and puts yours back. A look Shatter doesn't show (while it follows Glass UI, or a glass look without LibGlass) stops its step with no screenshot: Skip it |
| `ilvl` | #37: each worn slot's current item level (`C_Item.GetCurrentItemLevel`), the item's own and what Shatter reads, against the tooltip, also above item level 60; what Suggest fills in, and the queue keeping items at or above it |
| `tips` | #27: the "Disenchants into" lines on bag, chat-link, vendor, bank, auction house and loot tooltips, and Shift on an open bag tooltip and chat link with the modifier setting (screenshots). It sets `/shatter tooltip` and puts yours back |

Not covered, still by hand: the look switched in combat, the Mail session's Close Session confirm
(#29), persistence after a full exit (#20), and the CurseForge file.

Commands: `/fp sh skill` (read Enchanting both ways), `/fp sh watch on|off` (record casts, UI
errors and loot events), `/fp sh events`, `/fp sh clear`, and `/fp sh restore`, which puts back the look and tooltip setting
when `looks` or `tips` was stopped midway. Their backup is kept until a restore is verified, so
running one of them again never loses your original setting. A backup belongs to the Shatter
profile it was taken in (Global, or one character's Personal), and is only put back there: run
`/fp sh restore` on that character, with that profile active.

## Open questions

| Question | Procedure | Status |
|---|---|---|
| **#5:** does `C_SkillInfo.GetSkillLineInfoByID(333)` give Enchanting's rank, and does it agree with walking `GetSkillLineInfo(i)`? Does a collapsed header hide Enchanting from the walk? | `skill` | not measured |
| **#5:** does the server refuse a high item level at low skill? The client's ItemDisenchantLoot has `SkillRequired` 0 on every row. One success doesn't clear every quality and bracket, and one refusal doesn't give a table | `refuse`, step 6 | not measured |
| **#6:** is an item the client flags (ItemSparse `Flags_0 & 0x8000`) refused, while an unflagged green (the control) is accepted? Gates the next release with `USE_NO_DISENCHANT_LIST` on | `refuse`, steps 2-5 | not measured |
| **#6:** what does the refusal look like: `UI_ERROR_MESSAGE` type, text and name (`GetGameMessageInfo`), and its order against `UNIT_SPELLCAST_FAILED`? Decides whether refusals can be learned automatically | `refuse`, step 4 | not measured |
| **#10:** with Auto Loot on and off, the order of `UNIT_SPELLCAST_SUCCEEDED`, `LOOT_READY`, `LOOT_OPENED` (`isFromItem`), `LOOT_CLOSED` and `BAG_UPDATE_DELAYED`; does a loot event come after the bag update; can item A's loot reach B's attempt on two quick clicks; does a slow manual loot miss Shatter's count | `loot` | not measured |
| **#26:** after the mailbox closes, `MailFrame` hidden and `InboxFrame` shown but not visible; Shatter asks for the mailbox, and carries on when it reopens | `mail` | not measured |
| **#37:** does `C_Item.GetCurrentItemLevel` on a worn slot read as its tooltip shows, also above item level 60? | `ilvl` | not measured |
| **#36:** does Forever have equipment sets, and does `GetContainerItemEquipmentSetInfo` say `inSet` for an item saved in one? | `sets` | not measured |
| Does an item's GUID stay the same across a drag, a sort and a `/reload`? | `guid` | not measured |
| Shatter Next: one click, one cast, disarmed after; nothing on a right click or a release off the button | `next` | not measured |
| **#35:** does a bound key's release reach Shatter Next (it acts on the release, `useOnKeyDown` pinned false), casting once, with `ActionButtonUseKeyDown` 0 and 1? Nothing with the window closed? | `next`, steps 5-6 | not measured |
| The looks and the tooltips, by screenshot | `looks`, `tips` | not measured |

Write each answer here with the build, then update `docs/forever-api-notes.md`.
