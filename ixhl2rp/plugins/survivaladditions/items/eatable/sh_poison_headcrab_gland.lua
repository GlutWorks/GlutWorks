ITEM.name = "Poison Headcrab Gland"
ITEM.model = Model("models/mosi/fallout4/props/food/bloatflygland.mdl")
ITEM.width = 1
ITEM.height = 1
ITEM.description = "Rarely found intact, the poison gland of black headcrabs contains immensely acrid poison. A bold chef may try to incorporate its flavors into a dish, while consuming such a thing raw would lead to almost certain death."
ITEM.category = "Eatable"
ITEM.restoredHunger = 3

ITEM.functions.Eat = {
	OnRun = function(item)
		local client = item.player
        local character = client:GetCharacter()

		character:SetHunger(math.Clamp(character:GetHunger() + item.restoredHunger, 0, 100))
		client:EmitSound("npc/antlion_grub/squashed.wav", 75, 150, 0.25)

        timer.Create("PoisonTicker"..item:GetID(), 1.5, 8, function() 
            if (!client:Alive()) then
                timer.Remove("PoisonTicker"..item:GetID())
            end
            client:TakeDamage(8)
        end)
		return true
	end
}