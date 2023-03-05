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

        local effect = EffectData()
            effect:SetStart(client:EyePos())
            effect:SetOrigin(client:EyePos())
            effect:SetNormal(client:EyeAngles():Forward())
            effect:SetScale(0.25)
        util.Effect("StriderBlood", effect)

        timer.Create("PoisonTicker"..item:GetID(), 1.5, 8, function() 
            print(IsValid(client.ixRagdoll))

            if (!client:Alive()) then
                timer.Remove("PoisonTicker"..item:GetID())
            end

            // don't show the particle effects if the client is ragdolled
            // at least until I can find a way to attach the particle effect to their face
            if (!IsValid(client.ixRagdoll)) then
                local effectPoison = EffectData()
                    effectPoison:SetStart(client:EyePos())
                    effectPoison:SetOrigin(client:EyePos())
                    effectPoison:SetNormal(client:EyeAngles():Forward())
                    effectPoison:SetScale(0.25)
                util.Effect("StriderBlood", effectPoison)
            end  
            client:TakeDamage(8)
        end)
		return true
	end
}