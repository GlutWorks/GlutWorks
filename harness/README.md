# GlutWorks test harness

One command takes a branch through the finalization process:

```
harness/gw finalize --pr <number> --focus "what this change is meant to do"
```

It runs two stages and posts the result on the pull request.

1. **Headless stage.** Boots a dedicated server on this checkout with no network, lets Helix
   create a bot character, and runs the checks in `addon/gw_harness/lua/gw_harness/checks/`:
   every plugin loaded, every Lua file compiles (client files included), every item can be
   instanced and spawned, every scripted entity spawns, recipes name real items, stations
   are real entities, plus the behaviour checks each area has added (stacking, crafting,
   stations, survival, schema permissions). It then does the same for the merge-base and
   **fails only on failures the branch introduced**; failures already on the base are
   listed as known. About 40 seconds per boot without the Workshop content, a few minutes
   with it.
2. **Play stage.** Starts a private headless Wayland session (sway) in which the real game
   client hosts the gamemode as a listen server, with a screen recorder running, then
   hands the session to a playtest agent (GPT-6.1-Terra through `codex exec`; `--model` and
   `--effort` change it) that plays the change through `harness/gw play ...`, takes
   screenshots, and reports what happened. A Claude model (`--model claude-opus-5-5`) runs
   through `claude -p` instead, allowed only `harness/gw play ...` and reading its
   screenshots. It is billed to `ANTHROPIC_API_KEY` if set, else to the `ant` CLI's
   sign-in (`ant auth login`, an API organization), else to the machine's Claude Code
   login; the first two run `--bare`, without the machine's own hooks or `CLAUDE.md` files.
   The run's cost is printed and kept in `.gw/play/playtest.json`.

The result is written into the pull request body between two markers, replacing the
previous run, and it is short on purpose:

- one status line (commit, server checks, playtest verdict),
- one short video: a captioned clip for each highlight the playtest marked, joined into a reel,
- one screenshot and one sentence for each thing the playtest saw working (eight at most),
- blockers, if any, and the playtester's notes, collapsed.

The full check list, the playtest agent's whole report, every screenshot and the whole
session recording stay in `.gw/` on the machine that ran it. The part of the PR body above
the markers is the author's: a few lines saying what the change does, nothing else.

The playtest shows what happened; it does not direct the work. Its verdict is `fail` only
for a **blocker**: one of the specific things the change is meant to do cannot be done,
damages the player's items, money or character, or raises a Lua error. Everything else it
says is a **note**: a suggestion about wording or visuals, something outside the change, or
simply a mistake by the playtester. What to do about a blocker or a note, and whether to do
anything, is the author's decision. Opening an issue (`gh issue create`) instead of fixing
it in the same PR is always an option.

`--skip-play` runs stage 1 only. `--dry-run` builds the report but uploads and edits
nothing. Without `--pr` the report is left in `.gw/report.md`.

The media is uploaded as GitHub attachments with `gh pr edit --attach`, which uses the token
`gh` is already signed in with and needs gh 2.99 or newer and push access to the repository;
nothing is committed or pushed to any branch. With an older gh the report is still written
and the media stays in `.gw/play/` for you to drag in.

Before either stage, `finalize` lints the changed files (below) and stops on a syntax error.

## Lint

```
harness/gw lint                  # .lua files the branch changed, about a quarter of a second
harness/gw lint --all            # every tracked .lua file under ixhl2rp/ and harness/
harness/gw lint helix/plugins/doors   # named files or folders; the only way helix/ is linted
```

It runs [glualint](https://github.com/FPtje/GLuaFixer) (pinned in `gw`, fetched into the
tools prefix on first use), which understands Garry's Mod Lua. The default set is every
`.lua` file under `ixhl2rp/` and `harness/` that differs from the merge-base with
`origin/main` (`--base` changes it), untracked files included. Each finding is printed as
`path:line: severity: message`.

A syntax error fails the command. Warnings never do, and only the ones on lines the branch
changed are printed; `--all-warnings` shows the rest. `glualint.json` turns off the style
rules that disagree with the Helix style (parentheses around conditions, `!` and `&&`
mixed with `and`, whitespace) and keeps the ones that catch mistakes: unused variables,
shadowing, deprecated calls, empty blocks, duplicate keys.

It also warns when `docs/plugins.md` lacks a row for a plugin (or has one for a plugin that
is gone) and when a hook the project fires is neither Helix's nor in `docs/hooks.lua`.

## Registry dump

```
harness/gw dump                       # build or reuse .gw/registry.json, count per section
harness/gw dump items                 # the IDs in a section
harness/gw dump items metal_scrap     # one entry as JSON; a wrong ID suggests close ones
```

The registry is what the running gamemode holds once bases, plugins and overrides are
applied: plugins, items, recipes, stations, commands, config, factions, classes, flags,
the gamemode's scripted entities and weapons, and which plugins implement each hook. Items,
recipes, stations, plugins and entities carry the `file` they come from; items list the
recipes that require, use as a tool, or produce them.

Building it boots the server in its own sandbox layer (about 15 seconds; it can run while a
headless run of the same checkout does). The file is reused while HEAD is the same and
nothing under `helix/`, `ixhl2rp/` or `harness/addon/` has changed since; `--fresh` boots
anyway. It boots without the Workshop content, which none of these definitions depend on;
`--addons` mounts it. It is the server's view: client-only functions are not in it.

## Setup

```
harness/gw setup     # dedicated server and Workshop content via SteamCMD,
                     # sway/wf-recorder/grim and glualint into a private prefix
harness/gw doctor    # what is present and what is missing
```

