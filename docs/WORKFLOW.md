# Workflow

Single maintainer, so this is deliberately light.

## The loop

```
issue  ->  branch  ->  PR  ->  owner review  ->  address  ->  merge
```

1. **Pick an issue.** Milestones map to the port plan (M2 adapter + gate, M3 secure click,
   M4 Vanilla content, M5 Mail safety, M6 build check / integrations). Everything in
   `docs/forever-api-notes.md` and the porting guide is measured on the live client - treat it
   as fact.
2. **Branch off `main`**, named for the milestone: `m2/compat-gate`, `m3/secure-click`.
   Never commit directly to `main` once the scaffold is in.
3. **Before pushing:** `pwsh tests/run.ps1` green (luac over every Lua file + the strict-stub
   suite).
4. **Open a PR** with `Closes #N`.
5. **Code review is done manually by the owner.** Agents do not run automated PR reviews (Codex
   or otherwise) and do not post review comments on their own initiative.
6. **Address** the owner's review comments, deploy (`pwsh Tools/deploy.ps1`), check in game; the
   owner merges.

## Adversarial plan or design review (only when asked)

When the owner asks for a second opinion on a plan or design, use Codex through the
`/codex-consult` skill (`-m gpt-6-astra -c model_reasoning_effort=high`, read-only,
`--ephemeral`, prompt on stdin, answer from `-o`). Codex is a different model family, so the
value is decorrelated blind spots; it is a reviewer, not an oracle. If the `codex` CLI is
unavailable, say so and fall back to Fable.
