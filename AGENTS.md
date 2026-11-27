# GlutWorks

Garry's Mod gamemodes folder: the Helix framework (`helix/`) and the HL2RP schema with the
project's plugins (`ixhl2rp/`).

Before a change is done, run `harness/gw finalize` (see `harness/README.md`). It boots the
server in a sandbox, runs the checks against the merge-base, and records a playtest.
`harness/gw headless --compare origin/main` is the quick version.

Keep pull request descriptions short: a few lines on what the change does. `finalize` adds
a status line, a short video and one screenshot per specific thing below that; do not add
test logs, file lists or long write-ups.

The playtest reports what happened; it does not decide the work. Only a blocker on the
specific thing a change is for counts against it. Its other remarks are suggestions and may
be wrong: whoever implements or orchestrates the change chooses whether to act, and an
issue is often the better place for them than the same PR.