Nothing is installed system-wide and nothing needs root. Everything lives under
`~/.local/share/gw-harness` (override with `GW_HARNESS_HOME`), about 14 GB with the Workshop content.

The Workshop content the gamemode expects (models, weapons, PAC3 and so on) is listed in
`addons.json`. `setup` downloads each entry once and both stages mount them read-only.
`required: false` entries are skipped. `GW_NO_ADDONS=1` runs without any of it, which
boots faster; models then render as errors and external weapon classes do not exist, so
use it for a quick loop and not for the final run.

The play stage also needs the Garry's Mod client (Steam app 4000) installed in a Steam
library, and Steam running: the client proves ownership to it. The headless stage needs
neither. From a terminal, with Steam running:

```
steam +app_install 4000
steam +app_set_config 4000 BetaKey x86-64    # the 64-bit branch
```

Use the 64-bit branch. The default 32-bit client idles at 3.3 GB of its 4 GB address
space once the Workshop content is mounted and dies ("failed to lock index buffer") the
first time a menu needs a blur buffer. Run `harness/gw setup` again after switching
branches so the libraries that client needs are collected.

## Isolation

Each checkout gets its own run, keyed by its path, so worktrees can run at the same time.
A run is a bubblewrap sandbox with:

- no network: only its own loopback. The one exception is the play stage's relay of
  Steam's local IPC port (127.0.0.1:57343), without which the client refuses to start;
- a copy-on-write view of the game install, discarded at the start of the next run, so
  the SQLite database and data files always start empty;
- the checkout's `helix/` and `ixhl2rp/` mounted read-only over the server's gamemodes
  (the server's own current `base`/`sandbox` are used, not the 2022 copies in this repo;
  `GW_MOUNT=all` mounts those too);
- its own Wayland compositor, Xwayland and `XDG_RUNTIME_DIR`, none of them visible to the
  desktop session, and no access to the home directory.

Output goes to `.gw/` in the checkout (git-ignored).

## Driving a session by hand

```
harness/gw play start            # compositor + recorder + client hosting the gamemode
harness/gw play state            # player, character, inventory, surroundings, focus, open options (JSON)
harness/gw play shot crafting    # screenshot -> .gw/play/shots/
harness/gw play panels           # visible UI with click coordinates
harness/gw play press "Create"   # click the visible button or label with that text
harness/gw play click 640 360    # click whatever panel is at that point
harness/gw play type "John Doe" --replace   # type into the focused field (click it first)
harness/gw play key KEY_TAB 0.5  # hold a key
harness/gw play xdo key Escape   # raw xdotool input to the game window
harness/gw play xdo key e        # tap Use: the obvious action (take, open, talk)
harness/gw play xdo keydown e sleep 0.6   # hold Use: the options open beside the thing
harness/gw play choose "Pick Up" # aim at that option and confirm it, as a player does
                                 # (tap e at a workbench, then choose "Makarov" to craft it;
                                 # tap e at a vendor, then choose "Buy Metal Scrap")
harness/gw play xdo keyup e      # let go of Use (on no option: cancel)
harness/gw play look '{"ent": 123}'
harness/gw play move '{"forward": 1, "seconds": 2, "buttons": ["IN_USE"]}'
harness/gw play sv 'ix.item.Spawn("metal_scrap", Entity(1):GetPos())'
harness/gw play errors           # Lua errors on both sides since last asked
harness/gw play stop             # stops and encodes .gw/play/session.mp4
```

Only one play session with the real client can run on a machine at a time (one Steam
account, one game). `harness/gw play start --client-cmd "sleep 3600"` starts a dedicated
server with no client instead, for poking server Lua with `play sv`; any number of those
can run side by side.

`harness/gw play --help` lists the rest. `harness/playtest.md` is the brief the playtest
agent receives.

## Adding a check

Checks live in `addon/gw_harness/lua/gw_harness/checks/`, one file per plugin or tight
feature group, named after it (`40_stacking.lua`, `56_datafile.lua`, `60_schema.lua`), so
`ls` there shows where the existing checks for something are. A new check goes in the file for
the plugin or feature it exercises, or in a new file named for it; the header of each file
says what it covers. Helpers used by more than one file (`Scoped`, `ResetBot`, the `S` bots and
snapshots, ...) are defined once in `00_support.lua` on `GWH.Lib`, whose header says which
near-twin to pick; take them as locals instead of copying them.

```lua
GWH.Check("ores can be smelted", function(fail)
	if (!ix.item.list.iron_ore) then fail("iron_ore is not registered") end
end)
```

`fail(message)` records a failure; a thrown error counts as one too. `GWH.Bot()` returns a
bot with a character and an inventory to act on.

Files load in name order and all checks run in that order against one server and one bot, so
each check puts back what it changes: 10-20 framework and content, 30 compat, 40-59 plugins,
60 the schema (its last check is a real map cleanup), 90 teardown. The extra bots some files
share are kicked in `60_schema.lua` and `90_teardown.lua`, so files using them sort before
those. Keep a check's name when moving it: `--compare` matches failures by name.

## Known limits

- The play stage is a listen server, so the player is the host. A dedicated server with a
  separate client would be closer to production, but inside the network sandbox the
  dedicated server's replies to the client's handshake never arrive (plain UDP between
  other processes there works). The headless stage is what covers the dedicated server.
- The client is started with `-noworkshop`, so it uses only the content in `addons.json`
  and does not touch the account's Workshop subscriptions.
- The 32-bit client shows a "SetLocale failed" box at startup; the session clicks it away.
  The 64-bit client does not.
