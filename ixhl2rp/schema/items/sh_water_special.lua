
ITEM.name = "Special Breen's Water"
ITEM.model = Model("models/props_junk/popcan01a.mdl")
ITEM.skin = 2
ITEM.description = "A yellow aluminium can of water that seems a bit more viscous than usual."
ITEM.category = "Drink"
ITEM.items = {"empty_water_can_special"}

ITEM.functions.Drink = {
	OnRun = function(itemTable)
		local client = itemTable.player
		local character = client:GetCharacter()

		client:RestoreStamina(75)
		client:SetHealth(math.Clamp(client:Health() + 10, 0, client:GetMaxHealth()))
		client:EmitSound("npc/barnacle/barnacle_gulp2.wav", 75, 90, 0.35)
		for k, v in ipairs(itemTable.items) do
			if (!character:GetInventory():Add(v)) then
				ix.item.Spawn(v, client)
			end
		end
	end
}
