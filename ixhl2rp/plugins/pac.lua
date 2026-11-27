
-- luacheck: globals pac pace FACTION_MPF

-- Extends the bundled PAC3 integration (helix/plugins/pac.lua, which shares this uniqueID and so
-- this PLUGIN table). Besides pacData an item may define pacDataMale, pacDataFemale and
-- pacDataMPF; each is registered as the part uniqueID .. "male", "female" or "mpf", and a player
-- wears the one that fits them. The weapon being held is never shown as a holstered part.

local PLUGIN = PLUGIN

PLUGIN.name = "PAC3 Integration"
PLUGIN.author = "Black Tea / pedro.santos53"
PLUGIN.description = "PAC3 integration for item parts, with male, female and Civil Protection variants."

-- Part id suffix -> item field holding that variant's part data.
PLUGIN.partVariants = {
	male = "pacDataMale",
	female = "pacDataFemale",
	mpf = "pacDataMPF"
}

--- Returns the id of the part an item shows on a player, or nil when it has none for them.
-- Civil Protection data wins, then the gendered data, then the plain pacData.
function PLUGIN:GetItemPartID(client, item)
	local character = client:GetCharacter()

	if (item.pacDataMPF and character and FACTION_MPF and character:GetFaction() == FACTION_MPF) then
		return item.uniqueID .. "mpf"
	end

	if (client:IsFemale()) then
		if (item.pacDataFemale) then
			return item.uniqueID .. "female"
		end
	elseif (item.pacDataMale) then
		return item.uniqueID .. "male"
	end

	if (item.pacData) then
		return item.uniqueID
	end
end

--- Returns every part id an item can register, whichever variant a player ended up wearing.
function PLUGIN:GetItemPartIDs(item)
	local partIDs = {}

	if (item.pacData) then
		partIDs[#partIDs + 1] = item.uniqueID
	end

	for suffix, field in SortedPairs(self.partVariants) do
		if (item[field]) then
			partIDs[#partIDs + 1] = item.uniqueID .. suffix
		end
	end

	return partIDs
end

if (!pace) then return end

function PLUGIN:InitializedPlugins()
	for _, v in pairs(ix.item.list) do
		if (v.pacData) then
			ix.pac.list[v.uniqueID] = v.pacData
		end

		for suffix, field in pairs(self.partVariants) do
			if (v[field]) then
				ix.pac.list[v.uniqueID .. suffix] = v[field]
			end
		end
	end

	if (SERVER) then
		self:PatchWeaponItems()
	end
end

if (SERVER) then
	local function IsHeldWeapon(client, item)
		local weapon = client:GetActiveWeapon()

		return item.class != nil and IsValid(weapon) and weapon:GetClass() == item.class
	end

	local function WearEquipped(client, character)
		for item in character:GetInventory():Iter() do
			if (item:GetData("equip") == true and !IsHeldWeapon(client, item)) then
				local partID = PLUGIN:GetItemPartID(client, item)

				if (partID) then
					client:AddPart(partID, item)
				end
			end
		end
	end

	local function WearPAC(item, client)
		local partID = PLUGIN:GetItemPartID(client, item)

		if (partID) then
			client:AddPart(partID, item)
		end
	end

	local function RemovePAC(item, client)
		local parts = client:GetParts()

		for _, partID in ipairs(PLUGIN:GetItemPartIDs(item)) do
			if (parts[partID]) then
				client:RemovePart(partID)
			end
		end
	end

	--- The stock weapon base wears and removes only uniqueID, which would leave a gendered or
	-- Civil Protection part on the player after unequipping. Items that override these keep theirs.
	function PLUGIN:PatchWeaponItems()
		local base = ix.item.base["base_weapons"]

		if (!base or base.WearPAC == WearPAC) then
			return
		end

		local stockWear, stockRemove = base.WearPAC, base.RemovePAC

		for _, v in pairs(ix.item.list) do
			if (v.WearPAC == stockWear) then
				v.WearPAC = WearPAC
			end

			if (v.RemovePAC == stockRemove) then
				v.RemovePAC = RemovePAC
			end
		end

		base.WearPAC = WearPAC
		base.RemovePAC = RemovePAC
	end

	function PLUGIN:PlayerLoadedCharacter(client, curChar, prevChar)
		client:ResetParts()

		if (curChar) then
			WearEquipped(client, curChar)
		end
	end

	function PLUGIN:PlayerSwitchWeapon(client, oldWeapon, newWeapon)
		-- Parts are hidden while observing and restored by OnPlayerObserve.
		if (client.ixObsData) then
			return
		end

		local oldItem = IsValid(oldWeapon) and oldWeapon.ixItem
		local newItem = IsValid(newWeapon) and newWeapon.ixItem

		if (oldItem and oldItem.isWeapon and oldItem:GetData("equip") and PLUGIN:GetItemPartIDs(oldItem)[1]) then
			oldItem:WearPAC(client)
		end

		if (newItem and newItem.isWeapon and PLUGIN:GetItemPartIDs(newItem)[1]) then
			newItem:RemovePAC(client)
		end
	end

	function PLUGIN:OnPlayerObserve(client, state)
		client:ResetParts()

		local character = client:GetCharacter()

		if (!state and character) then
			WearEquipped(client, character)
		end
	end
end
