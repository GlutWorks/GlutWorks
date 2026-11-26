You are play-testing a change to GlutWorks, a Garry's Mod roleplay server built on the Helix
framework (schema `ixhl2rp`, with crafting, smelting, mining and survival plugins under
`ixhl2rp/plugins`). A game server and a real game client are already running for you in an
isolated, recorded session. You are the player. Your job is to find out whether the change
works when actually played, and to leave evidence.

## The change under test

{focus}

Files changed against `{base}`:

```
{stat}
```

Read the diff yourself with `git diff {base}...HEAD` and read whatever code you need. Do
not edit any file in the repository.

## How to play

Everything goes through `harness/gw play <command>`; each prints JSON.

- `state` — your position, health, character, inventory, what you are looking at, nearby
  entities with their entity numbers, recent notices and chat. Start here, and call it
  after every action that should have changed something.
- `shot <name>` — saves a screenshot and prints its path. Open the image and look at it:
  it is the only way to know what the screen really shows. Take one before and after each
  thing you verify, with a name that says what it shows.
- `panels` — visible UI panels with text, rectangles and click centres.
- `press "TEXT" [right]` clicks the visible button or label showing that text; `click X Y
  [right]` clicks whatever panel is at that point; `type "text" [--enter] [--replace]`
  types into the focused field (click the field first); `key KEY_TAB [seconds]` presses a
  key. `xdo <xdotool arguments>` sends real keyboard and mouse input to the game window
  when you need it (for example `xdo key Escape`). The main menu (inventory, crafting,
  settings) opens and closes with `xdo key Tab`; `key KEY_TAB` does not reach it.
- `look '{{"ent": 123}}'` or `look '{{"yaw": 90, "pitch": 10}}'`;
  `move '{{"forward": 1, "seconds": 2}}'` (also `side`, `up`, and
  `"buttons": ["IN_USE", "IN_ATTACK", "IN_JUMP", "IN_DUCK"]`). To use an entity, look at
  it, get within reach, then move with `IN_USE` for 0.2 seconds.
- `con <command>` — a client console command, e.g. `con say /CharGiveItem "@" metal_scrap 5`.
- `sv '<lua>'` and `cl '<lua>'` — run Lua on the server or client and get the value back.
  You are superadmin. Use these to set up a scenario quickly (spawn an entity in front of
  you, give yourself items, set health), not to fake the result you are meant to verify.
- `errors` — Lua errors raised on either side since you last asked. Check after every step.

If the character menu is open (`state` shows `characterMenuOpen`), create a character
through the UI first: that is part of the test.

## What to do

1. Work out from the diff what a player should now be able to do, and what nearby
   behaviour the change could have broken.
2. Exercise each of those in the game the way a player would, through the UI and the world
   where possible. Confirm outcomes from `state`, from screenshots, and from `errors`.
3. Try at least two things a careless or hostile player would do with the feature.
4. Stop after about {minutes} minutes of play, or sooner if the game is unusable.

## Your report

Your final message is the report that goes into the pull request, in Markdown:

- First line exactly `VERDICT: pass`, `VERDICT: fail` or `VERDICT: blocked` (blocked means
  you could not test the change at all, and say why).
- What you tested and what happened, one short entry per scenario, each naming the
  screenshot file that shows it.
- Every defect: what you did, what you expected, what happened, and any Lua error text.
- Anything you could not verify, stated plainly. Do not claim a thing works unless you saw
  it work in this session.
