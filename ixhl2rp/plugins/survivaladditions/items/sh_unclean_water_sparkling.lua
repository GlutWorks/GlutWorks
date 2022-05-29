
ITEM.name = "Unclean Red Water"
ITEM.model = Model("models/props_junk/popcan01a.mdl")
ITEM.description = "A red can of dirty water collected from an outdoor water source."
ITEM.category = "Consumables"
ITEM.items = {"empty_water_can_sparkling"}
ITEM.skin = 1

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
	end,
}
