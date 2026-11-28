# GlutWorks test harness

One command takes a branch through the finalization process:

```
harness/gw finalize --pr <number>
```

It reads the change's claims (below), runs two stages and posts the result on the pull
request.

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
   `--effort` change it) that plays the claims through `harness/gw play ...`, takes
   screenshots, and reports what happened against each one. A Claude model (`--model
   claude-opus-5-5`) runs through `claude -p` instead, allowed only `harness/gw play ...` and reading its
   screenshots. It is billed to `ANTHROPIC_API_KEY` if set, else to the `ant` CLI's
   sign-in (`ant auth login`, an API organization), else to the machine's Claude Code
   login; the first two run `--bare`, without the machine's own hooks or `CLAUDE.md` files.
   The run's cost is printed and kept in `.gw/play/playtest.json`.

The verdict (`pass`, `fail`, or `blocked` when nothing could be judged) is posted as the
commit status `gw/finalize` on the head commit, for example `130 checks pass · playtest
pass`. A failure to post it is a warning. The rest is written into the pull request body
between two markers, replacing the previous run, and it is short on purpose:

- one short video: a captioned clip for each highlight the playtest marked, joined into a reel,
- one screenshot and one sentence for each claim the playtest saw (eight at most), and the
  claims it did not show,
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

`--skip-play` runs stage 1 only. `--dry-run` builds the report and prints the commit
status but uploads, edits and posts nothing. Without `--pr` the report is left in
`.gw/report.md`. When a person's session (below) was recorded at the current commit, it is
the playtest: `finalize` uses its marks instead of starting the agent. Other checkouts
can run their own play stage at the same time.

## Claims and the packet

The author describes the change as a few claims in `.gw/claims.json` (or `--claims
<file>`):

```json
{
  "summary": "optional: a few lines on what the change does",
  "claims": [
    { "title": "Trade in world",
      "statement": "Trading happens beside the vendor; choosing a row trades one unit.",
      "paths": ["ixhl2rp/plugins/vendorpanel/"] }
  ]
}
```

`title` and `statement` are required. `paths` are the git pathspecs (files, folders,
globs) that hold the claim's code, never line numbers. A claim's id is a slug of its title
(`trade-in-world`); give an explicit `id` only to keep it across a retitle. The claims
describe the change as it is today: rewrite, split, merge or drop them whenever it is
better explained another way. Without a claims file, `--focus "<text>"` becomes a single
claim.

The playtest agent is given the claims and reports each highlight and blocker against a
claim id. A highlight that names no claim becomes a note with its evidence. Marks made in
the session (below) go the same way: a mark naming a claim is evidence on it (a clip of
exactly its range, its screenshot, or for a moment without one the recording's frame at
that moment, captioned with its note) and makes the claim `seen`; any other mark is a
note with that evidence. A person's session sets `status.playtest.by` to `person`.

The packet has no place yet for some of what a mark records, so it is left out rather
than given new fields: a mark's `region`, who made each mark or note (only the session as a
whole is `by` a person or an agent), a caption on a clip, and the moment an image was taken
in the recording. `.gw/play/marks.jsonl` keeps all of it.

`harness/gw packet` (run by `finalize`) assembles `.gw/packet/`: `packet.json` with the
revision, status, each claim's result (`seen`, `not-seen` when a blocker names it,
`untested` otherwise), evidence and paths, plus the screenshots and clips under `media/`,
each named by its SHA-256 and written once. A clip is exactly its `startMs`..`endMs` of the
session recording, in real time and without a caption, so it keeps its hash while that
stretch is unchanged; the recording itself is hashed but not copied. The pull request body
is rendered from the packet, with its reel cut separately, captioned and sped up.

The media is uploaded as GitHub attachments with `gh pr edit --attach`, which uses the token
`gh` is already signed in with and needs gh 2.99 or newer and push access to the repository;
nothing is committed or pushed to any branch. With an older gh the report is still written
and the media stays in `.gw/play/` for you to drag in.

Before either stage, `finalize` lints the changed files (below) and stops on a syntax error.

## Lint

```
harness/gw lint                  # .lua files the branch changed, about a quarter of a second
harness/gw lint --all            # every tracked .lua file under ixhl2rp/ and harness/
harness/gw lint helix/plugins/doors   # named files or folders: how the rest of helix/ is linted
```

It runs [glualint](https://github.com/FPtje/GLuaFixer) (pinned in `gw`, fetched into the
tools prefix on first use), which understands Garry's Mod Lua. The default set is every
`.lua` file under `ixhl2rp/`, `harness/` and `helix/` that differs from the merge-base with
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
                     # sway/wf-recorder/grim/wayvnc, Selkies and glualint into a private prefix
