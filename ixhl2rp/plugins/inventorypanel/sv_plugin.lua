local PLUGIN = PLUGIN

util.AddNetworkString("ixInventoryPanelMove")
util.AddNetworkString("ixInventoryPanelCombine")
util.AddNetworkString("ixInventoryPanelResult")
util.AddNetworkString("ixInventoryPanelMenu")

ix.log.AddType("inventoryPanelMove", function(client, name, amount, from, to)
	return string.format("%s moved %s (%s) from %s to %s.", client:Name(), name, amount, from, to)
end)

ix.log.AddType("inventoryPanelPlace", function(client, name, inventory, x, y)
	return string.format("%s put %s at %d,%d of %s.", client:Name(), name, x, y, inventory)
end)

ix.log.AddType("inventoryPanelCombine", function(client, name, target, from, to)
	return string.format("%s combined %s from %s with %s in %s.", client:Name(), name, from, target, to)
end)

-- Seconds between two moves (or combines) asked for by one player.
PLUGIN.moveInterval = 0.2
-- How far the eyes may be from a storage's entity while moving things in or out of it, when the storage does not
-- give its own `maxDistance`; the client closes the case a little nearer (cl_plugin.lua).
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

--- Whether the player may move things in or out of `inventory` from the case: their own, or the storage they have
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

--- Moves an item into an inventory the player may use, or to another place in its own (with a cell). A stack moves
-- through ix.stack.MoveTo (all of it or `quantity`), anything else whole through the stock Transfer, which applies
-- Helix's rules (no bag in a bag, nothing equipped leaves). Without a cell it goes into a free cell of the target's
-- own grid (merging into stacks there); with one (`x`, `y`, the top left cell, as the player placed it) it lies
-- exactly there or nowhere. All or nothing; every cell is checked here, never taken from the client.
-- @treturn bool whether it moved
-- @treturn string language phrase explaining a refusal
-- @return extra argument for that phrase
function PLUGIN:MoveItem(client, itemID, targetID, quantity, x, y)
	if (!self:CanAct(client)) then
		return false, "notNow"
	end

	local item = isnumber(itemID) and ix.item.instances[itemID]
	local source = item and ix.item.inventories[item.invID or 0]
	local target = isnumber(targetID) and ix.item.inventories[targetID]
	local bCell = x != nil or y != nil

	if (!item or !source or (item.invID or 0) <= 0 or !source:GetItemByID(item:GetID(), true)) then
		return false, "invPanelGone"
	end

	if (!target or (target == source and !bCell) or !self:CanUseInventory(client, source) or
		!self:CanUseInventory(client, target)) then
		return false, "stackNoAccess"
	end

	if (bCell and !ix.stack.FitsAt(target, item, x, y)) then
		return false, "noFit"
	end

	if (target == source) then
		if (quantity != nil) then
			return false, "invPanelWhole"
		end

		return self:PlaceItem(client, item, target, x, y)
	end

	local name, amount = item:GetName(), "1"
	local bSuccess, err, argument

	if (ix.stack and ix.stack.IsStackable(item)) then
		amount = ix.stack.Format(item, quantity or ix.stack.GetQuantity(item))
		bSuccess, err, argument = ix.stack.MoveTo(client, item, target, quantity, x, y)
	elseif (quantity != nil and quantity != 1) then
		return false, "invPanelWhole"
	else
		-- a free cell in the target's own grid: never one in a bag inside it, which can be the bag the item is in
		if (!bCell) then
			x, y = target:FindEmptySlot(item.width, item.height, true)
		end

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

