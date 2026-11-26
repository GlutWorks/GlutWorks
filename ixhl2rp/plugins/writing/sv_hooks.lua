
local PLUGIN = PLUGIN

-- the reach Helix allows for acting on an item that is lying in the world
local REACH = 96

local function CanReachItem(client, item)
	if (item.invID == 0) then
		local entity = item:GetEntity()

		return IsValid(entity) and client:GetShootPos():DistToSqr(entity:GetPos()) <= REACH * REACH
	end

	local inventory = ix.item.inventories[item.invID]

	return inventory != nil and inventory:OnCheckAccess(client)
end

netstream.Hook("ixWritingEdit", function(client, itemID, text)
	if (!isnumber(itemID) or !isstring(text)) then
		return
	end

	local character = client:GetCharacter()
	local item = ix.item.instances[itemID]

	if (!character or !item or item.base != "base_writing") then
		return
	end

	-- covers being tied up or knocked out, which block every other item action
	if (!CanReachItem(client, item) or hook.Run("CanPlayerInteractItem", client, "Edit", itemID) == false) then
		return
	end

	-- the item's own Edit action decides who may write on it (a written paper is final)
	local edit = item.functions and item.functions.Edit

	if (!edit) then
		return
	end

	if (edit.OnCanRun) then
		item.player = client
		local bCanEdit = edit.OnCanRun(item)
		item.player = nil

		if (bCanEdit == false) then
			return
		end
	end

	local owner = item:GetData("owner", 0)
	text = text:sub(1, PLUGIN.maxLength)

	if ((owner == 0 or owner == character:GetID()) and text:len() > 0) then
		item:SetText(text, character)
	end
end)
