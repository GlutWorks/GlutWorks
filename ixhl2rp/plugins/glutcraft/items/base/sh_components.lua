
-- Crafting components. Each item sets stackLimit, stackUnit and stackStep (1 for whole pieces, 0.1 for
-- lengths); stacking behaviour comes from the stacking plugin's base_stackable.
ITEM.category = "Components"
-- Fallback value for a component; most set their own price. A price alone does not open Business
-- (Schema:CanPlayerUseBusiness also needs a permit, factions/classes or a flag, none set here).
ITEM.price = 10
ITEM.width = 1
ITEM.height = 1
ITEM.stackLimit = 5
ITEM.stackStep = 1
