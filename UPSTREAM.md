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
| Storage access is held by the server: a player acts on a container, corpse or searched inventory only once the search has finished and while they're within reach (`maxDistance`, 128 by default) of its entity, alive and on the same character; the server closes it for them otherwise. Items moved between inventories need access at both ends. The storage view, closing, removes only its own two inventory panels, not whatever `ix.gui.inv1` points at by then. | Access was granted before the search finished and taken away only when the client said it had closed, so a modified client kept a searched player's inventory and money from anywhere, and could put items into any loaded inventory. Once the server closed one storage as another opened, the old view's cleanup, run after its fade, removed the new view's inventory panel. |
| Every placement is checked: `CanItemFit` keeps the whole item inside the grid on whole cells, and `Inventory:Add` checks a position its caller (or the client, through `Transfer`) gives. A client's inventory moves and item actions are rate limited (`ix.item.netBurst` 10, then `netPerSecond` 20). Items found outside their grid when an inventory loads are reported in the console. | The grid was bounded only on the right, and a given position wasn't checked at all, so a client could stack items on one cell or park them past the last row: unlimited room, and the items vanished at the next restart. Each move writes to the database, with no limit on how fast. |
| Saves happen in the tick of the change: `ix.data.SaveSoon` queues a save to run once at the end of the tick. Every setter of a saved character var queues the character's (`CHAR:SaveSoon`); the storage money handlers queue the container's on the other side; what `CharacterPreSave` hooks set during a save doesn't queue another; and a `CharacterPreSave` error is reported without stopping the save. The 300 s and 600 s timers stay as a backstop. | Items were written to the database at once, but character money only every 300 s and container money every 600 s. A crash refunded what a player bought, lost what they'd sold, and duplicated money taken out of a container. |
| The limits every item action and entity menu choice needs are the core's: `ix.item.CanInteract` (alive, with a character, not tied or ragdolled, a world item not another of your characters', a combined item reachable) and `ix.menu.CanInteract` (alive, within `ix.menu.reach`, 112, of the entity's nearest point). They run before `CanPlayerInteractItem` and `CanPlayerInteractEntity`, which can now only refuse. `GM:CanPlayerInteractItem` and `GM:CanPlayerInteractEntity` are gone, and so is glutcraft's override for stations. | The limits were the gamemode's own hook implementations, and Helix stops at the first hook that returns anything, so any plugin returning `true` switched them all off. glutcraft did, for stations, because the distance was measured to an entity's origin, which for a large station is inside the model. |

To update Helix, apply upstream's changes between the pin and the new commit onto `helix/`, from a
clone of upstream: `git diff <pin> <new> > helix.patch`, then here
`git apply -3 --directory=helix helix.patch`. Resolve any conflict with our changes, update the pin,
and run `harness/gw finalize`.
