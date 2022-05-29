
ITEM.name = "Sparkling Breen's Water"
ITEM.model = Model("models/props_junk/popcan01a.mdl")
ITEM.skin = 1
ITEM.description = "A red aluminium can of carbonated water."
ITEM.category = "Consumables"
ITEM.items = {"empty_water_can"}

ITEM.functions.Drink = {
	OnRun = function(itemTable)
		local client = itemTable.player
		local character = client:GetCharacter()

		client:RestoreStamina(50)
		client:SetHealth(math.Clamp(client:Health() + 8, 0, client:GetMaxHealth()))
		client:EmitSound("npc/barnacle/barnacle_gulp2.wav", 75, 90, 0.35)
		for k, v in ipairs(itemTable.items) do
			if (!character:GetInventory():Add(v)) then
				ix.item.Spawn(v, client)
			end
		end
	end,
	OnCanRun = function(itemTable)
		return !itemTable.player:IsCombine()
	end
}
