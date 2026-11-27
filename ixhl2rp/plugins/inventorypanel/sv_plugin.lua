local PLUGIN = PLUGIN

util.AddNetworkString("ixInventoryPanelMove")
util.AddNetworkString("ixInventoryPanelTidy")
util.AddNetworkString("ixInventoryPanelResult")
util.AddNetworkString("ixInventoryPanelMenu")

ix.log.AddType("inventoryPanelMove", function(client, name, amount, from, to)
	return string.format("%s moved %s (%s) from %s to %s.", client:Name(), name, amount, from, to)
end)

ix.log.AddType("inventoryPanelTidy", function(client, moved)
	return string.format("%s rearranged their inventory (%d items moved).", client:Name(), moved)
end)

-- Seconds between two moves, and two tidies, asked for by one player.
PLUGIN.moveInterval = 0.2
PLUGIN.tidyInterval = 2
-- How far the eyes may be from a storage's entity while moving things in or out of it, when the storage does not
-- give its own `maxDistance`; the client closes the panel a little nearer (cl_plugin.lua).
PLUGIN.storageReach = 128

--- Whether a player can handle their things now: alive, with a character, untied, on their feet.
function PLUGIN:CanAct(client)
	return IsValid(client) and client:Alive() and client:GetCharacter() != nil and !client:IsRestricted() and
		!IsValid(client.ixRagdoll)
end

-- Whether `inventory` is a bag inside `parent` (one level down, as Helix keeps them).
local function IsBagOf(parent, inventory)
	return istable(parent) and table.HasValue(parent:GetBags(), inventory:GetID())
end

--- Whether `inventory` is the player's own: their character's inventory or a bag inside it.
function PLUGIN:IsOwnInventory(client, inventory)
	local character = client:GetCharacter()
	local own = character and character:GetInventory()

	return own != nil and (own == inventory or IsBagOf(own, inventory))
end

--- Whether the player has finished searching `inventory` (or the storage holding it, for a bag inside one), it is
-- still open for them, and they are within reach of its entity. Helix grants a storage's receivers access before
-- the search ends and keeps it until the client says it closed; this does not rely on either.
function PLUGIN:CanReachStorage(client, inventory)
	local storage = client.ixOpenStorage

	if (!istable(storage) or (storage != inventory and !IsBagOf(storage, inventory))) then
		return false
	end

	local info = storage.storageInfo

	local character = client:GetCharacter()

	-- searched to the end, by the character the player is now
	if (!info or client.ixInventoryPanelReady != storage or !character or
		client.ixInventoryPanelReadyCharacter != character:GetID()) then
		return false
	end

	local entity = info.entity

	if (!IsValid(entity) or entity == client) then
		return false
	end

	-- a searched player: still the character whose inventory this is
	if (entity:IsPlayer()) then
		local owner = entity:GetCharacter()

		if (!owner or storage.owner != owner:GetID()) then
			return false
		end
	end

	local reach = tonumber(info.maxDistance) or self.storageReach
	local eyes = client:GetShootPos()

	return eyes:DistToSqr(entity:NearestPoint(eyes)) <= reach * reach
end

--- Whether the player may move things in or out of `inventory` from a panel: their own, or the storage they have
-- open (CanReachStorage), and in either case one Helix lets them reach (OnCheckAccess).
function PLUGIN:CanUseInventory(client, inventory)
	if (!istable(inventory) or !inventory.GetID or (inventory:GetID() or 0) <= 0) then
		return false
	end

	if (!self:IsOwnInventory(client, inventory) and !self:CanReachStorage(client, inventory)) then
		return false
	end

	return inventory:OnCheckAccess(client) == true
end

