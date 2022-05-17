
local PLUGIN = PLUGIN

function PLUGIN:PlayerHurt(target, attacker, health, damageAmount)
	local character = target:GetCharacter()


	if character and attacker:IsWorld() then
        print(character)
		character:SetRagdolled(true, 5)
	end
end