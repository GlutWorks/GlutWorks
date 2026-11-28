# Inventory on a datapad: proposal

Status: a proposal for discussion. Nothing here is implemented, and no layout has been chosen.
The mockups are in `inventory-datapad-mockups.html` (open it in a browser); the pull request that
added this file shows them as images.

## The idea

The inventory is a device the character carries and raises to look at, in the way of a Fallout
Pip-Boy. Its screen shows a hologram of the character's own body. Things are worn or stowed at
places on that body: slots for what is equipped, pockets that come with garments, and bags. The
device also shows carried weight.

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

## The model underneath

- **Everything is somewhere on the body.** There is no single grid. Garments bring pockets, the
  belt and sling hold weapons, and bags hang across the body, on the back or from a hand.
- **Slots and sizes, not a tetris grid.** A place has a number of slots. Small things take one,
  big things two. Bags also have their own weight limit.
- **Weight is felt first.** Exact kilograms are only on the device. In play the load is felt:
  shorter sprints, louder steps, heavier breathing, in three bands (light, loaded, heavy).
- **Where a thing is has consequences.** A pocket is quick to reach and a pack is slow. A rifle
  on a sling is visible to a patrol. A frisk finds pockets before boots.
- **It joins the exposure work.** The figure is the natural place for a garment's condition,
  warmth and wetness, in words as they are now.

## The mockups

- **A. The body is the menu.** The screen is the figure; every slot hangs off its body part, and
  choosing a part shows what is stored there. Strong: where a thing is carried is the whole
  interface. Weak: finding one item among forty means opening places one at a time.
- **B. The list, with the body as a locator.** Tabs and one sortable list driven by the keyboard;
  the figure lights up where the selected thing sits, beside a scan of its model. Strong: fastest
  with many items. Weak: still a list, and equipping becomes a key press, not a place.
- **C. Laid out by where it is carried.** One column per place, with whatever is open in the
  world (a crate, a body) as the last column. Strong: best for moving things and for looting.
  Weak: the figure shrinks to a map, and five columns is a lot for a small screen.
- **D. Searching someone.** The same figure, for a frisk that goes part by part and takes time.

These need not be alternatives. One device could use A as its home screen, B as "find" for a
character carrying a lot, and C whenever a container is open.

## To decide

1. **Who has one?** Every character, with a look per faction (a salvaged handheld for citizens,
   an arm unit for the Combine), or a lootable item, which needs a fallback for those without it.
2. **Does it show the body's state?** Health, hunger and temperature are felt today. One option
   is that only Combine units show vitals, since their suits report biosignals.
3. **Does opening it stop the world?** Probably not: the character stands looking at the device,
   slowed and exposed.
4. **Do garments add pockets?** It makes clothing matter beyond warmth, but every outfit then
   needs a pocket count.
5. **Mouse, keys or both?** A and C want a cursor for dragging. B works on keys alone.

The item names, weights and limits in the mockups are placeholders.
