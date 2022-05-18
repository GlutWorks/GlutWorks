
local PLUGIN = PLUGIN


function PLUGIN:EntityTakeDamage(target, dmg)
	if dmg:IsFallDamage() then
		target:SetRagdolled(true, dmg:GetDamage() / 10)
	end
	return false 
end
