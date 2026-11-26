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
2. **Play stage.** Starts a private headless Wayland session (sway) in which the real game
   client hosts the gamemode as a listen server, with a screen recorder running, then
   hands the session to a playtest agent (GPT-6.2-Sol through `codex exec`) that plays the
   change through `harness/gw play ...`, takes screenshots, and writes a verdict.

The results are written into the pull request body between two markers, replacing the
previous run. The recording and screenshots are uploaded as GitHub attachments and
embedded there; nothing is committed or pushed to any branch.

`--skip-play` runs stage 1 only. `--dry-run` builds the report but uploads and edits
nothing. Without `--pr` the report is left in `.gw/report.md`.

GitHub has no token API for attachments: they belong to a signed-in web session. To let
`harness/gw publish` attach media, save the value of your `user_session` cookie for
github.com in `~/.config/gw-harness/github-session` (mode 600). Without it the report is
still written into the PR body and the media stays in `.gw/play/` for you to drag in.

## Setup

```
harness/gw setup     # dedicated server via SteamCMD, sway/wf-recorder/grim into a private prefix
harness/gw doctor    # what is present and what is missing
```

Nothing is installed system-wide and nothing needs root. Everything lives under
`~/.local/share/gw-harness` (override with `GW_HARNESS_HOME`), about 7 GB.

The play stage also needs the Garry's Mod client (Steam app 4000) installed in a Steam
library, and Steam running: the client proves ownership to it. `steam +app_install 4000`
installs it from a terminal. The headless stage needs neither.

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

## Known limits

- The play stage is a listen server, so the player is the host. A dedicated server with a
  separate client would be closer to production, but inside the network sandbox the
  dedicated server's replies to the client's handshake never arrive (plain UDP between
  other processes there works). The headless stage is what covers the dedicated server.
- Launching the client makes Steam download the account's subscribed Workshop addons
  into its own library, as launching the game normally does.
- The 32-bit client shows a "SetLocale failed" box at startup; the session clicks it away.
- `publish` has been run only as a dry run. The attachment upload follows GitHub's web
  upload flow and has not been exercised against a real session cookie.
