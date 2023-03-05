
ITEM.name = "Empty Water Can"
ITEM.model = Model("models/props_junk/popcan01a.mdl")
ITEM.description = "An empty water can."
ITEM.category = "Ingredient"
ITEM.items = {"unclean_water"}

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
