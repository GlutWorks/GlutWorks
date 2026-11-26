---
name: finalize
description: Run the GlutWorks finalization process on the current branch before a PR is considered done - sandboxed headless server checks, then a recorded playtest by GPT-6.2-Sol, with the report and media written into the PR body. Use when a feature or fix is ready, when asked to finalize, test, or playtest a branch, or before asking for review.
---

Run from the repository root, with the work committed:

```
harness/gw finalize --pr <number> --focus "<what the change is meant to let a player do>"
```

- No PR yet: omit `--pr`; the report is written to `.gw/report.md`. Open the PR, then run
  `harness/gw publish --pr <number>` to post the same results.
- Quick loop while developing: `harness/gw headless --compare origin/main` (about 80 seconds).
- Exit status 0 means no new headless failures and a playtest verdict of pass. Read
  `.gw/report.md` either way and relay what it says, including a playtest that did not run.
- A failure listed as "already failing on base" is not caused by the branch. Do not fix it
  in the same PR unless asked.
- When the change adds a mechanic the generic checks cannot see, add a check for it (see
  `harness/README.md`, "Adding a check") in the same PR.
- `harness/gw doctor` explains anything missing. Never work around a missing game client by
  claiming the playtest passed; report it as not run.
