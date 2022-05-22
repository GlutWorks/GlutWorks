
local PLUGIN = PLUGIN


function PLUGIN:EntityTakeDamage(target, dmg)
	if target:Health() > dmg:GetDamage() and dmg:IsFallDamage() then
		print(target:GetActiveWeapon())
		target:SetRagdolled(true, dmg:GetDamage() / 10)
	end
	return 1
end
