ITEM.category = "Eatable"

// default hunger restored set to 10 
ITEM.restoredHunger = 10

ITEM.functions.Eat = {
	OnRun = function(item)
		local client = item.player
        local character = client:GetCharacter()

		character:SetHunger(math.Clamp(character:GetHunger() + item.restoredHunger, 0, 100))
		client:EmitSound("npc/antlion_grub/squashed.wav", 75, 150, 0.25)

		return true
	end
}
