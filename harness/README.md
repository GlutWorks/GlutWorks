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
   are real entities. It then does the same for the merge-base and **fails only on failures
   the branch introduced**; failures already on the base are listed as known. About 40
   seconds per boot.
2. **Play stage.** Starts a private headless Wayland session (sway) with the server, the
   real game client and a screen recorder, then hands the session to a playtest agent
   (GPT-6.2-Sol through `codex exec`) that plays the change through `harness/gw play ...`,
   takes screenshots, and writes a verdict. The recording, an inline preview and the
   screenshots go to the `gw-media` branch and are embedded in the PR comment.

`--skip-play` runs stage 1 only. `--dry-run` builds the report and the media commit but
pushes and posts nothing. Without `--pr` the report is left in `.gw/report.md`.

## Setup

```
harness/gw setup     # dedicated server via SteamCMD, sway/wf-recorder/grim into a private prefix
harness/gw doctor    # what is present and what is missing
```

Nothing is installed system-wide and nothing needs root. Everything lives under
`~/.local/share/gw-harness` (override with `GW_HARNESS_HOME`), about 7 GB.

The play stage also needs the Garry's Mod client (Steam app 4000) installed in a Steam
library and Steam running, in offline mode if you like, because the client checks
ownership with it. The headless stage needs neither.

## Isolation

Each checkout gets its own run, keyed by its path, so worktrees can run at the same time.
A run is a bubblewrap sandbox with:

- no network: only its own loopback, which is where the client reaches the server;
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
harness/gw play start            # compositor + server + recorder + client
harness/gw play state            # player, character, inventory, surroundings (JSON)
harness/gw play shot crafting    # screenshot -> .gw/play/shots/
harness/gw play panels           # visible UI with click coordinates
harness/gw play click 640 360
harness/gw play sv 'ix.item.Spawn("metal_scrap", Entity(1):GetPos())'
harness/gw play errors           # Lua errors on both sides since last asked
harness/gw play stop             # stops and encodes .gw/play/session.mp4
```

`harness/gw play --help` lists the rest. `harness/playtest.md` is the brief the playtest
agent receives.

## Adding a check

Drop a file in `addon/gw_harness/lua/gw_harness/checks/`:

```lua
GWH.Check("ores can be smelted", function(fail)
	if (!ix.item.list.iron_ore) then fail("iron_ore is not registered") end
end)
```

`fail(message)` records a failure; a thrown error counts as one too. `GWH.Bot()` returns a
bot with a character and an inventory to act on.

## Not yet verified

The play stage has been run end to end with a stand-in graphical client: the sandboxed
Wayland session, GPU rendering, recording, screenshots, the live server command channel
and the playtest agent's access to all of it are confirmed. Launching the actual Garry's
Mod client inside the sandbox, and the client-side commands (`state`, `panels`, `click`,
`move`, ...), have not been run, because the client was not installed on the machine this
was built on. Expect to adjust the launch line in `cmd_play_start` and possibly
`GW_PLAY_NET=host` if the client cannot reach Steam from inside the network sandbox.