--- Moves an item into another inventory, both of which the player may use: a stack through ix.stack.MoveTo (merged
-- into stacks there, all of it or `quantity`), anything else whole through the stock Transfer. All or nothing.
-- @treturn bool whether it moved
-- @treturn string language phrase explaining a refusal
-- @return extra argument for that phrase
function PLUGIN:MoveItem(client, itemID, targetID, quantity)
	if (!self:CanAct(client)) then
		return false, "notNow"
	end

	local item = isnumber(itemID) and ix.item.instances[itemID]
	local source = item and ix.item.inventories[item.invID or 0]
	local target = isnumber(targetID) and ix.item.inventories[targetID]

	if (!item or !source or (item.invID or 0) <= 0 or !source:GetItemByID(item:GetID(), true)) then
		return false, "invPanelGone"
	end

	if (!target or target == source or !self:CanUseInventory(client, source) or !self:CanUseInventory(client, target)) then
		return false, "stackNoAccess"
	end

	local name, amount = item:GetName(), "1"
	local bSuccess, err, argument

	if (ix.stack and ix.stack.IsStackable(item)) then
		amount = ix.stack.Format(item, quantity or ix.stack.GetQuantity(item))
		bSuccess, err, argument = ix.stack.MoveTo(client, item, target, quantity)
	elseif (quantity != nil and quantity != 1) then
		return false, "invPanelWhole"
	else
		-- a free slot in the target's own grid: never one in a bag inside it, which can be the bag the item is in
		local x, y = target:FindEmptySlot(item.width, item.height, true)

		if (!x) then
			return false, "noFit"
		end

		bSuccess, err = item:Transfer(target:GetID(), x, y, client)
		err = !bSuccess and (isstring(err) and err or "noFit") or nil
	end

	if (bSuccess) then
		ix.log.Add(client, "inventoryPanelMove", name, amount, self:DescribeInventory(source), self:DescribeInventory(target))
	end

	return bSuccess, err, argument
end

--- How a log names an inventory: whose, or which storage.
function PLUGIN:DescribeInventory(inventory)
	local info = inventory.storageInfo

	if (info and IsValid(info.entity)) then
		return string.format("%s #%d (%s)", info.name or "storage", inventory:GetID(), tostring(info.entity))
	end

	local character = inventory.owner and ix.char.loaded[inventory.owner]

	if (character) then
		return string.format("%s's %s #%d", character:GetName(), inventory.vars and inventory.vars.isBag and "bag" or
			"inventory", inventory:GetID())
	end

	return "inventory #" .. inventory:GetID()
end

-- Whether a w x h item fits at x, y of `inventory` with none of its cells in `taken` (x -> y -> item).
local function Fits(inventory, taken, x, y, w, h)
	if (x + w - 1 > inventory.w or y + h - 1 > inventory.h) then
		return false
	end

	for x2 = x, x + w - 1 do
		for y2 = y, y + h - 1 do
			if (taken[x2] and taken[x2][y2]) then
				return false
			end
		end
	end

	return true
end

local function Take(taken, item, x, y)
	for x2 = x, x + item.width - 1 do
		taken[x2] = taken[x2] or {}

		for y2 = y, y + item.height - 1 do
			taken[x2][y2] = item
		end
	end
end

