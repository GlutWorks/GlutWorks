
ITEM.name = "Poison Headcrab Gland"
ITEM.model = Model("models/mosi/fallout4/props/food/bloatflygland.mdl")
ITEM.width = 1
ITEM.height = 1
ITEM.description = "Rarely found intact, the poison gland of black headcrabs contains immensely acrid poison. A bold chef may try to incorporate its flavors into a dish, while consuming such a thing raw would lead to almost certain death."
ITEM.restoredHunger = 5
ITEM.bMessy = true

ITEM.poisonTicks = 8
ITEM.poisonDamage = 8
ITEM.poisonInterval = 1.5

function ITEM:OnConsumed(client)
	local name = "ixPoison" .. client:SteamID64()
	local damage = self.poisonDamage

	timer.Create(name, self.poisonInterval, self.poisonTicks, function()
		if (!IsValid(client) or !client:Alive()) then
			timer.Remove(name)
			return
		end

		-- the effect is drawn at the player's eyes, which are not where a ragdoll's face is
		if (!IsValid(client.ixRagdoll)) then
			local effect = EffectData()
				effect:SetStart(client:EyePos())
				effect:SetOrigin(client:EyePos())
				effect:SetNormal(client:EyeAngles():Forward())
				effect:SetScale(0.25)
			util.Effect("StriderBlood", effect)
		end

		local info = DamageInfo()
			info:SetDamage(damage)
			info:SetDamageType(DMG_POISON)
			info:SetAttacker(client)
			info:SetInflictor(client)
		client:TakeDamageInfo(info)
	end)
end
