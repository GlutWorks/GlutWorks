
local PLUGIN = PLUGIN

ITEM.name = "Ingredient"
ITEM.description = "An ingredient."
ITEM.category = "Ingredient"
ITEM.model = Model("models/props_junk/popcan01a.mdl")

-- When set, the item is an empty container that can be filled from standing water and
-- turns into this item ID. Water from the world is always the unclean kind.
ITEM.fillsInto = nil

ITEM.functions.Fill = {
	icon = "icon16/water.png",
	OnRun = function(item)
		local client = item.player

		PLUGIN:GiveItem(client, item.fillsInto)
		client:EmitSound("player/footsteps/slosh1.wav", 75, 150, 0.25)
	end,
	OnCanRun = function(item)
		return item.fillsInto != nil and IsValid(item.player) and item.player:WaterLevel() > 0
	end
}
