
local PLUGIN = PLUGIN

--- The weapon items a dying player has equipped. A downed player's weapons were unequipped
-- into their ragdoll when they fell, so those count too.
function PLUGIN:GetDeathDrops(client, inventory)
	local result = {}
	local seen = {}

	local function Add(item)
		if (item and item.isWeapon and !seen[item:GetID()] and item.invID == inventory:GetID()) then
			seen[item:GetID()] = true
			result[#result + 1] = item
		end
	end

	for _, v in pairs(inventory:GetItems()) do
		if (v:GetData("equip")) then
			Add(v)
		end
	end

	-- the corpse plugin may already have detached the ragdoll from the player
	local ragdoll = client.ixRagdoll

	if (!IsValid(ragdoll)) then
		ragdoll = Entity(client:GetLocalVar("ragdoll", 0) or 0)
	end

	if (IsValid(ragdoll) and ragdoll.ixWeapons) then
		for _, v in ipairs(ragdoll.ixWeapons) do
			Add(v.item)
		end

		-- they are on the ground now; waking up must not hand them back
		ragdoll.ixWeapons = nil
	end

	return result
end

function PLUGIN:DoPlayerDeath(client)
	local character = client:GetCharacter()
	local inventory = character and character:GetInventory()

	if (!inventory or !ix.config.Get("dropWeaponOnDeath", true)) then
		return
	end

	for _, item in ipairs(self:GetDeathDrops(client, inventory)) do
		if (item:GetData("equip") and item.Unequip) then
			item:Unequip(client, false)
		end

		item:Transfer(nil, nil, nil, client)
	end
end
