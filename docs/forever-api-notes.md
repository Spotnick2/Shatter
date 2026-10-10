# Forever API notes (Shatter-specific)

Measured or source-verified facts this addon depends on. Addon-agnostic findings belong in the
canonical guide, `C:\Projects\References\PORTING-TBC-TO-FOREVER.md`; this file only records what
Shatter itself relies on, with the evidence.

Build: **1.60.1.70338** (`.build.info` in the World of Warcraft root, row `wow_classic_beta`;
`References\forever-api-1.60.1.70338.md`).
Client UI source: `C:\Projects\wow-ui-source`, `forever` branch (`version.txt` 1.60.1.70338,
commit 943764493). From 70291 to 70338 only `version.txt` changed, so the source citations below
hold on 70338.

70338's dump declares the same documented API as 70334's (functions, events, tables, widget
methods and the dump line numbers cited below are unchanged); its `_G` walk adds 35 Raid UI
functions Shatter doesn't use.

What was measured in game on 70338, before `MEASURED_ON_BUILD` moved to it: **pending**. The
probe: log in a character that knows Disenchant (Shatter stays inactive and stamps nothing on any
other, so its file reads `ShatterDB = nil`), exit the client fully, and find a 70338 stamp
following the 70334 ones in `WTF\Account\<id>\SavedVariables\Shatter.lua`. On 70334 that probe
showed Shatter loading and activating on an enchanter, and its SavedVariables read back across a
full client exit: the 70291
stamps were followed by 20 stamps on 70334, 2026-10-09 19:30 to 2026-10-10 01:01 (a build change is
a client restart, so the first new-build stamp in the same list is the table read back by a new
process). The rows marked **measure in game** below have not been measured on any build yet.

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
| SavedVariables | load back since 70009 | guide s1; Shatter's load stamps on 70334 (above) | measured (70334); 70338 pending |

Persistence canary: `ShatterDB.loadStamps` gains one `{ time, build }` per login (capped at 30).
After a FULL client exit, a list that never grows past one entry means SavedVariables are not
being read back on that build.

"source" = read from the dump or Blizzard source; still needs an in-game check before it is
"measured". Update this table when an in-game check settles a row.
