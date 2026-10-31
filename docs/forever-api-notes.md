# Forever API notes (Shatter-specific)

Measured or source-verified facts this addon depends on. Addon-agnostic findings belong in the
canonical guide, `C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md`; this file only records what
Shatter itself relies on, with the evidence.

Build: **1.60.1.70334** (`_classic_beta_\.build.info`, `References\Forever\api\forever-api-1.60.1.70334.md`).
Client UI source: `C:\Projects\WoW\wow-ui-source`, `forever` branch (`version.txt` 1.60.1.70291; no
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
| Equipment sets (#36) | `C_Container.GetContainerItemEquipmentSetInfo(bag, slot) -> inSet, setList`; `C_EquipmentSet.CanUseEquipmentSets`, `GetEquipmentSetIDs`; `EQUIPMENT_SETS_CHANGED` (dump 70532). `Shatter.API.IsInEquipmentSet` answers nil when `CanUseEquipmentSets()` isn't a plain true, or the slot call is absent, throws or isn't a plain boolean, and nothing is filtered then | dump 1168, 1561, 1569, 7233 | dump only; **measure in game** whether sets exist on Forever (ShatterProbe `sets`) |
| Keep item level (#37) | An item instance's level: `C_Item.GetCurrentItemLevel(ItemLocation)` (optional number), else `C_Item.GetDetailedItemLevelInfo(link)` (may return nothing); the generic `C_Item.GetItemInfo` level never stands in. Worn: slots 1-18 without the shirt (4), the tabard (19) not read; a worn item whose level can't be read declines Suggest (its data requested), only an empty slot is skipped. Bag items: the instance's level, from the bag slot; none readable is kept until it is | dump 2222, 2226, `GetInventoryItemLink`; Blizzard_ObjectAPI `ItemLocation` | dump only; **measure in game** that a worn slot and a bag item with a level of its own read as their tooltips, also above item level 60 (ShatterProbe `ilvl`) |
| Key binding (#35) | `Bindings.xml` `CLICK ShatterNextButton:LeftButton`, label `BINDING_NAME_*`; `GetBindingKey`, `UPDATE_BINDINGS` (dump 70532). A `CLICK` binding reaches a secure button registered for both edges, one press one action, **and acts on a hidden button** (Apotheca, measured on 70009 with `ActionButtonUseKeyDown` 1), so Shatter refuses a click on its hidden button in PreClick and PostClick. `SecureActionButton_OnClick` treats an addon-driven click as a key press, and with `useOnKeyDown=false` acts on the release | SecureTemplates.lua:802-818; Apotheca `docs/FOREVER-PROBE.md` | partly measured; **measure in game** that the key's release casts once, with the CVar at 0 and 1 (ShatterProbe `next`) |
| Resize bounds | `SetResizeBounds(minW, minH, maxW, maxH)`; `SetMinResize`/`SetMaxResize` gone | dump 6114 | source |
| Mail receive slots | `ATTACHMENTS_MAX` = 16 receive, 12 send | Blizzard_MailFrame/MailFrame.lua:3-4 | source |
| Item instance identity | `C_Item.GetItemGUID(ItemLocation)` (non-optional WOWGUID), `C_Item.DoesItemExist`; `ItemLocation:CreateFromBagAndSlot` from Blizzard_ObjectAPI (no game-type restriction). Shatter scans bags for the GUID rather than using `C_Item.GetItemLocation`. If it yields nothing, every copy of the item is held back from Solo and the Mail disenchant is refused | dump 2207, 2232; Blizzard_ObjectAPI/Mainline/ItemLocation.lua | source; **measure in game** (GUID stable across a drag and a bag sort) |
| Mail frames | `InboxFrame`, `OpenMailFrame`, `MailFrameTab1/2` exist; Blizzard_MailFrame is not LOD | MailFrame.xml | source |
| Mailbox open | `MailFrame` is shown and hidden by the player interaction manager (`MailFrame_Show` / `MailFrame_Hide`); `MailMixin:OnHide` doesn't hide its child `InboxFrame`, which stays `IsShown()` after the mailbox closes. Shatter answers from `MAIL_SHOW` / `MAIL_CLOSED` (and `MailFrame:IsVisible()` before either), never a child's `IsShown` (#26) | Blizzard_MailFrame/MailFrame.lua:49, 99-131 | source; **measure in game** (#31) |
| Class colour (Glass UI's class body) | `UnitClass("player")` → name, filename, id; `C_ClassColor.GetClassColor(filename)` → a colorRGB with `r`, `g`, `b` | dump 6405, 768 | source |
| Item tooltip hook | `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)` runs `fn(tooltip, tooltipData)` after the tooltip has added its lines, on every rebuild (a rebuild clears the lines first); `tooltipData.id` is the itemID; `Item` = 0; no way to remove a post call. `IsModifierKeyDown()` for the Shift/Alt/Ctrl mode | dump 33057, 5496; `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199, 294-298`; `TooltipUtil.lua:9`; `TooltipInfoSharedDocumentation.lua` | source; **measure in game** (which tooltips reach it: bags, chat links, loot, vendor, auction house) |
| Items that can't be disenchanted (#6) | The client's item data flags them: ItemSparse `Flags_0 & 0x8000` (ITEM_FLAG_NO_DISENCHANT). 1606 weapons/armor of quality 2-4 in an equip slot at 1.60.1.70532: enchanter-made wands, PvP insignias and rank gear, quest items. Shipped as `Data/NoDisenchant.lua` (`Tools/gen_no_disenchant.py`); `Constants.USE_NO_DISENCHANT_LIST` turns it off | wago.tools ItemSparse + Item, 1.60.1.70532 | data; **measure in game** before the next release (a flagged wand refused, an unflagged green accepted) |
| Disenchant loot brackets | ItemDisenchantLoot: weapon/armor, quality 2-3 from item level 5 to 99, epics from 40 to 99, **`SkillRequired` 0 on every row**. Not used for eligibility (a missing row isn't proof the server refuses), and no skill filter is built on it (#5) | wago.tools ItemDisenchantLoot, 1.60.1.70685 | data; **measure in game** (does the server refuse a high-level item at low skill?) |
| A Disenchant refusal's reason | `UNIT_SPELLCAST_FAILED(unit, castGUID, spellID)` has no reason; `UI_ERROR_MESSAGE(errorType, message)` carries the text, with no item or cast identity. Shatter traces every one, with the attempt then pending (or none) | dump 8244; `Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua` | source; **measure in game** (the errorType and text for "can't be disenchanted", and their order against FAILED) |
| Enchanting skill | `GetProfessions` returns nothing. `C_SkillInfo.GetNumSkillLines` + `GetSkillLineInfo(i)` return a SkillLineAttributes table (`skillID`, `rank`, `maxRank`, `isHeader`), measured by two sibling addons; `GetSkillLineInfoByID(333)` is unmeasured. Shatter doesn't read the skill yet (#5) | dump 3414-3417, 9141; AltStable `Compat.lua`, GlassPanel `Plugins/Professions` | source; **measure in game** |
| Bags | 0-4 unchanged, `NUM_BAG_SLOTS` = 4, reagent bag 5 | guide s3 | measured (guide) |
| SavedVariables | load back since 70009 | guide s1; Shatter's load stamps on 70334 (above) | measured (70334) |

Persistence canary: `ShatterDB.loadStamps` gains one `{ time, build }` per login (capped at 30).
After a FULL client exit, a list that never grows past one entry means SavedVariables are not
being read back on that build.

"source" = read from the dump or Blizzard source; still needs an in-game check before it is
"measured". Update this table when an in-game check settles a row.
