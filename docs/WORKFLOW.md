# Workflow

Single maintainer, so this is deliberately light. The one non-obvious step is the Codex review.

## The loop

```
issue  ->  branch  ->  PR  ->  Codex review  ->  address  ->  merge
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
5. **Run the Codex review** (below) and post its findings as a PR comment.
6. **Address or rebut** each finding in the thread, deploy (`pwsh Tools/deploy.ps1`), check in
   game, then merge.

## Codex review on a PR

Codex is a *different model family*, so the value is decorrelated blind spots. It is a local CLI;
the review is generated locally and posted to the PR for the record. This repo uses
`gpt-6-astra` at high effort.

```bash
git fetch origin main
git diff origin/main...HEAD > "$SCRATCH/pr.diff"
# write "$SCRATCH/codex-prompt.txt": files to read + numbered questions (see below)
timeout 900 codex exec -m gpt-6-astra -c model_reasoning_effort=high \
  --ephemeral --skip-git-repo-check -s read-only \
  -o "$SCRATCH/codex-verdict.md" \
  < "$SCRATCH/codex-prompt.txt" > "$SCRATCH/codex-progress.log" 2>&1
gh pr comment <N> --body-file "$SCRATCH/codex-verdict.md"
```

Gotchas, all learned the hard way in the sibling repos:

- **Feed the prompt via `< file` on stdin.** `codex exec "prompt"` in a non-TTY hangs forever.
- **Read the answer from `-o`, not stdout.** stdout is progress noise.
- **`--ephemeral`**, or a long run balloons a session log under `~/.codex/sessions/`.
- **Never say "review the code" and "do not run commands" together.** Codex reads files *through*
  shell commands. Say: "You may run read-only shell commands to read the files listed. The
  sandbox is read-only; do not try to edit."

### Prompt shape

- The **established facts** it must not re-litigate: interface 16001, Vanilla content on the
  Retail API, the measured return shapes, the porting guide path
  (`C:\Projects\References\PORTING-TBC-TO-FOREVER.md`), the API dump path.
- The **files to read**, by path, and the diff.
- **Numbered questions**, silent-wrong-behaviour first.
- A closing note that this is a single-maintainer addon: right-size the findings.

Take its bug-catching seriously; be skeptical when it wants to add abstraction. It is a reviewer,
not an oracle.

## Fallback

If the `codex` CLI is unavailable, use Fable for the adversarial pass - same family, so a weaker
adversary, but better than no independent review.
