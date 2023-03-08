ITEM.category = "Drinkable"

// default thirst set to 10
ITEM.restoredThirst = 10

ITEM.functions.Drink = {
	OnRun = function(item)
		local client = item.player
		local character = client:GetCharacter()

		character:SetThirst(math.Clamp(character:GetThirst() + item.restoredThirst, 0, 100))
		client:EmitSound("npc/barnacle/barnacle_gulp2.wav", 75, 90, 0.35)
		for k, v in ipairs(item.items) do
			if (!character:GetInventory():Add(v)) then
				ix.item.Spawn(v, client)
			end
		end
	end,
}