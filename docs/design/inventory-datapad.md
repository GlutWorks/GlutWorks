# Inventory on a datapad: proposal

Status: a proposal for discussion. Nothing here is implemented. This is the second round; what
changed from the first is at the end. The mockups are in `inventory-datapad-mockups.html` (open
it in a browser); the pull request that added this file shows them as images.

## The idea

The inventory is a device the character carries and raises to look at, in the way of a Fallout
Pip-Boy. Things are worn or stowed at places on the body: a belt and a sling for weapons, pockets
that come with garments, and bags. The device shows what is where, what it weighs, and how the
character is.

## Why a device

Two earlier attempts were dropped (pull request #20): a scrolling list on a world panel, then an
open case with item models in its cells.

- The list was indirect. Rows floating in the world were picked by aiming, which got worse with
  many items. A device has a cursor, keys, sorting and search.
- The icons were not immersive. A screen that shows a scan of the item's real model is part of
  the device's fiction; a pictogram on a panel is not.
- It keeps the UI rule. The screen is on an object in the character's hand, like a Combine
  terminal. Others see the character raise it and look down, and it cannot be used with tied
  hands.

## The views

- **Carry** is what opens first. Everything carried, grouped by the place it is in, as plain rows
  under a heading that says how full the place is. There are no slot boxes. The right side shows
  the selected thing: a scan of its model, where on the body it sits, and what can be done with
  it.
- **Carry with something open.** When a crate, a body or a cupboard is open, the right side
  becomes its contents, in the same rows. The character's own side does not change.
- **Body** is the whole character on the figure: what is worn and where, what is on the belt and
  back, and how they are (cold, wet, hurt, hungry, thirsty) in words, the way `/Feel` says it
  today, with no bars. Hatching on the figure marks where they are hurt. Choosing a part shows
  what is worn there, and "Pockets" jumps to that place in Carry.
- **Frisk** is the same figure used on someone else. A search goes part by part and takes time,
  so what is hidden deep is found last or not at all.

## The model underneath

- **Everything is somewhere on the body.** There is no single grid. Garments bring pockets, the
  belt and sling hold weapons, and bags hang across the body, on the back or from a hand.
- **A count and a size, not a tetris grid.** A place holds a number of things. Small things count
  once, large things twice. Bags also have their own weight limit.
- **Weight is felt first.** Exact kilograms are only on the device. In play the load is felt:
  shorter sprints, louder steps, heavier breathing, in three bands (light, loaded, heavy).
- **Where a thing is has consequences.** A pocket is quick to reach and a pack is slow. A rifle
  on a sling is visible to a patrol. A frisk finds pockets before boots.

## Picking up sorts itself

Nobody should have to file a thing by hand to pick it up. A picked-up or taken thing goes, in
order:

1. onto its own stack, wherever that is;
2. if it is a weapon, to its free place on the belt or sling;
3. to the place that already holds things of its kind (rounds with rounds, materials with
   materials);
4. by its kind when nothing of that kind is carried yet: small everyday things (aid, rounds,
   papers) to pockets, materials, food and books to a bag;
5. to any place with room.

If nothing has room, the pickup is refused in one line. The device says where the thing went, and
one key puts it somewhere else. It remembers that: move rounds to the jumpsuit once and rounds go
there from then on.

## Moving things

- With something open, one key takes from its side and stores from the character's side. Holding
  it moves everything of that kind. Before a take, a dashed row shows where the thing will land
  and what the load becomes.
- "Move to" on a carried thing lists only the places that have room for it.
- Dragging a row onto a heading is for choosing the exact place by hand.

## To decide

1. **Who has one?** Every character, with a look per faction (a salvaged handheld for citizens,
   an arm unit for the Combine), or a lootable item, which needs a fallback for those without it.
2. **How does a plain handheld know how the character is?** Body shows cold, wet and hurt. It may
   be enough that this is the character's own knowledge shown on their device; the alternative is
   that only Combine units, whose suits report biosignals, show it.
3. **Does opening it stop the world?** Probably not: the character stands looking at the device,
   slowed and exposed.
4. **Do garments add pockets?** It makes clothing matter beyond warmth, but every outfit then
   needs a pocket count.
5. **Should "out here now" exist?** A line in Body that sets what is worn against the weather. It
   is useful, and it also tells the player something they would otherwise find out by getting
   cold.

The item names, weights and limits in the mockups are placeholders.

## What changed from the first round

The first round had three layouts: A, the figure as the menu; B, a tabbed list with the figure as
a locator; C, a column of slot boxes per place.

- C had too much at once and too many boxes. It is now Carry, drawn in the plain rows that A's
  side panel used, and it is the default view.
- A looked right but would have made adding and moving things slow. It is now Body, a view of the
  character, and moving happens in Carry.
- B is folded into Carry, which can be searched by typing.
- Sorting on pickup is new.