--- Puts an item at another place in the grid it is in, as Helix's own move does (ixInventoryMove: the cells and
-- the item's position, the row's x and y unless the inventory is not saved, and the same message to whoever sees
-- the grid; it asks no transfer rule, so an equipped item can be moved too). The cell has been checked (FitsAt).
function PLUGIN:PlaceItem(client, item, inventory, x, y)
	local oldX, oldY = item.gridX, item.gridY

	if (oldX == x and oldY == y) then
		return false, "invPanelSamePlace"
	end

	for _, column in pairs(inventory.slots) do
		for row, slot in pairs(column) do
			if (slot == item) then
				column[row] = nil
			end
		end
	end

	for x2 = x, x + item.width - 1 do
		inventory.slots[x2] = inventory.slots[x2] or {}

		for y2 = y, y + item.height - 1 do
			inventory.slots[x2][y2] = item
		end
	end

	item.gridX, item.gridY = x, y

	if (!inventory.noSave) then
		local query = mysql:Update("ix_items")
			query:Update("x", x)
			query:Update("y", y)
			query:Where("item_id", item:GetID())
		query:Execute()
	end

	-- the client keeps an item at its top left cell and moves it there on this (helix/gamemode/core/libs/sh_item.lua)
	local receivers = inventory:GetReceivers()

	if (istable(receivers) and #receivers > 0) then
		net.Start("ixInventoryMove")
			net.WriteUInt(inventory:GetID(), 32)
			net.WriteUInt(item:GetID(), 32)
			net.WriteUInt(oldX, 6)
			net.WriteUInt(oldY, 6)
			net.WriteUInt(x, 6)
			net.WriteUInt(y, 6)
		net.Send(receivers)
	end

	ix.log.Add(client, "inventoryPanelPlace", item:GetName(), self:DescribeInventory(inventory), x, y)

	return true
end

-- A stack's quantity, or nil for anything else; to tell whether a combine changed anything.
local function Quantity(item)
	return ix.stack and ix.stack.IsStackable(item) and ix.stack.GetUnits(item) or nil
end

--- Combines an item with another by putting one onto the other, as dragging it there did: the target's own
-- `combine` function with the item's ID, through ix.item.PerformInventoryAction (the same entry point and checks as
-- the old drag: stacks merge through ix.stack.Combine, a bag takes the item through Transfer). Both must be in
-- inventories the player may use from the case (CanUseInventory) and the target must accept it
-- (PLUGIN:GetCombineTargets).
-- @treturn bool whether anything changed
-- @treturn string language phrase explaining a refusal
function PLUGIN:CombineItems(client, itemID, targetID)
	if (!self:CanAct(client)) then
		return false, "notNow"
	end

	local item = isnumber(itemID) and ix.item.instances[itemID]
	local target = isnumber(targetID) and ix.item.instances[targetID]
	local source = item and ix.item.inventories[item.invID or 0]
	local inventory = target and ix.item.inventories[target.invID or 0]

	if (!item or !target or !source or !inventory or (item.invID or 0) <= 0 or (target.invID or 0) <= 0 or
		!source:GetItemByID(item:GetID(), true) or !inventory:GetItemByID(target:GetID(), true)) then
		return false, "invPanelGone"
	end

	if (item == target) then
		return false, "invPanelNoCombine"
	end

	if (!self:CanUseInventory(client, source) or !self:CanUseInventory(client, inventory)) then
		return false, "stackNoAccess"
	end

	local refusal = self:GetCombineRefusal(item, target)

	if (refusal) then
		return false, refusal
	end

	if (#self:GetCombineTargets(item, {target}, client) == 0) then
		return false, "invPanelNoCombine"
	end

	local name, targetName = item:GetName(), target:GetName()
	local from, to = self:DescribeInventory(source), self:DescribeInventory(inventory)
	local before = {item.invID, Quantity(item), Quantity(target)}

	ix.item.PerformInventoryAction(client, "combine", target:GetID(), target.invID, {item:GetID()})

	-- nothing changed: both still there, where they were, holding what they held
	if (ix.item.instances[item:GetID()] == item and ix.item.instances[target:GetID()] == target and
		item.invID == before[1] and Quantity(item) == before[2] and Quantity(target) == before[3]) then
		return false, self:GetCombineRefusal(item, target) or "invPanelNoCombine"
	end

	ix.log.Add(client, "inventoryPanelCombine", name, targetName, from, to)

	return true
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

function PLUGIN:SendResult(client, bSuccess, phrase, argument)
	net.Start("ixInventoryPanelResult")
		net.WriteBool(bSuccess == true)
		net.WriteString(isstring(phrase) and phrase or "")
		net.WriteString(argument != nil and tostring(argument) or "")
	net.Send(client)
end

-- One request from the case every moveInterval; the rest are dropped.
function PLUGIN:TakeRequest(client)
	if ((client.ixInventoryPanelNextMove or 0) > CurTime()) then
		return false
	end

	client.ixInventoryPanelNextMove = CurTime() + self.moveInterval

	return true
end

-- A move asked for from the case: the item, where to, how much of a stack (nothing for all of it) and the cell it
-- was put at (nothing for any free one).
net.Receive("ixInventoryPanelMove", function(length, client)
	if (!PLUGIN:TakeRequest(client)) then
		return
	end

	local itemID = net.ReadUInt(32)
	local targetID = net.ReadUInt(32)
	local quantity = net.ReadBool() and net.ReadDouble() or nil
	local x, y

	if (net.ReadBool()) then
		x, y = net.ReadUInt(8), net.ReadUInt(8)
	end

	PLUGIN:SendResult(client, PLUGIN:MoveItem(client, itemID, targetID, quantity, x, y))
end)

-- An item put down onto another: the item and the one it was put onto.
net.Receive("ixInventoryPanelCombine", function(length, client)
	if (!PLUGIN:TakeRequest(client)) then
		return
	end

	local itemID = net.ReadUInt(32)
	local targetID = net.ReadUInt(32)

	PLUGIN:SendResult(client, PLUGIN:CombineItems(client, itemID, targetID))
end)

-- Helix's storage (helix/gamemode/core/libs/sh_storage.lua) makes the player a receiver before the search and
-- sends the storage once it is over (ix.storage.Sync); the case moves things only after that, so it is remembered here,
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
	-- player had open before is let go of and their case closed, and the new one is not ready until its search ends.
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
-- tied, whose client may never say so, or who opened another. `bTell` also closes their case (ixStorageExpired).
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
