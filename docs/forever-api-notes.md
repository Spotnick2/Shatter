# Forever API notes (Shatter-specific)

Measured or source-verified facts this addon depends on. Addon-agnostic findings belong in the
canonical guide, `C:\Projects\References\PORTING-TBC-TO-FOREVER.md`; this file only records what
Shatter itself relies on, with the evidence.

Build: **1.60.1.70334** (`_classic_beta_\.build.info`, `References\forever-api-1.60.1.70334.md`).
Client UI source: `C:\Projects\wow-ui-source`, `forever` branch (`version.txt` 1.60.1.70291; no
70334 source has been published, so the source citations below are 70291's).

What was measured in game on 70334, before `MEASURED_ON_BUILD` moved to it: Shatter loads and
activates on an enchanter, and its SavedVariables come back across a full client exit (the
persistence canary below, read from `WTF\Account\<id>\SavedVariables\Shatter.lua`: the 70291
stamps are followed by 20 stamps on 70334, 2026-10-09 19:30 to 2026-10-10 01:01; a build change is
a client restart, so the first 70334 stamp landing in the same list is the table read back by a new
process). These are the rows 70291 was measured on too. The rows marked **measure in game** below
have not been measured on any build yet, 70334 included.

| Shatter needs | On Forever | Evidence | Status |
|---|---|---|---|
| Item info | `C_Item.GetItemInfo` (Classic 18-tuple; zero returns on cache miss), `C_Item.GetItemInfoInstant` (7-tuple) | dump 2240-2241; guide s2 | source |
| Container | `C_Container.*`; `GetContainerItemInfo` returns a struct with `isBound` | dump 1167-1182, 8790 | source |
| Disenchant known | `C_SpellBook.IsSpellInSpellBook(13262)`; bare `IsSpellKnown` only with deprecation fallbacks | dump 3627; `Blizzard_DeprecatedSpellBook` | source |
| Localized spell name | `C_Spell.GetSpellName(13262)` (by ID always resolves) | dump 3543; guide s2 | source |
| Secure Disenchant button | `SecureActionButtonTemplate`, `type=spell` + `spell=13262` -> `CastSpellByID`; `target-bag`/`target-slot` used only while `SpellCanTargetItem()`; `useOnKeyDown=false` attribute pins the action to the up edge | SecureTemplates.lua:396, 758-776, 780-805; guide s3 | source; **measure in game** |
| Resize bounds | `SetResizeBounds(minW, minH, maxW, maxH)`; `SetMinResize`/`SetMaxResize` gone | dump 6114 | source |
| Mail receive slots | `ATTACHMENTS_MAX` = 16 receive, 12 send | Blizzard_MailFrame/MailFrame.lua:3-4 | source |
| Item instance identity | `C_Item.GetItemGUID(ItemLocation)` (non-optional WOWGUID), `C_Item.DoesItemExist`; `ItemLocation:CreateFromBagAndSlot` from Blizzard_ObjectAPI (no game-type restriction). Shatter scans bags for the GUID rather than using `C_Item.GetItemLocation`. If it yields nothing, every copy of the item is held back from Solo and the Mail disenchant is refused | dump 2207, 2232; Blizzard_ObjectAPI/Mainline/ItemLocation.lua | source; **measure in game** (GUID stable across a drag and a bag sort) |
| Mail frames | `InboxFrame`, `OpenMailFrame`, `MailFrameTab1/2` exist; Blizzard_MailFrame is not LOD | MailFrame.xml | source |
| Bags | 0-4 unchanged, `NUM_BAG_SLOTS` = 4, reagent bag 5 | guide s3 | measured (guide) |
| SavedVariables | load back since 70009 | guide s1; Shatter's load stamps on 70334 (above) | measured (70334) |

Persistence canary: `ShatterDB.loadStamps` gains one `{ time, build }` per login (capped at 30).
After a FULL client exit, a list that never grows past one entry means SavedVariables are not
being read back on that build.

"source" = read from the dump or Blizzard source; still needs an in-game check before it is
"measured". Update this table when an in-game check settles a row.
