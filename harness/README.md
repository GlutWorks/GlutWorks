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
harness/gw setup     # dedicated server and Workshop content via SteamCMD,
                     # sway/wf-recorder/grim into a private prefix
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
harness/gw play state            # player, character, inventory, surroundings (JSON)
harness/gw play shot crafting    # screenshot -> .gw/play/shots/
harness/gw play panels           # visible UI with click coordinates
harness/gw play press "Create"   # click the visible button or label with that text
harness/gw play click 640 360    # click whatever panel is at that point
harness/gw play type "John Doe" --replace   # type into the focused field (click it first)
harness/gw play key KEY_TAB 0.5  # hold a key
harness/gw play xdo key Escape   # raw xdotool input to the game window
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
- The client is started with `-noworkshop`, so it uses only the content in `addons.json`
  and does not touch the account's Workshop subscriptions.
- The 32-bit client shows a "SetLocale failed" box at startup; the session clicks it away.
  The 64-bit client does not.
- `publish` has been run only as a dry run. The attachment upload follows GitHub's web
  upload flow and has not been exercised against a real session cookie.
