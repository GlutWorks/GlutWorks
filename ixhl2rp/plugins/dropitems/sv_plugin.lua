
local PLUGIN = PLUGIN

function PLUGIN:PlayerHurt(target, attacker, health, damageAmount)
	local character = target:GetCharacter()

	if character then
		local inventory = character:GetInventory()
		local items = inventory:GetItems()

		-- If the player is taking lethal damage
		if health <= 0 then
			for _, v in pairs(items) do
				if v:GetData("equip", false) then
					v:SetData("equip", false)
					target:StripWeapon(v.class)
					v:Transfer() -- drops the item
					weapon = v
				end
			end
		end
	end
end

