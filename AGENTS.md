# GlutWorks

Garry's Mod gamemodes folder: the Helix framework (`helix/`) and the HL2RP schema with the
project's plugins (`ixhl2rp/`).

Before a change is done, run `harness/gw finalize` (see `harness/README.md`). It boots the
server in a sandbox, runs the checks against the merge-base, and records a playtest.
`harness/gw headless --compare origin/main` is the quick version.
