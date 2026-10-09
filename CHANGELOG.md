# Changelog

## Forever port (unreleased)

- Glass skins: Shatter's window and the Mail launch panel can be **Clear glass** (the new default), **Smoked glass** or **Flat** (the previous opaque look), matching the other Glass addons. Choose under Settings > Look or with `/shatter skin clear|smoked|flat`; the change applies immediately, even in combat. The glass comes from the embedded LibGlass-1.0. Without the library (a git checkout without `Libs`), Shatter stays Flat and Settings says so.
- The Mail tab is now marked as the current tab in the Mail view, and hovering the Mail or Raid tab no longer leaves it highlighted.
- Expected materials learn from your disenchants: each real disenchant read from the loot window is counted for its quality, armor/weapon and item-level bracket, and from 20 disenchants a bracket's estimate blends the measured odds with the built-in table (shown as "measured"); the more you measure, the more it follows your results, and a rare material you have not seen yet keeps a share. Items above item level 92 are measured separately from Vanilla items. `/shatter yields` lists them, `/shatter yields reset` clears them.
- Shatter now targets World of Warcraft: Forever (Interface 16001). This repository was forked with full history from the TBC Anniversary addon at `Spotnick2/Shatter@25886ea`; the TBC entries below are that addon's history.
- Ported item, spell, container and addon calls to the Forever (Retail) APIs through a `Shatter.API` adapter; the bag scan no longer errors on the removed `GetItemInfo`.
- The Enchanting gate now asks the spellbook for Disenchant directly, so real enchanters are no longer switched off; learning or unlearning Enchanting mid-session takes effect without a reload.
- Soulbound detection reads the container's bound flag instead of scanning (localized) tooltip text.
- Events the client refuses are reported in chat; if one Shatter needs to track a disenchant result is missing, Shatter Next stays disabled.
- Shatter Next now casts Disenchant by spell ID and targets the queued bag slot through Blizzard's secure targeting, so it works on non-English clients and a cast that fails to start can no longer use (equip) the item.
- Shatter Next acts on exactly one left click whatever your "cast on key down" setting is; right clicks and presses released off the button do nothing, and the button is never left armed between clicks.
- Shatter Next refuses (with a status message) while another spell is waiting for a target, while casting or channeling, for a locked item, and in combat.
- The Shatter window no longer raises blocked-action errors in combat: opening, closing, moving and resizing wait until combat ends, and Escape does not close it during combat.
- Expected materials now follow Vanilla disenchanting: Outland materials (Arcane Dust, Planar Essences, Prismatic Shards, Void Crystal) are gone, high-level greens show Illusion Dust and Greater Eternal Essence, blues Large Brilliant Shards, and epics Nexus Crystals. Items above Vanilla's item levels show "Expected Materials (unverified)".
- `/shatter sim` produces Vanilla materials from the same rules.
- Corrected uncommon shard chances (5% at 16-20, 10% at 21-25, 5% from 51) and weapon dust chances from 51.
- Mail Mode safety: a bag scan can no longer replace the mail disenchant queue, Shatter Next only disenchants items from the queue of the view you are in, a take is re-matched against the inbox as it is now, and a received item is identified by the bag slot it newly occupies (an identical item you already owned is never mistaken for it).
- A received mail item stays the sender's when you move or sort it: Shatter follows it by its item GUID, keeps it out of the Solo queue (also after a trip to the bank), and never disenchants a copy of your own that ends up in its old slot. Switching to Solo is no longer undone by a background inbox rescan.
- Mail sessions: Start New Session no longer replaces an active session (continue it, or close it first); Continue keeps changes made on the mailbox panel, and a narrower mail filter drops listed items you have not taken yet; a funnel recipient typed without pressing Enter is used; nothing but Start New Session creates a session.
- Mail Keep mode records the materials you keep instead of waiting for a return to yourself, so the session can complete.
- Postal "Selected mails" sessions keep the mails you selected when the inbox shifts, never take an unchecked identical mail instead (that one is left for you to take by hand), and switching to them on Continue uses the mails checked now; Postal is detected only when installed, loaded at most once per mailbox visit, and the selected count follows your checkbox clicks.
- Mail sessions saved before sessions were per character go back to the character that started them.
- Mail Mode reads all 16 attachment slots of a mail, and waits for item data the client has not cached yet instead of skipping those attachments.
- Mail actions (taking attachments and disenchanting mail items) are off until the mail flow has been validated on Forever; `/shatter mailtest` enables them for the current session.
- On a client build other than the one Shatter was measured on (1.60.1.70334), Shatter prints a one-line notice when it first activates (at login, or later if the spellbook loads late or login happened in combat).
- Price lookups through other addons (Auctionator, Auctioneer, TSM) can no longer raise errors in Shatter; a failing lookup simply shows no price.
- Dragging the minimap button now follows the cursor correctly when the minimap is scaled in Edit Mode.
- Added the Forever development scaffold: strict-stub Lua 5.1 test suite, TOC-driven deploy script for the `_classic_beta_` client, and a package-check CI dry run.

## TBC Anniversary history (before the fork)

## Unreleased

