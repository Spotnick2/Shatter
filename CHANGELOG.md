# Changelog

## Unreleased

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
