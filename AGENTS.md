# Shatter (Forever) Agent Instructions

## Project
Shatter is a standalone guided-disenchanting addon. **This repository is the World of Warcraft:
Forever build** (Interface `16001`, Lua 5.1): Vanilla content on Blizzard's Retail (Mainline)
codebase. It was forked with full history from the TBC Anniversary addon at
`Spotnick2/Shatter@25886ea` (branch `phase-3-mail-storyboard-refactor`); the TBC addon lives on
in `C:\Projects\Shatter` and is maintained separately - do not port changes back and forth
without being asked.

It must stay lightweight, native-feeling, and independent of ElvUI, TSM, Postal, Gargul, or other
heavy runtime dependencies.

## Forever first
- **The porting guide is canonical:** `C:\Projects\References\PORTING-TBC-TO-FOREVER.md`. Read the
  sections you touch. New addon-agnostic findings go there; Shatter-specific ones go in
  `docs/forever-api-notes.md`.
- **The API dump for the measured build:** `C:\Projects\References\forever-api-1.60.1.70291.md`.
  `Constants.MEASURED_ON_BUILD` must match it (and the literal in the tests).
- **The client's own UI source:** `C:\Projects\wow-ui-source` (`forever` branch). Read
  `SecureTemplates.lua`, `Blizzard_MailFrame`, etc. before reasoning about Blizzard behaviour.
- **Removed globals go through `Shatter.API`** (`Compat.lua`), never bare and never injected into
  `_G`. Struct-vs-tuple matters: `C_Container.GetContainerItemInfo` returns a struct,
  `C_Item.GetItemInfo` keeps the Classic tuple and returns nothing on a cache miss.
