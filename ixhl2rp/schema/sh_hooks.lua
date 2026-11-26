
local function IsListed(list, value)
	if (istable(list)) then
		for _, v in pairs(list) do
			if (v == value) then
				return true
			end
		end

		return false
	end

	return list == value
end

-- The business menu is deny-by-default for every faction. Helix sells an item without a price
-- for nothing, so an item needs a positive price and must opt in: with a permit the character
-- holds, with a faction and/or class allow-list that the character matches, or, for an item
-- gated by nothing but a flag, with that flag.
function Schema:CanPlayerUseBusiness(client, uniqueID)
	local itemTable = ix.item.list[uniqueID]
	local character = client:GetCharacter()

	if (!itemTable or !character or itemTable.noBusiness or !ix.config.Get("allowBusiness", true)) then
		return false
	end

	if (!isnumber(itemTable.price) or !(itemTable.price > 0)) then
		return false
	end

	local bAllowed = false

	-- permits themselves carry a permit field; they are handed out, never bought
	if (itemTable.permit and itemTable.base != "base_permits") then
		local inventory = character:GetInventory()

		bAllowed = inventory and inventory:HasItem("permit_" .. itemTable.permit) and true or false
	end

	if (!bAllowed and (itemTable.factions or itemTable.classes)) then
		bAllowed = (!itemTable.factions or IsListed(itemTable.factions, client:Team()))
			and (!itemTable.classes or IsListed(itemTable.classes, character:GetClass()))
	elseif (!bAllowed and itemTable.flag and !itemTable.permit) then
		bAllowed = true
	end

	if (!bAllowed or (itemTable.flag and !character:HasFlags(itemTable.flag))) then
		return false
	end

	return true
end

-- called when the client wants to view the combine data for the given target
function Schema:CanPlayerViewData(client, target)
	return client:IsCombine() and (!target:IsCombine() and target:Team() != FACTION_ADMIN)
end

-- called when the client wants to edit the combine data for the given target
function Schema:CanPlayerEditData(client, target)
	return client:IsCombine() and (!target:IsCombine() and target:Team() != FACTION_ADMIN)
end

function Schema:CanPlayerViewObjectives(client)
	return client:IsCombine()
end

function Schema:CanPlayerEditObjectives(client)
	if (!client:IsCombine() or !client:GetCharacter()) then
		return false
	end

	-- Overwatch are dispatch and hold the top datafile tier
	return client:Team() == FACTION_OTA or self:HasCommandRank(client)
end

function Schema:CanDrive()
	return false
end
