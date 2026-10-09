# CLAUDE.md - Claude-specific overlay

`AGENTS.md` is the shared baseline (project rules, build/test/deploy, workflow). This file only
adds Claude-specific bits. Where the two overlap, AGENTS.md wins.

## Adversarial review - prefer a different family

PR code review is done **manually by the owner**; do not run Codex (or any automated review) on
PRs or post review comments unasked.

For a second opinion on a plan or design, when the owner asks for one, use **Codex** via the `/codex-consult` skill, with
`-m gpt-6-astra -c model_reasoning_effort=high` (the owner's standing choice for this repo). Fall
back to Fable only when Codex is unavailable.

Strongest loop: Claude drafts (knows the repo) -> Codex attacks -> Claude reconciles (tells real
objections from context gaps). Take its bug-catching seriously; be skeptical when a cold model
wants to ratchet complexity - this is a single-owner addon.

## This codebase's specifics (feed these to any external reviewer)

- **Forever, not TBC.** Vanilla content on the Mainline API. Suggestions citing TBC Classic API
  behaviour are usually stale.
- **`Compat.lua` -> `Shatter.API`** is deliberately not injected into `_G`; the struct-vs-tuple
  split is load-bearing.
- **The secure `Shatter Next` path** (UI/MainFrame.lua PreClick/PostClick, Disenchant.lua): one
  left click on the activating edge, one cast, one item; disarmed afterwards; nothing in combat
  that touches the protected main frame.
- **`ShatterDB` shape** is persisted and loads back on this client; don't break it.
- **Test stubs model Forever.** A stub returning a Classic-shaped tuple, or a widget method the
  client lacks, makes a broken port pass - stub fidelity is part of the review surface.
