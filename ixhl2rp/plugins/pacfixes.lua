
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

-- The part variant the PAC integration registered for this character: Metropolice, then
-- gendered, then the plain one.
local function GetPartID(client, character, item)
	if (character:GetFaction() == FACTION_MPF and item.pacDataMPF) then
		return item.uniqueID .. "mpf"
	end

	local bFemale = client:IsFemale()

	if (bFemale and item.pacDataFemale) then
		return item.uniqueID .. "female"
	elseif (!bFemale and item.pacDataMale) then
		return item.uniqueID .. "male"
	end

	return item.uniqueID
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
		if (!v.class or v.class != activeClass) then
			client:AddPart(GetPartID(client, character, v), v)
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
		if (v.class == weaponClass) then
			client:RemovePart(GetPartID(client, character, v))
		end
	end
end

function PLUGIN:DoPlayerDeath(client, attacker, damageinfo)
	if (client.GetParts and client:GetParts()) then
		client:ResetParts()
	end
end
