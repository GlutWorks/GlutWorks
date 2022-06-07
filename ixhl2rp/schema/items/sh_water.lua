
ITEM.name = "Breen's Water"
ITEM.model = Model("models/props_junk/popcan01a.mdl")
ITEM.description = "A blue aluminium can of plain water."
ITEM.category = "Drink"
ITEM.items = {"empty_water_can"}

ITEM.functions.Drink = {
	OnRun = function(itemTable)
		local client = itemTable.player
		local character = client:GetCharacter()

		client:RestoreStamina(25)
		client:SetHealth(math.Clamp(client:Health() + 6, 0, client:GetMaxHealth()))
		client:EmitSound("npc/barnacle/barnacle_gulp2.wav", 75, 90, 0.35)
		for k, v in ipairs(itemTable.items) do
			if (!character:GetInventory():Add(v)) then
				ix.item.Spawn(v, client)
			end
		end
	end
}
