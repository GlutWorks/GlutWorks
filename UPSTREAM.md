# Vendored upstream code

| Path | Upstream | Pinned at | Local changes |
|---|---|---|---|
| `helix/` | https://github.com/nebulouscloud/helix | `bb8bf86988b980d576419597ae6b966ee939e409` (2026-10-27) | Our fork: the changes below. |
| `ixhl2rp/schema`, `ixhl2rp/entities` | https://github.com/nebulouscloud/helix-hl2rp | forked from `e1377d0` (2022-04-11) | Edited in place; this is the project's own schema. |

## Our changes to `helix/`

`helix/` is our fork of Helix. A problem in the framework is fixed where it is, in `helix/`; game
behaviour goes in a plugin under `ixhl2rp/plugins`. Each change to `helix/` is a pull request of its
own titled `helix: ...` (so once squashed, `git log --grep '^helix:'` lists them), comes with a check
in the harness, and gets a row here.

| Change | Why |
|---|---|
| Storage access is held by the server: a player acts on a container, corpse or searched inventory only once the search has finished and while they're within reach (`maxDistance`, 128 by default) of its entity, alive and on the same character; the server closes it for them otherwise. Items moved between inventories need access at both ends. | Access was granted before the search finished and taken away only when the client said it had closed, so a modified client kept a searched player's inventory and money from anywhere, and could put items into any loaded inventory. |

To update Helix, apply upstream's changes between the pin and the new commit onto `helix/`, from a
clone of upstream: `git diff <pin> <new> > helix.patch`, then here
`git apply -3 --directory=helix helix.patch`. Resolve any conflict with our changes, update the pin,
and run `harness/gw finalize`.
