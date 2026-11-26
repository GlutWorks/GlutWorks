# Vendored upstream code

| Path | Upstream | Pinned at | Local changes |
|---|---|---|---|
| `helix/` | https://github.com/nebulouscloud/helix | `bb8bf86988b980d576419597ae6b966ee939e409` (2026-10-27) | None. Keep it that way: change framework behaviour from a plugin under `ixhl2rp/plugins`, never by editing `helix/`. |
| `ixhl2rp/schema`, `ixhl2rp/entities` | https://github.com/nebulouscloud/helix-hl2rp | forked from `e1377d0` (2022-04-11) | Edited in place; this is the project's own schema. |

To update Helix, replace the contents of `helix/` with an export of the new upstream
commit, update the pin above, and run `harness/gw finalize`.
