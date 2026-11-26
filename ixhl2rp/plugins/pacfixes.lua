
-- luacheck: globals pace

PLUGIN.name = "Miscellaneous PAC Fixes"
PLUGIN.author = "Oebelysk"
PLUGIN.description = "Re-applies PAC parts of equipped items after a character gets up, and clears them on death."

-- Without PAC3 the Helix PAC plugin never defines AddPart/RemovePart/GetParts, so there is
-- nothing to fix. Returning here keeps the hooks below from being registered at all.
if (!pace) then return end

local function HasPAC(item)
	return item.pacData or item.pacDataMale or item.pacDataFemale or item.pacDataMPF
end

-- Which part variant a character wears is decided in one place, the PAC plugin override.
local function GetPartID(client, character, item)
	return ix.plugin.Get("pac"):GetItemPartID(client, item)
end

local function GetEquippedPACItems(client)
	local character = IsValid(client) and client:GetCharacter()
	local inventory = character and character:GetInventory()

	if (!inventory) then
		return {}
	end

	local result = {}

	for _, v in pairs(inventory:GetItems()) do
		if (v:GetData("equip") and HasPAC(v)) then
			result[#result + 1] = v
		end
	end

	return result, character
end

-- A held weapon is drawn by the weapon itself, so its holstered part is left off.
function PLUGIN:RestoreParts(client)
	local items, character = GetEquippedPACItems(client)
	local weapon = client:GetActiveWeapon()
	local activeClass = IsValid(weapon) and weapon:GetClass()

	for _, v in ipairs(items) do
		local partID = GetPartID(client, character, v)

		if (partID and (!v.class or v.class != activeClass)) then
			client:AddPart(partID, v)
		end
	end
end

function PLUGIN:OnCharacterGetup(client, ragdoll)
	self:RestoreParts(client)
end

function PLUGIN:OnCharacterWakeup(client, ragdoll)
	self:RestoreParts(client)
end

function PLUGIN:OnCharacterWakeupWeapon(client, weaponClass)
	local items, character = GetEquippedPACItems(client)

	for _, v in ipairs(items) do
		local partID = GetPartID(client, character, v)

		if (partID and v.class == weaponClass) then
			client:RemovePart(partID)
		end
	end
end

function PLUGIN:DoPlayerDeath(client, attacker, damageinfo)
	if (client.GetParts and client:GetParts()) then
		client:ResetParts()
	end
end
