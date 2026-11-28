# Inventory on a datapad: proposal

Status: a proposal for discussion. Nothing here is implemented. What changed between
rounds is at the end. The mockups are in `inventory-datapad-mockups.html` (open
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
  the selected thing: a scan of its model, where on the body it sits or what on the body it is
  for, and what can be done with it.
- **Carry with something open.** When a crate, a body or a cupboard is open, the right side
  becomes its contents, in the same rows. The character's own side does not change.
- **Carry while being searched.** The place someone has their hands in shakes red. What they have
  found is red, and so is contraband they have not reached yet.
- **Body** is the whole character on the figure. Amber is the device and what is worn; anything
  wrong with the character has its own colour, said in words beside the figure and drawn on it
  where it is. Choosing a part or a mark shows it in detail, and "Pockets" jumps to that place in
  Carry.
- **Frisk** is the same figure used on someone else. A search goes part by part and takes time,
  so what is hidden deep is found last or not at all. The part under the searcher's hands shakes,
  contraband that turns up goes red and shakes in the list and on the figure, and the subject's
  own state (a bruise, a wet coat) shows in its colours.

## Colour

Amber is the device: neutral, and most of every screen. Any other colour means the same trouble
wherever it appears.

| Colour | Means | On an item | Elsewhere |
|---|---|---|---|
| Ice blue | cold | frozen | numb hands and feet |
| Teal | wet | damp, soaked; a damp place makes what is in it damp | wet clothes |
| Pale, dry | used up | empty | thirst |
| Red | harm, now | contraband once someone can find it | wounds, a search, a refusal |
| Violet | a bruise | | |
| Sick green | gone bad | spoiled, contaminated | infection, sepsis, fever |

Items are not coloured by kind. A colour on a row says something is the matter with the thing, and
a small tag in a state's colour marks a thing that would help with that state: the water can is
tagged for thirst and the bandage for the cut. Contraband is a dim word in Carry until a search is
on, and then it is red.

## How the body's state is shown

Every state has a colour, words, and an effect with the feel of the state. A state that is fine
stays dim amber.

| State | Colour | On the figure | In the words |
|---|---|---|---|
| Cold | ice blue | frost on the numb parts, shivering | the line shivers |
| Wet | teal | water running down what is soaked | the line drips |
| Thirst | pale, dry | cracks | flat, with no glow |
| Hurt | red (violet for a bruise) | a mark per kind of injury, where it is | the line throbs |
| Sick | sick green | a glow that pulses, streaks that creep | the line pulses |

Injuries are marked by how they happened, so the figure can be read without the words: a bruise
is a violet blotch, a cut a red slash, a burn a hatched and blistered patch, a break a jagged
line, a gunshot a ring. A dressing is drawn over what it covers.

Lasting conditions use the green. An infection glows around its wound. Sepsis is the same green
leaving the wound and climbing the limb in streaks. Fever and illness rise off the head. The
mockup shows one case end to end: a cut two days old under a dirty dressing has become infected,
streaks are climbing toward the hip, and a fever is starting.

This is for the mockup. Which injuries and conditions exist, how they progress and how they are
treated is game design still to be done.

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
2. **How does a plain handheld know how the character is?** Body shows cold, wet, hurt and sick. It may
   be enough that this is the character's own knowledge shown on their device; the alternative is
   that only Combine units, whose suits report biosignals, show it.
3. **Does opening it stop the world?** Probably not: the character stands looking at the device,
   slowed and exposed.
4. **Do garments add pockets?** It makes clothing matter beyond warmth, but every outfit then
   needs a pocket count.
5. **How far do injuries go?** The mockup assumes kinds of injury and conditions that develop
   over days. That is a medical system of its own, well beyond the inventory.

The item names, weights and limits in the mockups are placeholders.

## What changed between rounds

The first round had three layouts: A, the figure as the menu; B, a tabbed list with the figure as
a locator; C, a column of slot boxes per place.

- C had too much at once and too many boxes. It is now Carry, drawn in the plain rows that A's
  side panel used, and it is the default view.
- A looked right but would have made adding and moving things slow. It is now Body, a view of the
  character, and moving happens in Carry.
- B is folded into Carry, which can be searched by typing.
- Sorting on pickup is new.

Third round: Body's state was amber words only. It is now a colour per state with an effect to
match, a mark per kind of injury, and lasting conditions (infection, sepsis, fever) drawn on the
figure. The "out here now" line is dropped.

Fourth round: the colours are used in every view. Items take a state's colour or a tag for the
state they would help, a search shakes red from both sides, and Frisk shows the subject's state.
The suitcase is gone from the example kit, so the load reads 13.0 kg.
