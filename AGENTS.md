# GlutWorks

Garry's Mod gamemodes folder: the Helix framework (`helix/`) and the HL2RP schema with the
project's plugins (`ixhl2rp/`).

## Where things are

- `helix/` is our fork of Helix: its upstream pin and our changes are in `UPSTREAM.md`,
  which says how a change to it is made. Fix a framework problem there; game behaviour goes
  in a plugin. Its hooks are documented in `helix/docs/hooks/plugin.lua`.
- `ixhl2rp/schema` is the project's own schema: factions, classes, items, Combine logic.
- `ixhl2rp/plugins` holds 59 plugins; 29 began as third-party code and most of those have
  been changed here. `docs/plugins.md` has one row per plugin (what it owns, where it came
  from, what it depends on) and the rules that cut across plugins. Read it before deciding
  where a change goes.
- `docs/hooks.lua` documents the hooks the project fires itself, with arguments and what a
  return value does.
- `harness/` is the test harness. Its checks are in
  `harness/addon/gw_harness/lua/gw_harness/checks/`, one file per plugin or feature.

The UI rule: nothing is drawn in screen space for players during play. State is shown in the world, felt
(full-screen post effects, sound) or said in one private chat line (notices already are; see `immersion`);
short lists of choices go on `ix.worldui` as text, with no icons or glyphs. Nothing floats, nothing pops up. Exceptions: staff
tools, the character and Tab menus, the handheld inventory datapad, reading and typed-prompt windows,
Combine terminals and the Combine visor; while the Tab or character menu is up
(they hide the chat), a notice is Helix's corner notice. `immersionHideHUD` turns the hidden stock HUD back on
for comparison; the chat's look, the typing indicator and pruned notices do not follow it. Details in
`docs/plugins.md`.

The rules that are easiest to break:

- A stackable item (`ITEM.stackLimit`) is one instance holding `data.quantity`. Count, give,
  take and spawn through `ix.stack` (`ixhl2rp/plugins/stacking`), not `HasItem`,
  `GetItemCount`, `Remove` or `ix.item.Spawn`.
- Crafting is two plugins: `ixcraft` has the engine, the station panel, the recipes and the station
  definitions; `glutcraft` has the materials, station items, smelting and placement.
- A hook that returns anything but nil stops every other implementation, the schema's
  included. Return nothing unless that is the point.
- The file prefix is the realm: `sv_` server, `cl_` client, `sh_` both.
- Only plugins go directly in `ixhl2rp/plugins/`. Helix loads every file there as one, a
  README included.

## While working

```
harness/gw lint                     # under a second: syntax errors, warnings on changed lines
harness/gw dump items metal_scrap   # what the game resolved: base, stack limit, price, recipes
harness/gw headless --only "stacking"   # the checks whose name contains the text, one boot
```

`dump` also takes `recipes`, `stations`, `commands`, `config`, `plugins`, `hooks`,
`entities`, `factions`, `classes` and `flags`; without an ID it lists the section. To run
Lua against a live server, `harness/gw play start --client-cmd "sleep 3600"` and then
`harness/gw play sv '<lua>'`. `harness/README.md` has the rest.

A new plugin gets a row in `docs/plugins.md` and a new project-fired hook an entry in
`docs/hooks.lua`; `lint` warns when either is missing.

## Before a change is done

Run `harness/gw finalize` (see `harness/README.md`). It boots the server in a sandbox, runs
the checks against the merge-base, and records a playtest.
`harness/gw headless --compare origin/main` is the quick version.

Keep pull request descriptions short: a few lines on what the change does. `finalize` adds
a status line, a short video and one screenshot per specific thing below that; do not add
test logs, file lists or long write-ups.

Open every pull request as a draft (`gh pr create --draft`) and mark it ready
(`gh pr ready`) only when `finalize` has passed and you would be content to see it merged
exactly as it stands. An open pull request that is not a draft is presumed mergeable at any
time and may be merged without anyone asking first. If one needs more work after all, put
it back to draft (`gh pr ready --undo`) before pushing to it.

Work split into pull requests that depend on each other goes up as a GitHub stack
(`gh stack link <bottom> ... <top>`, from the `github/gh-stack` extension), and is reported
as one stack, bottom to top, not as separate pull requests. Pull requests that do not
depend on each other are not a stack.

The playtest reports what happened; it does not decide the work. Only a blocker on the
specific thing a change is for counts against it. Its other remarks are suggestions and may
be wrong: whoever implements or orchestrates the change chooses whether to act, and an
issue is often the better place for them than the same PR.
