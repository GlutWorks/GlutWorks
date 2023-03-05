ITEM.category = "Eatable"

// default hunger restored set to 10 
ITEM.restoredHunger = 10

ITEM.functions.Eat = {
	OnRun = function(item)
		local client = item.player
        local character = client:GetCharacter()
        local effect = EffectData()
            effect:SetStart(client:EyePos())
            effect:SetOrigin(client:EyePos())
            effect:SetScale(0.25)
            effect:SetNormal(client:EyeAngles():Forward())
        util.Effect("StriderBlood", effect)

		character:SetHunger(math.Clamp(character:GetHunger() + item.restoredHunger, 0, 100))
		client:EmitSound("npc/antlion_grub/squashed.wav", 75, 150, 0.25)
 
		return true
	end
}