--- A tidier layout for an inventory's own grid: equipped items stay where they are, everything else is packed
-- around them largest first, row by row as Helix fills a grid. Returns item -> {x, y} for every item, or nil and a
-- phrase when it cannot be done (a slot still waiting for its item, or no packing that fits).
function PLUGIN:PlanTidy(inventory)
	local items, movable = {}, {}
	local taken = {}

	for x = 1, inventory.w do
		for y = 1, inventory.h do
			local slot = inventory.slots[x] and inventory.slots[x][y]

			-- an item still being created reserves its slot with `true`
			if (slot != nil and !istable(slot)) then
				return nil, "invPanelTidyBusy"
			end
		end
	end

	for _, item in pairs(inventory:GetItems(true)) do
		items[#items + 1] = item
	end

	local layout = {}

	for _, item in ipairs(items) do
		if (item:GetData("equip")) then
			layout[item] = {item.gridX, item.gridY}
			Take(taken, item, item.gridX, item.gridY)
		else
			movable[#movable + 1] = item
		end
	end

	table.sort(movable, function(a, b)
		local areaA, areaB = a.width * a.height, b.width * b.height

		if (areaA != areaB) then return areaA > areaB end
		if (a.height != b.height) then return a.height > b.height end
		if (a.uniqueID != b.uniqueID) then return a.uniqueID < b.uniqueID end

		return a:GetID() < b:GetID()
	end)

	for _, item in ipairs(movable) do
		local placed

		for y = 1, inventory.h - item.height + 1 do
			for x = 1, inventory.w - item.width + 1 do
				if (Fits(inventory, taken, x, y, item.width, item.height)) then
					placed = {x, y}
					break
				end
			end

			if (placed) then
				break
			end
		end

		if (!placed) then
			return nil, "invPanelTidyNoRoom"
		end

		layout[item] = placed
		Take(taken, item, placed[1], placed[2])
	end

	return layout
end

--- Repacks the player's own inventory grid (PlanTidy). Nothing but positions change: every item keeps its
-- instance, data and inventory, and a bag keeps its own inventory. Refused for a player who cannot act.
-- @treturn bool whether anything moved
-- @treturn string language phrase: why not, or what happened
function PLUGIN:Tidy(client)
	if (!self:CanAct(client)) then
		return false, "notNow"
	end

	local inventory = client:GetCharacter():GetInventory()

	if (!inventory or !inventory:OnCheckAccess(client)) then
		return false, "stackNoAccess"
	end

	local layout, reason = self:PlanTidy(inventory)

	if (!layout) then
		return false, reason
	end

	local changed = {}

	for item, position in pairs(layout) do
		if (item.gridX != position[1] or item.gridY != position[2]) then
			changed[#changed + 1] = item
		end
	end

	if (#changed == 0) then
		return false, "invPanelTidyDone"
	end

	-- every cell is rebuilt from the plan, so no item can be left in two places or none
	for x = 1, inventory.w do
		if (inventory.slots[x]) then
			for y = 1, inventory.h do
				if (layout[inventory.slots[x][y]]) then
					inventory.slots[x][y] = nil
				end
			end
		end
	end

	for item, position in pairs(layout) do
		item.gridX, item.gridY = position[1], position[2]

		for x = position[1], position[1] + item.width - 1 do
			inventory.slots[x] = inventory.slots[x] or {}

			for y = position[2], position[2] + item.height - 1 do
				inventory.slots[x][y] = item
			end
		end
	end

	if (!inventory.noSave) then
		for _, item in ipairs(changed) do
			local query = mysql:Update("ix_items")
				query:Update("x", item.gridX)
				query:Update("y", item.gridY)
				query:Where("item_id", item:GetID())
			query:Execute()
		end
	end

	-- the whole grid again for whoever sees it (an item's own OnSendData runs per receiver)
	for _, receiver in ipairs(inventory:GetReceivers()) do
		inventory:Sync(receiver)
	end

	ix.log.Add(client, "inventoryPanelTidy", #changed)

	return true, "invPanelTidied"
end

function PLUGIN:SendResult(client, bSuccess, phrase, argument)
	net.Start("ixInventoryPanelResult")
		net.WriteBool(bSuccess == true)
		net.WriteString(isstring(phrase) and phrase or "")
		net.WriteString(argument != nil and tostring(argument) or "")
	net.Send(client)
end

-- A move asked for from a panel: the item, where to, and how much of a stack (nothing for all of it).
net.Receive("ixInventoryPanelMove", function(length, client)
	if ((client.ixInventoryPanelNextMove or 0) > CurTime()) then
		return
	end

	client.ixInventoryPanelNextMove = CurTime() + PLUGIN.moveInterval

	local itemID = net.ReadUInt(32)
	local targetID = net.ReadUInt(32)
	local quantity = net.ReadBool() and net.ReadDouble() or nil

	PLUGIN:SendResult(client, PLUGIN:MoveItem(client, itemID, targetID, quantity))
end)

net.Receive("ixInventoryPanelTidy", function(length, client)
	if ((client.ixInventoryPanelNextTidy or 0) > CurTime()) then
		return
	end

	client.ixInventoryPanelNextTidy = CurTime() + PLUGIN.tidyInterval

	PLUGIN:SendResult(client, PLUGIN:Tidy(client))
end)

-- Helix's storage (helix/gamemode/core/libs/sh_storage.lua) makes the player a receiver before the search and
-- sends the storage once it is over (ix.storage.Sync); the panel moves only after that, so it is remembered here,
-- and forgotten whenever the player stops being a receiver or starts another search.
function PLUGIN:WrapStorage()
	if (!ix.storage or !ix.storage.Sync) then
		return
	end

	local original = ix.inventoryPanelStorage or {
		Open = ix.storage.Open,
		Sync = ix.storage.Sync,
		RemoveReceiver = ix.storage.RemoveReceiver
	}

	ix.inventoryPanelStorage = original

	-- Opening a storage: unless Helix is about to refuse it (someone else has it and it is not shared), whatever the
	-- player had open before is let go of and their panel closed, and the new one is not ready until its search ends.
	-- A refused open changes nothing.
	function ix.storage.Open(client, inventory, ...)
		if (IsValid(client) and istable(inventory)) then
			local info = inventory.storageInfo
			local bRefused = info and !info.bMultipleUsers and ix.storage.InUse(inventory) and
				!ix.storage.InUseBy(inventory, client)

			if (!bRefused) then
				local previous = client.ixOpenStorage

				if (previous and previous != inventory) then
					PLUGIN:ReleaseStorage(client, true)
				end

				if (previous != inventory) then
					client.ixInventoryPanelReady = nil
				end
			end
		end

		return original.Open(client, inventory, ...)
	end

	function ix.storage.Sync(client, inventory, ...)
		if (IsValid(client)) then
			local character = client:GetCharacter()

			client.ixInventoryPanelReady = inventory
			client.ixInventoryPanelReadyCharacter = character and character:GetID()
		end

		return original.Sync(client, inventory, ...)
	end

	function ix.storage.RemoveReceiver(client, inventory, ...)
		if (IsValid(client) and client.ixInventoryPanelReady == inventory) then
			client.ixInventoryPanelReady = nil
		end

		return original.RemoveReceiver(client, inventory, ...)
	end
end

--- Lets go of the storage a player has open, as ixStorageClose does: for a player who died, was knocked out or
-- tied, whose client may never say so, or who opened another. `bTell` also closes their panel (ixStorageExpired).
function PLUGIN:ReleaseStorage(client, bTell)
	local inventory = IsValid(client) and client.ixOpenStorage

	if (inventory) then
		local id = inventory.storageInfo and inventory.storageInfo.id or inventory:GetID()

		ix.storage.RemoveReceiver(client, inventory)

		if (bTell) then
			net.Start("ixStorageExpired")
				net.WriteUInt(id, 32)
			net.Send(client)
		end
	end
end

function PLUGIN:PlayerDeath(client)
	self:ReleaseStorage(client)
end

function PLUGIN:OnPlayerRestricted(client)
	self:ReleaseStorage(client)
end

-- a storage opened by one character is not the next one's
function PLUGIN:PlayerLoadedCharacter(client, character, previous)
	if (previous) then
		self:ReleaseStorage(client, true)
	end
end

function PLUGIN:OnCharacterFallover(client, entity, bFallenOver)
	if (bFallenOver) then
		self:ReleaseStorage(client)
	end
end

--- /Menu: opens the rest of Helix's menu, for a player whose help key (F1) is not bound.
function PLUGIN:OpenMenu(client)
	net.Start("ixInventoryPanelMenu")
	net.Send(client)
end

function PLUGIN:InitializedPlugins()
	self:WrapStorage()
end

PLUGIN:WrapStorage()
