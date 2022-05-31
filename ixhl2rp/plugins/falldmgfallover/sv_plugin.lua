
local PLUGIN = PLUGIN

function PLUGIN:EntityTakeDamage(target, dmg)
	if target:Health() > dmg:GetDamage() and dmg:IsFallDamage() then
		armor = target:Armor()
		target:SetArmor( 0 )
		target:SetRagdolled(true, dmg:GetDamage() / 10)
		target:TakeDamage( dmg:GetDamage(), worldspawn, worldspawn )
		target:GodEnable()
		timer.Simple( 1, function() target:GodDisable() end )
		target:SetArmor( armor )
	end
end
