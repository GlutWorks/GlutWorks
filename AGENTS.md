# GlutWorks

Garry's Mod gamemodes folder: the Helix framework (`helix/`) and the HL2RP schema with the
project's plugins (`ixhl2rp/`).

Before a change is done, run `harness/gw finalize` (see `harness/README.md`). It boots the
server in a sandbox, runs the checks against the merge-base, and records a playtest.
`harness/gw headless --compare origin/main` is the quick version.

Keep pull request descriptions short: a few lines on what the change does. `finalize` adds
a status line, a short video and one screenshot per specific thing below that; do not add
test logs, file lists or long write-ups.

Open every pull request as a draft (`gh pr create --draft`) and mark it ready
(`gh pr ready`) only when `finalize` has passed and you would be content to see it merged
exactly as it stands. An open pull request that is not a draft is presumed mergeable at any
time and may be merged without anyone asking first. If one needs more work after all, put
it back to draft (`gh pr ready --undo`) before pushing to it.

The playtest reports what happened; it does not decide the work. Only a blocker on the
specific thing a change is for counts against it. Its other remarks are suggestions and may
be wrong: whoever implements or orchestrates the change chooses whether to act, and an
issue is often the better place for them than the same PR.
