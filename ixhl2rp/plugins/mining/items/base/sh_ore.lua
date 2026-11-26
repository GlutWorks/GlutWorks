
-- Mined ore, weighed in kilograms. Stacking behaviour comes from the stacking plugin's base_stackable.
ITEM.category = "Ore"
ITEM.width = 1
ITEM.height = 1
ITEM.price = 4
ITEM.stackLimit = 20
ITEM.stackStep = 0.1
ITEM.stackUnit = "kg"

-- Every ore shares one model and differs only by skin. Helix renders an item's iconCam
-- picture once per model, so without this only the first ore drawn gets a proper icon and
-- the rest fall back to the engine's default camera, which sits inside the rock.
ITEM.forceRender = true