- Improved Mail launch panel UX with tighter layout flow, clearer section spacing, and persistent funnel selector visibility.
- Improved Postal integration detection for Mail launch filters and now surfaces a Postal selected-mail option when Postal is installed, with a clear inactive-state hint when its Select module controls are unavailable.
- Polished the mailbox-attached Shatter Mail launch panel layout: tighter spacing, clearer primary/secondary session action styling, dropdown-style Funnel placeholder, and footer text kept fully inside panel bounds.
- Started the storyboard Mail Mode refactor with a mailbox-attached Shatter Mail launch panel and expand/collapse toggle button.
- Stopped auto-opening the large Mail session window on mailbox open; mailbox now shows the launch panel first.
- Scoped active Mail sessions by character instead of account-wide shared `activeMail`.
- Added startup gating so Shatter stays inactive on characters without Enchanting/Disenchant trained.
- Implemented Pass 2 mailbox launch-panel configuration with mail selection filters (`All`, `Mail from`, and Postal `Selected mails`) and return destination options (`Original`, `Funnel`, `Keep materials`).
- Wired `Start New Session` and `Continue Existing Session` to open/resume Mail sessions from the launch panel and apply saved selection/destination rules.
- Kept pending Mail Mode input items visible across mailbox refreshes when the client temporarily stops exposing attachment metadata.
- Fixed Mail Mode primary button enablement so `Take Attachments` receives both label and enabled state correctly.
- Kept Mail Mode's `Take Attachments` action clickable when selected item rows exist and made mailbox-frame detection more defensive.
- Clarified Mail Mode's first action by showing `Open Mailbox` when attachment intake is paused and the Blizzard mailbox is not open.
- Refined Phase 3 Mail Mode so the Input Queue is item-based while preserving source mail metadata internally.
- Started Phase 3 Mail Mode on a dedicated branch with durable mail sessions, mailbox auto-activation, Input/Output Queue UI scaffolding, read-only inbox scans, and guided attachment intake.
- Added a Settings profile selector with Global as the default and per-character Personal profiles.
- Reduced normal debug chat noise by moving routine disenchant flow and scan details to trace logging.
- Added explanatory tooltips to Settings controls.
- Restored the right-side inspection panel layout with compact Session and Generated sections.
- Added coin icon formatting to right-pane expected disenchant value.

## v0.1.22-alpha - 2026-05-16

- Moved Generated materials and session counters under the left queue and simplified the right pane to item details only.
- Increased the default/reset Solo window size and minimum bounds for the richer Phase 1 details layout.
- Rebalanced the Solo details pane so expected material names remain readable and Value stays available.
- Refined the Solo details pane into a compact inspection/results panel with generated material icons.
- Made the selected item details body scrollable and switched expected material rows to a safer two-line layout.
- Added queue item counts and a scrollable Solo queue list for larger inventories.
- Polished the selected item details pane with Expected Materials, Value, and Session sections.
- Added Phase 2 disenchant material estimates for Solo queue items using Shatter-owned Classic/TBC disenchant rules.
- Added optional expected value calculation from installed pricing addons: TSM, Auctioneer, or Auctionator.
- Added Settings controls for expected value filtering and value thresholds.
- Updated item detail text to show expected materials and value source when available.

## v0.1.12-alpha - 2026-05-16

- Tagged the first Shatter Phase 1 alpha release for CurseForge packaging and repository distribution.

## 0.1.0 - 2026-05-16

- Initialized the Shatter repository.
- Added CurseForge-style packaging metadata.
- Added project guardrails in `AGENTS.md`.
- Added the initial product and technical specification in `SPEC.md`.
- Added modular addon files for the Phase 1 Solo Mode foundation.
- Added saved variables, bag scanning, queue state, AltTracker-style UI shell, settings panel, and guided disenchant button scaffolding.
- Added development simulation mode for recording fake disenchant results without destroying items.
- Tightened Solo Mode eligibility so trade goods, enchanting materials, cloth bolts, and other non-equipment no longer enter the disenchant queue.
- Changed Settings into a real view state so it no longer renders over the queue and detail panels.
- Polished the Phase 1 Solo UI with a compact frame, header icon placeholder, clearer active/disabled mode tabs, improved queue row styling, user-facing item details, and a summary view.
- Hardened Skip and Ignore behavior with session tracking so skipped items stay out of the current queue while ignored items are removed immediately and persisted.
- Moved simulation behind debug/dev mode; real mode keeps the guided secure Disenchant macro flow and clearer status messages.
- Added a subtle header `SIMULATION` badge and explicit status warning only while debug simulation is enabled.
- Hardened real `Shatter Next` pending handling with timeout recovery, item-exists checks, bag-update result detection, and event debug logging.
- Added a bottom-right resize grip with drag-to-resize, Shift-drag-to-scale, right-click reset, tooltip guidance, responsive Solo layout, and persisted size/scale/position settings.
- Reworked Solo Mode scanning to use debounced event-driven scheduling with scan reasons, recursive-scan protection, quieter debug logging, and optional trace logging.
- Polished the Phase 1 Solo UI with a smaller default/reset size, lighter simulation badge, clearer diagonal resize grip, and tighter queue/detail alignment.
- Mirrored TSM's secure macro button pattern for guided disenchanting by using `*type1` / `*macrotext1`, client-aware click registration, and `/cast Disenchant;` plus `/use bag slot` macro text.
- Added a compact Shatter-owned cast/progress bar for disenchant casting, waiting-for-result, and simulation progress.
- Added a Solo queue order setting with per-mode saved-variable structure for Bag / Slot, FIFO, and LIFO ordering.
- Added CurseForge project metadata for project ID `1545161`.
- Fixed Settings view clipping at the smaller default size by moving settings controls into a reserved scrollable content area and hiding footer status text while Settings is open.
- Added a native Shatter minimap button with drag positioning, left-click toggle, right-click Settings, and a Settings checkbox to show or hide it.