harness/gw doctor    # what is present and what is missing (--json: [{id, state, detail, fix}])
```

Nothing is installed system-wide and nothing needs root. Everything lives under
`~/.local/share/gw-harness` (see Environment below), about 14 GB with the Workshop content.
The session tools come from the Arch package mirrors through `pacman -Sp`, only those the
prefix lacks. A download that fails with 404 means the system's package list is older than
the mirror; it works again after the next `pacman -Syu`. Selkies, which streams a person's
session, is its project's own Arch package (pinned with its checksum in `gw`, 52 MB to fetch
and 262 MB unpacked): a Python environment for the system's Python 3.14, with its encoders,
that uses the system's Mesa, libva and Wayland libraries. When the system's Python moves to
another version, `doctor` says so and the pin in `gw` needs a newer Selkies.

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

- no network: only its own loopback. The exceptions are relays through Unix sockets in a
  folder only the sandbox and this user can reach: Steam's local IPC port (127.0.0.1:57343)
  in, without which the client refuses to start, and a streamed session's port out (below),
  over TCP and, for WebRTC, the same port over UDP. Everything in the stream, the server
  included, runs in the sandbox, which can make no outbound connection. The relays set
  TCP_NODELAY (the game's Steam traffic is many small writes; without it the game ran at
  under a fifth of its frame rate), which `doctor` checks. A play session started with
  `--net direct` gives this up (see Streamed sessions);
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

A checkout has one play session at a time, because the session owns `.gw/play`. Sessions of
different checkouts run side by side, real game clients included: each has its own sandbox,
display, network and writable game files, and the clients share the machine's one Steam
login. `harness/gw play start --client-cmd "sleep 3600"` starts a dedicated server with no
client instead, for poking server Lua with `play sv`.

`harness/gw play --help` lists the rest. `harness/playtest.md` is the brief the playtest
agent receives.

## Sessions and marks

The same session as verbs that answer with one JSON document on standard output (progress
goes to standard error), for a program such as T3 Code to call:

```
harness/gw session start --by person   # a person's session: always streamed (below)
harness/gw session start               # an agent's: not streamed
harness/gw session status              # the running session and how to attach
harness/gw mark "the vendor menu flickered" --last 10 --claim trade-in-world
harness/gw session stop                # finishes the recording; the marks stay
harness/gw packet                      # the marks become claim evidence and notes
```

`session start` takes the options of `play start` and answers with the session's `id`,
`by`, `net` and `outbound` (the network profile, below), `stream`, `recorded`, `recording`
(the raw `.gw/play/session.mkv`, whose times every mark and clip use; null when not recorded),
`marks` (the marks file), `attach` (how to reach a streamed session) and `locks`. `session
stop` answers with the recording, its duration, the encoded `video` and the number of
marks. A failure answers `{"ok": false, "error": ...}` with a non-zero exit code.

**No lock between checkouts.** `locks` is the list of machine-wide resources a session
needs, for a caller that queues sessions; it is always empty here. Starting a second
session in the same checkout fails until the first is stopped.

**Marks.** A session started with `--no-record` (the default with `--net direct`) has no
recording, so `gw mark` refuses it with an error rather than record a moment nothing can show,
and `finalize` does not take such a session as the playtest. `gw mark NOTE` (also `gw play mark`) records a moment of the running session
against its recording: by default now, with `--last SECONDS` the range ending now (for
"that thing that just happened"), or with `--from`/`--to` a range in recording seconds,
which also works once the session has stopped. `--shot` takes a screenshot as well,
`--region x,y,w,h` names the part of the screen as fractions, `--claim ID` the claim it is
about, `--by person|agent` who made it (default: who the session is by). Each mark is one
line appended to `.gw/play/marks.jsonl` and printed as JSON. A moment has `atMs`, and
a range has `startMs` and `endMs`. A mark takes about 60 ms, or
about 150 ms with a screenshot, and any number of processes can mark one session at once.
A mark's time is right to a tenth of a second: the recorder notes when it started.

## Streamed sessions

A person plays a session from any machine on the tailnet, in a browser, never in a window on
this desktop. `session start --by person` (or `--streamed`) runs [Selkies](https://github.com/selkies-project/selkies)
inside the sandbox. It captures the session's private compositor through its screencopy
protocol, encodes on the GPU where it can (VA-API H.264 here) and puts keyboard and mouse
into the compositor through its virtual input protocols; no device of the machine is used.
`gw` relays one port on this machine's Tailscale address to it (127.0.0.1 without Tailscale;
`--listen ADDRESS` chooses, and the answer says when that is every interface): 5900 plus the
slot, over TCP for the page and over UDP for WebRTC's media. Without a slot, the harness
checks ports 5900–5999 from a starting point derived from the checkout path. Every session
gets a new password. With `--net direct`, Selkies binds that port itself (Network profiles,
below). `attach` says what to open:

```json
"attach": {"protocol": "selkies", "transport": "webrtc", "host": "100.x.y.z", "port": 5901,
           "udpPort": 5901, "url": "http://100.x.y.z:5901/", "user": "player",
           "password": "<16 characters>", "network": "tailnet", "pointer": "relative",
           "pointerLock": "Control+Shift+click on the picture, or gaming mode (Control+Shift+X)"}
