# Shatter Agent Instructions

## Project
Shatter is a standalone World of Warcraft TBC Classic / Anniversary addon for guided disenchanting workflows. It must stay lightweight, native-feeling, and independent of ElvUI, TSM, Postal, Gargul, or other heavy runtime dependencies.

## Hard Constraints
- Do not design or implement unattended gameplay automation.
- Do not bypass protected action restrictions.
- Actions that require player interaction must be modeled as a visible guided next action.
- The primary workflow should remain one clear button, one user click, one safe action.
- Mailbox and trade workflows must be delayed, event-driven, and recoverable.
- Do not assume mail, loot, bag, or trade state changes are instant.
- Simulation mode must never cast Disenchant, use an item, send mail, place trade items, or consume inventory. It is for development-only fake result recording.

## UI Direction
- Match the AltTracker style: dark translucent charcoal panels, thin black borders, clean typography, yellow active text, and restrained cyan/blue accents.
- Use native WoW Classic frames and APIs.
- Do not require ElvUI.
- Keep the UI compact enough to sit near the mailbox or trade window.
- The main frame supports persisted geometry. Width, height, point, offsets, and scale live under `ShatterDB.settings.window`; preserve the bottom-right grip behavior when changing layout code.

## Implementation Defaults
- Interface target: TBC Anniversary `20505`.
- Addon namespace: `Shatter`.
- SavedVariables root: `ShatterDB`.
- Disenchant spell id: `13262`, but validate behavior in-game before relying on it.
- Prefer small modules and explicit state machines over hidden background processing.
- Before implementing Mail Mode or Raid/Trade Mode, run Phase 0 API validation from `SPEC.md`.
- Keep `/shatter sim` available during Phase 1 development so UI and queue work can be tested without destroying items.
- In the UI, simulation is a debug/development setting. Real MVP testing should use the guided `Shatter Next` secure button path unless explicitly testing debug simulation.
- Solo bag scans must be event-driven through `SoloMode:ScheduleScan(reason, delay)`. Do not rescan from UI rendering or frame visibility loops; normal debug should log meaningful scan changes only, while trace debug can log every scan/event.
- Queue ordering is saved under `ShatterDB.settings.queueOrder` with per-mode keys (`solo`, `mail`, `raid`). Phase 1 exposes only Solo ordering. Keep FIFO/LIFO stable through `Session:AssignQueueSequence(item)` rather than deriving those orders from whatever a fresh bag scan happens to return.
- The real `Shatter Next` action must use a secure macro button pattern, not direct protected calls. The primary button is a `SecureActionButtonTemplate` button with `*type1 = "macro"` and `*macrotext1` set during `PreClick`; it registers for `LeftButtonDown` or `LeftButtonUp` based on `ActionButtonUseKeyDown`. Direct `CastSpellByName`, `UseContainerItem`, or `C_Container.UseContainerItem` calls from addon code caused protected-action errors in TBC Anniversary.
- TSM Destroying's local implementation confirms the safe pattern for this client: set secure macro text like `/cast Disenchant;` followed by `/use bag slot` on the secure macro button before the hardware click executes. Do not copy TSM code or assets, but this API pattern is validated reference behavior.
- The Shatter-owned cast/progress bar lives in `UI/MainFrame.lua`. It may use `OnUpdate` only while visible for an active cast, result wait, simulation progress, or resize scale drag; it must clear `OnUpdate` when hidden or idle.
- Mail Mode and Raid / Trade Mode must remain disabled placeholders until Solo Mode is accepted as Phase 1 MVP.

## Repository Practices
- Keep changes scoped to the current phase.
- Do not copy proprietary addon data or UI code from TSM, Postal, Gargul, or other addons.
- Use reference addons only to understand API patterns and risks.
- Update `CHANGELOG.md` for user-visible changes.
- Keep packaging compatible with CurseForge `.pkgmeta`.
- After each implementation iteration, deploy the current repository to `C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\Shatter` and tell the user whether `/reload` is sufficient or whether a relog may be needed. Copy files by preserving their relative paths from the repo root; do not copy whole directories onto same-named existing destination directories, because that can create nested paths such as `UI\UI`.
