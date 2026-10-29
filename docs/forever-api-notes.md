# Forever API notes (Shatter-specific)

Measured or source-verified facts this addon depends on. Addon-agnostic findings belong in the
canonical guide, `C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md`; this file only records what
Shatter itself relies on, with the evidence.

Build: **1.60.1.70532** (`.build.info` in the World of Warcraft root, `_forever_` client;
`References\Forever\api\forever-api-1.60.1.70532.md`).
Client UI source: `C:\Projects\WoW\wow-ui-source`, `forever` branch (`version.txt` 1.60.1.70532,
commit ca8368f2f). From 70291 to 70532, `SecureTemplates.lua`, `Blizzard_DeprecatedSpellBook` and
`Blizzard_ObjectAPI/Mainline/ItemLocation.lua` are unchanged. `Blizzard_MailFrame` changed in
70425, only in gamepad navigation and Open All handling the new `MAIL_OPEN_ALL_CANCELED`. The
attachment constants and the frame names cited below are unchanged.

From 70334 to 70532 the documented API changed in names Shatter doesn't use, mostly
`C_SecureTransfer` mail-money confirmation, `C_BattleNet` and `C_ExternalEventURL`. The widget
methods are unchanged, and so are the signatures cited below; their dump line numbers moved and
are 70532's.

What was measured in game on 70532, before `MEASURED_ON_BUILD` moved to it: **pending**. The
probe: log in a character that knows Disenchant (Shatter stays inactive and stamps nothing on any
other), exit the client fully, and find a 70532 stamp following the 70334 ones in
`WTF\Account\<id>\SavedVariables\Shatter.lua`. On 70334 that probe showed Shatter loading and
activating on an enchanter, and its SavedVariables read back across a full client exit: the 70291
stamps were followed by 20 stamps on 70334, 2026-10-09 19:30 to 2026-10-10 01:01 (a build change is
a client restart, so the first new-build stamp in the same list is the table read back by a new
process). The rows marked **measure in game** below have not been measured on any build yet.

| Shatter needs | On Forever | Evidence | Status |
|---|---|---|---|
| Item info | `C_Item.GetItemInfo` (Classic 18-tuple; zero returns on cache miss), `C_Item.GetItemInfoInstant` (7-tuple) | dump 2243-2244; guide s2 | source |
| Container | `C_Container.*`; `GetContainerItemInfo` returns a struct with `isBound` | dump 1170-1185, 8808 | source |
| Disenchant known | `C_SpellBook.IsSpellInSpellBook(13262)`; bare `IsSpellKnown` only with deprecation fallbacks | dump 3633; `Blizzard_DeprecatedSpellBook` | source |
| Localized spell name | `C_Spell.GetSpellName(13262)` (by ID always resolves) | dump 3549; guide s2 | source |
| Secure Disenchant button | `SecureActionButtonTemplate`, `type=spell` + `spell=13262` -> `CastSpellByID`; `target-bag`/`target-slot` used only while `SpellCanTargetItem()`; `useOnKeyDown=false` attribute pins the action to the up edge | SecureTemplates.lua:396, 758-776, 780-805; guide s3 | source; **measure in game** |
| Resize bounds | `SetResizeBounds(minW, minH, maxW, maxH)`; `SetMinResize`/`SetMaxResize` gone | dump 6127 | source |
| Mail receive slots | `ATTACHMENTS_MAX` = 16 receive, 12 send | Blizzard_MailFrame/MailFrame.lua:3-4 | source |
| Item instance identity | `C_Item.GetItemGUID(ItemLocation)` (non-optional WOWGUID), `C_Item.DoesItemExist`; `ItemLocation:CreateFromBagAndSlot` from Blizzard_ObjectAPI (no game-type restriction). Shatter scans bags for the GUID rather than using `C_Item.GetItemLocation`. If it yields nothing, every copy of the item is held back from Solo and the Mail disenchant is refused | dump 2210, 2235; Blizzard_ObjectAPI/Mainline/ItemLocation.lua | source; **measure in game** (GUID stable across a drag and a bag sort) |
| Mail frames | `InboxFrame`, `OpenMailFrame`, `MailFrameTab1/2` exist; Blizzard_MailFrame is not LOD | MailFrame.xml | source |
| Class colour (Glass UI's class body) | `UnitClass("player")` → name, filename, id; `C_ClassColor.GetClassColor(filename)` → a colorRGB with `r`, `g`, `b` | dump 6405, 768 | source |
| Bags | 0-4 unchanged, `NUM_BAG_SLOTS` = 4, reagent bag 5 | guide s3 | measured (guide) |
| SavedVariables | load back since 70009 | guide s1; Shatter's load stamps on 70334 (above) | measured (70334); 70532 pending |

Persistence canary: `ShatterDB.loadStamps` gains one `{ time, build }` per login (capped at 30).
After a FULL client exit, a list that never grows past one entry means SavedVariables are not
being read back on that build.

"source" = read from the dump or Blizzard source; still needs an in-game check before it is
"measured". Update this table when an in-game check settles a row.
