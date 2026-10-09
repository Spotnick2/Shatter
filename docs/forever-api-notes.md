# Forever API notes (Shatter-specific)

Measured or source-verified facts this addon depends on. Addon-agnostic findings belong in the
canonical guide, `C:\Projects\References\PORTING-TBC-TO-FOREVER.md`; this file only records what
Shatter itself relies on, with the evidence.

Build: **1.60.1.70291** (`_classic_beta_\.build.info`, `References\forever-api-1.60.1.70291.md`).
Client UI source: `C:\Projects\wow-ui-source`, `forever` branch (`version.txt` 70245).

| Shatter needs | On Forever | Evidence | Status |
|---|---|---|---|
| Item info | `C_Item.GetItemInfo` (Classic 18-tuple; zero returns on cache miss), `C_Item.GetItemInfoInstant` (7-tuple) | dump 2240-2241; guide s2 | source |
| Container | `C_Container.*`; `GetContainerItemInfo` returns a struct with `isBound` | dump 1167-1182, 8790 | source |
| Disenchant known | `C_SpellBook.IsSpellInSpellBook(13262)`; bare `IsSpellKnown` only with deprecation fallbacks | dump 3627; `Blizzard_DeprecatedSpellBook` | source |
| Localized spell name | `C_Spell.GetSpellName(13262)` (by ID always resolves) | dump 3543; guide s2 | source |
| Secure macro button | `SecureActionButtonTemplate`, `type=macro` -> `C_Macro.RunMacroText`; register both edges | SecureTemplates.lua:450, 724, 802; guide s3 | source; **measure in game** |
| Resize bounds | `SetResizeBounds(minW, minH, maxW, maxH)`; `SetMinResize`/`SetMaxResize` gone | dump 6114 | source |
| Mail receive slots | `ATTACHMENTS_MAX` = 16 receive, 12 send | Blizzard_MailFrame/MailFrame.lua:3-4 | source |
| Mail frames | `InboxFrame`, `OpenMailFrame`, `MailFrameTab1/2` exist; Blizzard_MailFrame is not LOD | MailFrame.xml | source |
| Bags | 0-4 unchanged, `NUM_BAG_SLOTS` = 4, reagent bag 5 | guide s3 | measured (guide) |
| SavedVariables | load back since 70009 | guide s1 | measured (guide) |

"source" = read from the dump or Blizzard source; still needs an in-game check before it is
"measured". Update this table when an in-game check settles a row.
