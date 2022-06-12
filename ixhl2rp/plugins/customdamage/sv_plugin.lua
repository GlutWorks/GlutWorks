
local PLUGIN = PLUGIN

function PLUGIN:EntityTakeDamage(target, dmg)

	-- show blood effects if player is ragdoll
	if(target.ixRagdoll) then
		dmg:ScaleDamage(0.5)
		local effectBloodSpray = EffectData()
			effectBloodSpray:SetStart(dmg:GetDamagePosition())
			effectBloodSpray:SetOrigin(dmg:GetDamagePosition())
			effectBloodSpray:SetFlags(3)
			effectBloodSpray:SetColor(0)
			effectBloodSpray:SetScale(6)
   		util.Effect("bloodspray", effectBloodSpray)
		local effectBloodSplatter = EffectData()
			effectBloodSplatter:SetStart(dmg:GetDamagePosition())
			effectBloodSplatter:SetOrigin(dmg:GetDamagePosition())
			effectBloodSplatter:SetScale(10)
   		util.Effect("BloodImpact", effectBloodSplatter)
	end

	-- make it so that ragdolls don't take an insane amount of damage from worldspawn


	-- fall over on fall damage
	if (target:IsPlayer() and ix.config.Get("falloverAfterFallDamage") and target:Health() > dmg:GetDamage() and dmg:IsFallDamage()) then
		armor = target:Armor()
		target:SetArmor( 0 )
		target:SetRagdolled(true, ix.config.Get("fallDamageBaseTime") + dmg:GetDamage() * ix.config.Get("fallDamageTimeMultiplier"))
		target:TakeDamage( dmg:GetDamage(), worldspawn, worldspawn )
		target:GodEnable()
		timer.Simple( 1, function() target:GodDisable() end )
		target:SetArmor( armor )
	end

	if(target.ixRagdoll == nil and target:IsPlayer() and (target:Health() - dmg:GetDamage()) > 0 and (target:Health() - dmg:GetDamage()) < 20 ) then
		timer.Simple( 0.1, function()
			target:GodEnable()
		end )
		timer.Simple( 0.3, function()
			target:GodDisable()
		end )
		target:SetRagdolled(true, 100)
	end

	-- make headshot noise
	if (target:IsPlayer() and target:LastHitGroup() == 1) then
		local pitch = math.random(75, 125)
		target:EmitSound("physics/body/body_medium_break3.wav", 75, pitch, 1)
	end
end

function PLUGIN:EntityEmitSound(target)
    if target.Entity:IsPlayer() and target.Entity:Crouching() and string.find(target.SoundName, "player/footsteps") then
        target.Volume = target.Volume * .25
        return true
    end
end

function PLUGIN:CreateRagdoll()
end
