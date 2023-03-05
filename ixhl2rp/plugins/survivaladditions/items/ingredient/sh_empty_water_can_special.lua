
ITEM.name = "Empty Yellow Water Can"
ITEM.model = Model("models/props_junk/popcan01a.mdl")
ITEM.skin = 2
ITEM.description = "An empty yellow water can. Perhaps you could fill it back up."
ITEM.category = "Ingredient"
ITEM.items = {"unclean_water_special"}

ITEM.functions.Fill = {
	OnRun = function(itemTable)
		local client = itemTable.player
		local character = client:GetCharacter()

		for k, v in ipairs(itemTable.items) do
			if (!character:GetInventory():Add(v)) then
				ix.item.Spawn(v, client)
			end
		end
		client:EmitSound("player/footsteps/slosh1.wav", 75, 150, 0.25)
	end,
	OnCanRun = function(itemTable)
		local client = itemTable.player
		return client:WaterLevel() > 0
	end
}
