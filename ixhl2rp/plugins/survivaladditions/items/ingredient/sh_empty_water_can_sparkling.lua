
ITEM.name = "Empty Red Water Can"
ITEM.model = Model("models/props_junk/popcan01a.mdl")
ITEM.skin = 1
ITEM.description = "An empty red water can. Perhaps you could fill it back up."
ITEM.category = "Ingredient"
ITEM.items = {"unclean_water_sparkling"}

ITEM.functions.Fill = {
	OnRun = function(itemTable)
		local client = itemTable.player
		local character = client:GetCharacter()

		for k, v in ipairs(itemTable.items) do
			if (!character:GetInventory():Add(v)) then
				ix.item.Spawn(v, client)
			end
		end
		client:EmitSound("player/footsteps/slosh1.wav", 100, 150, 0.25)
	end,
	OnCanRun = function(itemTable)
		local client = itemTable.player
		return client:WaterLevel() > 0
	end
}
