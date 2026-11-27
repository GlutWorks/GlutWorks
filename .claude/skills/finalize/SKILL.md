---
name: finalize
description: Run the GlutWorks finalization process on the current branch before a PR is considered done - sandboxed headless server checks, then a recorded playtest by GPT-6.1-Terra, with the report and media written into the PR body. Use when a feature or fix is ready, when asked to finalize, test, or playtest a branch, or before asking for review.
---

Run from the repository root, with the work committed:

```
harness/gw finalize --pr <number> --focus "<what the change is meant to let a player do>"
```

- Write the PR body yourself as a few lines that say what the change does for a player or
  an admin, and nothing else: no file lists, no test logs, no verification section. The
  harness adds the evidence below it (a status line, one short video, one screenshot per
  thing that works). Name the specific things in `--focus`; the playtest shows one
  screenshot for each.
- No PR yet: omit `--pr`; the report is written to `.gw/report.md`. Open the PR, then run
  `harness/gw publish --pr <number>` to post the same results.
- Quick loop while developing: `harness/gw lint` (a second), `harness/gw dump items <id>` (resolved definitions), `harness/gw headless --compare origin/main` (about 80 seconds).
- Exit status 0 means no new headless failures and a playtest verdict of pass. Read
  `.gw/report.md` either way and relay what it says, including a playtest that did not run.
- The playtest is there to show what happened, not to assign work. Do not start fixing its
  findings on your own and do not re-run it in a loop until it passes.
  - A `BLOCKER` means a thing the change is meant to do did not work. Confirm it yourself
    first; the playtester can be wrong. Then it is your call, or the call of whoever you
    are working for, whether to fix it now, open an issue, or accept it.
  - A `NOTE` is a suggestion, usually about visuals or wording, sometimes mistaken. Relay
    the ones worth knowing. Fix one only if it is clearly in scope and cheap; otherwise
    leave it or open an issue (`gh issue create`).
- A failure listed as "already failing on base" is not caused by the branch. Do not fix it
  in the same PR unless asked.
- When the change adds a mechanic the generic checks cannot see, add a check for it (see
  `harness/README.md`, "Adding a check") in the same PR.
- `harness/gw doctor` explains anything missing. Never work around a missing game client by
  claiming the playtest passed; report it as not run.
