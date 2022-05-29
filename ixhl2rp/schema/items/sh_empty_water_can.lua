
ITEM.name = "Empty Water Can"
ITEM.model = Model("models/props_junk/popcan01a.mdl")
ITEM.description = "An empty water can."
ITEM.category = "Consumables"
ITEM.items = {"water"}

ITEM.functions.Fill = {
	OnRun = function(itemTable)
		local client = itemTable.player
		local character = client:GetCharacter()

		for k, v in ipairs(itemTable.items) do
			if (!character:GetInventory():Add(v)) then
				ix.item.Spawn(v, client)
			end
		end
	end,
	OnCanRun = function(itemTable)
		local client = itemTable.player
		return client:WaterLevel() > 0
	end
}