- **Content is Vanilla:** level cap 60, profession cap 300, no Outland materials or items.
- **Measured beats reasoned.** A function in the dump is not a working function; probe in game.
- **Persistence is verified only by a full client exit**, never by `/reload`.
- When `GetBuildInfo()` changes: re-dump the API (AltStable's `Tools/ForeverAPIDump`), diff,
  and land a PR titled `Measured on 1.60.1.NNNNN: ...` that bumps `MEASURED_ON_BUILD`.

## Hard Constraints
- Do not design or implement unattended gameplay automation.
- Do not bypass protected action restrictions.
- Actions that require player interaction must be modeled as a visible guided next action.
- The primary workflow should remain one clear button, one user click, one safe action.
- Mailbox and trade workflows must be delayed, event-driven, and recoverable.
- Do not assume mail, loot, bag, or trade state changes are instant.
- Simulation mode must never cast Disenchant, use an item, send mail, place trade items, or consume
  inventory. It is for development-only fake result recording.

## UI Direction
- Match the AltTracker style: dark translucent charcoal panels, thin black borders, clean
  typography, yellow active text, and restrained cyan/blue accents.
- Use native frames and APIs. Do not require ElvUI. Keep the UI compact enough to sit near the
  mailbox or trade window.
- The main frame supports persisted geometry under `ShatterDB.settings.window`; preserve the
  bottom-right grip behavior when changing layout code.
- Settings support Global and Personal profiles. `Database:GetSettings()` returns the active
  profile; do not read `ShatterDB.settings` directly. Personal profiles live under
  `ShatterDB.characterSettings[characterKey]`.
- Solo layout defaults are 660x440 with a 620x400 minimum and 900x650 maximum
  (`SetResizeBounds`). Do not lower these bounds without re-testing Expected Materials, Value,
  Session, Generated, footer buttons, Summary, and Settings at reset and minimum sizes.
- The main frame is the parent of a secure button, so it is **protected**: in combat the client
  refuses to show, hide, move, resize or rescale it. Record the request and apply it on
  `PLAYER_REGEN_ENABLED`.

## Implementation Defaults
- Interface target: Forever `16001`. Addon namespace `Shatter`, SavedVariables `ShatterDB`.
- Disenchant spell id: `13262`. Resolve its name with `C_Spell.GetSpellName(13262)` (localized);
  gate on `C_SpellBook.IsSpellInSpellBook(13262)`.
- Prefer small modules and explicit state machines over hidden background processing.
- Keep `/shatter sim` available. In the UI, simulation is a debug/development setting.
- Solo bag scans must be event-driven through `SoloMode:ScheduleScan(reason, delay)`. Do not
  rescan from UI rendering or frame visibility loops.
- Queue ordering is saved under `ShatterDB.settings.queueOrder` with per-mode keys. Keep FIFO/LIFO
  stable through `Session:AssignQueueSequence(item)`.
- The real `Shatter Next` action uses a secure macro button: a `SecureActionButtonTemplate` button
  with `*type1 = "macro"` and `*macrotext1` set during `PreClick`. Register **both** edges
  (`"AnyUp", "AnyDown"`) and set no `typerelease`; the client acts on exactly one edge
  (`down == useOnKeyDown`). Shatter's own PreClick/PostClick side effects must run only for the
  left button on that edge, and the macro must be disarmed after each click. Direct
  `CastSpellByName` / `C_Container.UseContainerItem` calls from addon code are protected.
- The Shatter-owned cast/progress bar lives in `UI/MainFrame.lua`. It may use `OnUpdate` only while
  visible for an active cast, result wait, simulation progress, or resize scale drag.
- The minimap button is Shatter-owned in `UI/Minimap.lua` with no external library.
- Disenchant estimates live in `Data/DisenchantTables.lua`: Shatter-owned compact Vanilla rules.
  Do not copy TSM or Enchantrix data.
- Optional pricing lives in `Integrations/AuctionData.lua` and stays best-effort only
  (Auctionator supports Forever; TSM does not load on this client).
- Expected value filters must degrade safely: no price never removes an eligible item.
- Mail Mode is an auto-activated durable batch session (`MAIL_SHOW` creates/resumes
  `sessions.activeMail`; only an explicit `Close Session` archives it). Mail sessions are
  character-scoped in `sessions.byCharacter[characterKey]`. The Input Queue is item-based.
  Destructive mail actions stay behind their safety gate until queue ownership and attachment
  identity are proven (port plan M5). `Mail/MailSender.lua` stays a blocked scaffold.
- Before implementing Mail return/sending, inspect `C:\Projects\PrimalMailer` for API lessons; do
  not copy its code. Re-run SPEC.md Phase 0 mail validation on Forever first.
- Raid / Trade Mode remains a disabled placeholder until Mail Mode is accepted.
- Shatter hard-gates initialization behind the Disenchant spell. Characters without it get slash
  feedback and no active UI/event behaviour.
- Character names carry a surname on this client ("First Surname"); never key on a first name.

## Build, test, deploy
- `pwsh tests/run.ps1` - luac -p over every Lua file, then every `tests/test_*.lua` under Lua 5.1
  (`C:\Program Files (x86)\Lua\5.1`). Must be green before every push.
- `tests/wow_stubs.lua` models **Forever, not Classic**: strict globals (reading an unstubbed global
  errors), strict widgets (no catch-all methods), and a list of known absences. Never add a stub
  because a test failed; confirm the API in the dump or source first.
- `pwsh Tools/deploy.ps1` copies the TOC, LICENSE and every TOC-listed file to
  `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\Shatter`, preserving
  relative paths, and refuses the `_anniversary_` client. After each implementation iteration,
  deploy and tell the user whether `/reload` is enough (a brand-new addon folder or new TOC entry
  needs a full client restart).
- In game: `/console scriptErrors 1` (errors are off by default on this client).

## Repository Practices
- Workflow: issue -> branch -> PR -> Codex review (`gpt-6-astra`, high effort) -> merge. See
  `docs/WORKFLOW.md`.
- Keep changes scoped to the current milestone.
- Do not copy proprietary addon data or UI code from TSM, Postal, Gargul, or other addons.
- Update `CHANGELOG.md` for user-visible changes.
- Keep packaging compatible with CurseForge `.pkgmeta`; CI dry-runs the BigWigs packager and checks
  the zip holds exactly the TOC's files plus LICENSE.
- **Releases:** tags are `v0.2.<buildnumber>-alpha`, where `<buildnumber>` is the commit count
  after the release metadata commit. (0.2 keeps Forever versions distinct from the TBC addon's
  0.1 line.) Keep `## Version: @project-version@`. Add a top changelog entry, commit, tag, push the
  branch, then the tag. Never push inherited TBC tags to this repo.
- No CurseForge project ID yet: the Forever project (flavor `forever`, game version type 88568)
  and its webhook must be created by the owner before the first release; then add
  `## X-Curse-Project-ID`. Check the real CurseForge artifact, not only the CI dry run.
