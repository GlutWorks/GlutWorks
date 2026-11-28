# Building and excavation trial

## Try a workshop

1. As staff, stand on level ground, face the direction the workshop should extend, aim at the ground a few steps ahead and run `/SurveySite quarry`. Choose an existing tunnel or recess for a cave base. The survey needs roughly 246 × 122 units of clear floor and 101 units of headroom. It snaps to the nearest cardinal direction. `/SurveySite open` marks the same footprint for an above-ground shelter.
2. As a player, strike each packed rock section three times with a crowbar. Walk into the space you clear. A mined section stays open. Examine the supply crate for instructions.
3. Carry 5 kg of wooden scrap and 6 kg of metal scrap for the complete workshop. Use the crate to raise the two long walls and the back wall, fit a sheet roof after the side walls are up, and assemble the bench. Each choice shows its material cost. The entrance stays open.
4. Tap Use on the bench to craft. Its builder can pick it up and place it elsewhere through the ordinary station actions. Other characters can contribute to the shelter and use the bench.

The crate records the walls, roof and remaining rock sections per map. The station plugin saves the bench and its owner separately. Removing the crate with the staff remover takes down its shell. A bench already built belongs to its builder.

## What this tests

**Buildings.** One standard footprint lets us test actual player collision, weather cover, material spending and cooperative building in a small space. The server checks the space again at assembly so a player, prop or previously built bench can block the job without costing scrap. Stock Garry's Mod plates, blocks and a supply crate provide the shell. The workbench uses the existing schema model. The busiest site uses six entities after construction, including the crate and bench. The proof of concept has no territory, doors or structural damage rules.

**Caves.** Valve's compiler turns the map's world brushes into the world BSP. The supported approach for an existing RP map is to occupy already playable space with removable solids. The trial uses two independently removable sections that share the shelter footprint. A mapper with the editable map source could instead carve connected chambers in Hammer and seal selected openings with breakable brush entities before recompiling. The latter gives authored cave silhouettes and fixed excavation routes. [Valve's world-model compiler](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/utils/vbsp/vbsp.cpp) and [breakable brush implementation](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/func_break.cpp).

**Next experiment.** To let players choose a tunnel's direction, fill a larger authored cavern with a grid, save only which cells were mined, and replicate exposed faces. Test a fork wide enough for two players and a station. Measure server tick time, collision rebuild time, entity count and late-join traffic as the mined region grows. The two-section trial establishes the interaction loop; it supplies no large-cavern performance figures. Server-side axis-aligned hull traces are enough for the cardinally aligned trial. [Facepunch hull trace reference](https://wiki.facepunch.com/gmod/util.TraceHull).
