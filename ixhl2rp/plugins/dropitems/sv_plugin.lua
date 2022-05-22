
local PLUGIN = PLUGIN

/*
function PLUGIN:PlayerHurt(target, attacker, health, damageAmount)
	
	
	print("-1")
	if character then
		local inventory = character:GetInventory()
		local items = inventory:GetItems()

		print("0")
		-- If the player is taking lethal damage
		if health <= 0 then
			local weapon = target:GetActiveWeapon()
			print("1")
			print(ix.config.Get("dropWeaponOnDeath", false))
			-- Check if dropping weapons is enabled and skip checking for weapon classes that shouldn't drop
			if ix.config.Get("dropWeaponOnDeath", false) then
				print("fdsfdsfsfsfs")
				print(items)
				for _, v in pairs(items) do
					print("2") 
					print(v:GetName())
					print(v:GetData("equip", true))
					if v:GetData("equip", true) then
						v:SetData("equip", false)
						target:StripWeapon(v.class)
						v:Transfer() -- drops the item
						weapon = v
						print("3")
					end
				end
			end

			-- Drop inventory, if enabled
			if ix.config.Get("destroyInventoryOnDeath", false) then
				for _, item in pairs(items) do
					if !item.noDrop and item != weapon then
						item:Remove()
					end
				end
			end
		end
	end
end

*/

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