```

Open the URL in Chrome, Edge or Firefox and log in with that user and password. The picture
keeps the session's size (`--res`) and is scaled to the browser window; resizing the window
never resizes the game. For mouse-look, take the pointer: Control+Shift+click on the picture,
or gaming mode (Control+Shift+X, also in the side menu). The game then gets the mouse's own
movement, exactly, and a still mouse moves nothing. A single Escape gives the pointer back to
the browser: over plain HTTP the browser has no keyboard lock, so that Escape does not reach
the game (a second one does). Without the pointer taken, the mouse is an absolute pointer
that still works in menus.

Transports (`--stream`):

- `webrtc` (the default): frames are pushed at the game's rate over UDP whatever the round
  trip. On a stand-in with a 51 ms round trip added in the relay, 57–59 frames a second
  were decoded with about 3.5 Mbit/s. No STUN or TURN server is used: the page is offered
  the listen address directly.
- `websockets`: everything over the one TCP port. Over plain HTTP the browser gives the page
  no WebCodecs, so the picture falls back to JPEG; it is meant for a page served over HTTPS
  or from localhost, such as one proxied by another app.
- `vnc`: [wayvnc](https://github.com/any1/wayvnc) on the same port, for any VNC viewer
  ([TigerVNC](https://tigervnc.org) with H.264: `vncviewer PreferredEncoding=H.264 host::port`,
  empty user name). Menus work; mouse-look does not, because a VNC viewer sends absolute
  positions, which the compositor turns into turning for as long as the cursor is off the
  lock point. Frames are asked for one at a time, so the rate falls with the round trip.
  wayvnc offers only RSA-AES security here, so gtk-vnc viewers (`remote-viewer`, GNOME
  Connections) cannot connect.

The session restarts the stream server whenever it exits; the page reconnects. There is no
sound: the session has no audio server.

Network profiles (`--net`), for any play session:

- `isolated` (the default): as under Isolation, the session has no outbound network; Steam
  and the stream cross the boundary through `portproxy.py`. Recorded unless `--no-record`.
- `direct`: the session shares this machine's network namespace, so **the game, its server
  and the stream server can make outbound connections**, and anything they listen on is
  reachable as if run on the host. There are no relays: the game talks to Steam directly and
  takes this checkout's ports on loopback (27100 + slot, client port 800 above it), and
  Selkies binds 5900 + slot itself, over TCP on the listen address plus 127.0.0.1 (its own
  signalling client) and over UDP on the address it offers. No STUN or TURN, and the login is
  as above. Not recorded unless `--record`. Use it when a person plays and frame rate
  matters: the relays and the recorder each cost the game frames.

`session start`/`status` say which profile a session runs in (`net`, `outbound`, `recorded`)
and whether the stream is relayed (`attach.relayed`, `attach.bind`).

## Environment

Nothing has to be set. A caller such as T3 Code can set:

| Variable | Default | What it is |
|---|---|---|
| `T3CODE_CACHE_PATH` | `GW_HARNESS_HOME`, else `~/.local/share/gw-harness` | the harness home: server, tools, Workshop content, run state |
| `T3CODE_OUTPUT_PATH` | `GW_OUT`, else `.gw/` in the checkout | where every result is written |
| `T3CODE_SLOT` | none | a number from 0 to 99, unique among the checkouts running at once: the stream port is 5900 + slot (TCP, and UDP for WebRTC) and the session's server port 27100 + slot |

The checkout is always the one `harness/gw` is in. If `T3CODE_WORKTREE_PATH` names another
folder, the harness says so on standard error and still uses its own. The names other than
`GW_HARNESS_HOME` and `GW_OUT` are provisional until the companion app settles them.

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
