
local INVENTORY = ix.meta.inventory

-- The stock Add, kept across Lua refreshes so the wrapper below is never wrapped twice.
ix.stack.StockAdd = ix.stack.StockAdd or INVENTORY.Add

local PICKUP_RANGE = 96 * 96

-- Deletes an instance once. A world item's entity would otherwise delete the row and call OnRemoved itself
-- when item:Remove removes it, and then item:Remove would do both again.
local function RemoveItem(item)
	local entity = (item.invID or 0) == 0 and item:GetEntity()

	if (IsValid(entity)) then
		entity.ixIsSafe = true
	end

	item:Remove()
end

local function SetUnits(item, units)
	if (units <= 0) then
		RemoveItem(item)
	else
		item:SetData("quantity", ix.stack.FromUnits(item, units))
	end
end

--- Sets an instance's quantity, removing it when the quantity is zero or less.
-- Returns false and changes nothing for a quantity above the stack limit, or other than 1 on a non-stackable.
function ix.stack.SetQuantity(item, quantity)
	if (!istable(item) or !ix.stack.IsFiniteNumber(quantity)) then
		return false
	end

	local units = ix.stack.ToUnits(item, quantity)

	if (units <= 0) then
		RemoveItem(item)
		return true
	end

	if (!ix.stack.IsStackable(item)) then
		return units == 1
	end

	if (units > ix.stack.GetLimitUnits(item)) then
		return false
	end

	item:SetData("quantity", ix.stack.FromUnits(item, units))
	return true
end

--- Adds one new instance to the inventory with the stock Add, which reserves the slot immediately and sets the
-- data when the database insert completes, so this is safe with an asynchronous database.
local function AddNewInstance(inventory, uniqueID, data)
	return ix.stack.StockAdd(inventory, uniqueID, 1, data)
end

-- Fills partial stacks of uniqueID in the inventory with up to `units`, skipping the instance `exclude`.
-- Returns the number of units placed.
local function FillPartialStacks(inventory, uniqueID, units, exclude)
	local limit = ix.stack.GetLimitUnits(uniqueID)
	local placed = 0

	for _, stack in ipairs(ix.stack.GetStacks(inventory, uniqueID)) do
		if (placed >= units) then
			break
		end

		if (stack:GetID() != exclude) then
			local have = ix.stack.GetUnits(stack)

			if (have < limit) then
				local add = math.min(limit - have, units - placed)

				SetUnits(stack, have + add)
				placed = placed + add
			end
		end
	end

	return placed
end

-- How many w x h items fit in the free space of one inventory grid, placed first-fit in the same order
-- FindEmptySlot uses. Reserved slots (pending inserts) count as occupied.
local function CountPlacements(inventory, w, h, wanted)
	if (w > inventory.w or h > inventory.h) then
		return 0
	end

	local taken = {}
	local count = 0

	local function IsFree(x, y)
		for x2 = x, x + w - 1 do
			for y2 = y, y + h - 1 do
				if ((inventory.slots[x2] and inventory.slots[x2][y2]) or (taken[x2] and taken[x2][y2])) then
					return false
				end
			end
		end

		return true
	end

	for y = 1, inventory.h - (h - 1) do
		for x = 1, inventory.w - (w - 1) do
			if (count >= wanted) then
				return count
			end

			if (IsFree(x, y)) then
				for x2 = x, x + w - 1 do
					taken[x2] = taken[x2] or {}

					for y2 = y, y + h - 1 do
						taken[x2][y2] = true
					end
				end

				count = count + 1
			end
		end
	end

	return count
end

--- Whether the whole quantity of uniqueID would fit, counting free space in partial stacks and empty slots
-- in the inventory and its bags.
function ix.stack.CanGive(inventory, uniqueID, quantity)
	local itemTable = ix.item.list[uniqueID]

	if (!inventory or !itemTable or !ix.stack.IsFiniteNumber(quantity)) then
		return false
	end

	local needed = ix.stack.ToUnits(itemTable, quantity)

	if (needed <= 0) then
		return true
	end

	if (hook.Run("CanTransferItem", itemTable, ix.item.inventories[0], inventory) == false) then
		return false
	end

	local limit = ix.stack.GetLimitUnits(itemTable)

	if (ix.stack.IsStackable(itemTable)) then
		for _, stack in ipairs(ix.stack.GetStacks(inventory, uniqueID)) do
			needed = needed - math.max(limit - ix.stack.GetUnits(stack), 0)
		end

		if (needed <= 0) then
			return true
		end
	end

	local stacksNeeded = math.ceil(needed / limit)
	local found = CountPlacements(inventory, itemTable.width, itemTable.height, stacksNeeded)

	for _, bagID in ipairs(inventory:GetBags()) do
		local bag = ix.item.inventories[bagID]

		if (found >= stacksNeeded) then
			break
		end

		if (bag) then
			found = found + CountPlacements(bag, itemTable.width, itemTable.height, stacksNeeded - found)
		end
	end

	return found >= stacksNeeded
end

--- Gives quantity of uniqueID to the inventory: fills partial stacks first, then makes new stacks.
-- Non-stackables are given as that many separate items.
-- @treturn bool true when everything was placed
-- @treturn number the quantity that did not fit (only when false); the caller decides what happens to it
function ix.stack.Give(inventory, uniqueID, quantity)
	local itemTable = ix.item.list[uniqueID]

	if (!inventory or !itemTable or !ix.stack.IsFiniteNumber(quantity) or quantity < 0) then
		return false, ix.stack.IsFiniteNumber(quantity) and math.max(quantity, 0) or 0
	end

	local remaining = ix.stack.ToUnits(itemTable, quantity)

	if (ix.stack.IsStackable(itemTable)) then
		local limit = ix.stack.GetLimitUnits(itemTable)

		remaining = remaining - FillPartialStacks(inventory, uniqueID, remaining)

		while (remaining > 0) do
			local chunk = math.min(limit, remaining)

			if (!AddNewInstance(inventory, uniqueID, {quantity = ix.stack.FromUnits(itemTable, chunk)})) then
				break
			end

			remaining = remaining - chunk
		end
	else
		while (remaining > 0) do
			if (!AddNewInstance(inventory, uniqueID)) then
				break
			end

			remaining = remaining - 1
		end
	end

	if (remaining > 0) then
		return false, ix.stack.FromUnits(itemTable, remaining)
	end

	return true
end

--- Takes quantity of uniqueID from the inventory, smallest stacks first. All or nothing.
function ix.stack.Take(inventory, uniqueID, quantity)
	local itemTable = ix.item.list[uniqueID]

	if (!inventory or !itemTable or !ix.stack.IsFiniteNumber(quantity) or quantity < 0) then
		return false
	end

	local needed = ix.stack.ToUnits(itemTable, quantity)

	if (needed <= 0) then
		return true
	end

	local stacks = ix.stack.GetStacks(inventory, uniqueID)
	local units = {}
	local total = 0

	for _, stack in ipairs(stacks) do
		units[stack] = ix.stack.GetUnits(stack)
		total = total + units[stack]
	end

	if (total < needed) then
		return false
	end

	table.sort(stacks, function(a, b)
		if (units[a] != units[b]) then
			return units[a] < units[b]
		end

		return a:GetID() < b:GetID()
	end)

	for _, stack in ipairs(stacks) do
		local take = math.min(units[stack], needed)

		SetUnits(stack, units[stack] - take)
		needed = needed - take

		if (needed <= 0) then
			break
		end
	end

	return true
end

--- Spawns quantity of uniqueID in the world, as as many stacks as the limit requires (one entity per item for
-- non-stackables). position may be a player, in which case the items are dropped in front of them.
-- callback(item, entity) runs for each entity once its database insert completes.
function ix.stack.Spawn(uniqueID, position, quantity, angles, callback)
	local itemTable = ix.item.list[uniqueID]

	if (!itemTable or !ix.stack.IsFiniteNumber(quantity)) then
		return false
	end

	local remaining = ix.stack.ToUnits(itemTable, quantity)

	if (remaining <= 0) then
		return false
	end

	-- Resolve a player to a position and an owner now: the entity is made when the insert completes, which on
	-- an asynchronous database can be after the player has left. The owner marks are the ones Helix's own
	-- item:Spawn(player) sets.
	local steamID, characterID

	if (isentity(position) and IsValid(position) and position:IsPlayer()) then
		local character = position:GetCharacter()

		steamID, characterID = position:SteamID(), character and character:GetID()
		position = position:GetItemDropPos()
	end

	local spawned = callback

	if (characterID) then
		spawned = function(item, entity)
			if (IsValid(entity)) then
				entity.ixSteamID = steamID
				entity.ixCharID = characterID
				entity:SetNetVar("owner", characterID)
			end

			if (callback) then
				callback(item, entity)
			end
		end
	end

	local limit = ix.stack.GetLimitUnits(itemTable)
	local stackable = ix.stack.IsStackable(itemTable)

	while (remaining > 0) do
		local chunk = math.min(limit, remaining)

		ix.item.Spawn(uniqueID, position, spawned, angles,
			stackable and {quantity = ix.stack.FromUnits(itemTable, chunk)} or nil)

		remaining = remaining - chunk
	end

	return true
end

--- Gives quantity to the character's inventory and drops whatever does not fit in front of the player.
-- Returns true when everything went into the inventory.
function ix.stack.GiveOrDrop(client, uniqueID, quantity)
	local character = IsValid(client) and client:GetCharacter()
	local inventory = character and character:GetInventory()
	local bSuccess, leftover = ix.stack.Give(inventory, uniqueID, quantity)

	if (!bSuccess and leftover and leftover > 0 and IsValid(client)) then
		ix.stack.Spawn(uniqueID, client, leftover)
	end

	return bSuccess, leftover
end

--- Whether the player may touch this item: it is in an inventory they can access (their own, a bag they carry,
-- a container they have open), or it is a world item within reach. Items belonging to another of the player's
-- characters are refused, and so is everything while the player is dead, tied or ragdolled.
function ix.stack.CanAccess(client, item)
	local character = IsValid(client) and client:GetCharacter()

	if (!character or !istable(item) or ix.item.instances[item:GetID()] != item) then
		return false
	end

	if (!client:Alive() or client:IsRestricted() or IsValid(client.ixRagdoll)) then
		return false
	end

	if (!item.bAllowMultiCharacterInteraction) then
		local itemPlayerID, itemCharacterID = item:GetPlayerID(), item:GetCharacterID()

		if (itemPlayerID and itemCharacterID and itemPlayerID == client:SteamID64() and
			itemCharacterID != character:GetID()) then
			return false
		end
	end

	local invID = item.invID or 0

	if (invID > 0) then
		local inventory = ix.item.inventories[invID]

		if (!inventory or !inventory:GetItemByID(item:GetID(), true)) then
			return false
		end

		-- Receivers only, not inventory.owner: a dropped bag keeps its last owner (Helix's SetOwner(nil) does
		-- nothing) but loses its receivers. A character's own inventories always list the player as a receiver.
		return inventory:OnCheckAccess(client)
	end

	local entity = item:GetEntity()

	return IsValid(entity) and client:GetShootPos():DistToSqr(entity:GetPos()) <= PICKUP_RANGE
end

--- Merges the stack sourceID into target, as far as the limit allows. This is what the "combine" item action
-- runs when a player drags one stack onto another; sourceID comes from the client.
-- @treturn bool whether anything moved
-- @treturn string language phrase explaining a refusal
function ix.stack.Combine(client, target, sourceID)
	if (isnumber(target)) then
		target = ix.item.instances[target]
	end

	local source = isnumber(sourceID) and ix.item.instances[sourceID]
	local bCanCombine, reason = ix.stack.CanCombine(target, source)

	if (!bCanCombine) then
		return false, reason
	end

	if (!ix.stack.CanAccess(client, target) or !ix.stack.CanAccess(client, source)) then
		return false, "stackNoAccess"
	end

	local targetUnits = ix.stack.GetUnits(target)
	local sourceUnits = ix.stack.GetUnits(source)
	local moved = math.min(ix.stack.GetLimitUnits(target) - targetUnits, sourceUnits)

	-- Take from the source before adding to the target, so an error in between can never create quantity.
	SetUnits(source, sourceUnits - moved)
	SetUnits(target, targetUnits + moved)

	return true
end

--- Splits amount off a stack into a new stack in the same inventory. amount is the raw text the player typed;
-- the stack is looked up and its quantity read again here, when the answer arrives, not when it was asked.
-- @treturn bool whether a new stack was made
-- @treturn string language phrase explaining a refusal
-- @return extra argument for that phrase
function ix.stack.Split(client, itemID, amount)
	local item = isnumber(itemID) and ix.item.instances[itemID] or (istable(itemID) and itemID)

	if (!item or !ix.stack.IsStackable(item)) then
		return false, "stackInvalid"
	end

	if ((item.invID or 0) <= 0 or !ix.stack.CanAccess(client, item)) then
		return false, "stackNoAccess"
	end

	amount = tonumber(amount)

	if (!ix.stack.IsFiniteNumber(amount) or amount <= 0) then
		return false, "stackSplitInvalid"
	end

	local step = ix.stack.GetStep(item)
	local units = ix.stack.ToUnits(item, amount)

	if (units <= 0 or math.abs(ix.stack.FromUnits(item, units) - amount) > step * 1e-6) then
		return false, "stackSplitStep", ix.stack.Format(item, step)
	end

	local have = ix.stack.GetUnits(item)

	if (units >= have) then
		return false, "stackSplitTooLarge", ix.stack.Format(item, ix.stack.FromUnits(item, have))
	end

	-- Only reachable from a stack stored above the limit (older rows): never make another one.
	if (units > ix.stack.GetLimitUnits(item)) then
		return false, "stackSplitOverLimit", ix.stack.Format(item, item.stackLimit)
	end

	local inventory = ix.item.inventories[item.invID]

	-- Make the new stack first: if it does not fit, nothing has changed.
	if (!AddNewInstance(inventory, item.uniqueID, {quantity = ix.stack.FromUnits(item, units)})) then
		return false, "noFit"
	end

	SetUnits(item, have - units)

	return true
end

--- Picks a world stack up: merges it into partial stacks in the player's inventory first, then moves what is
-- left into a free slot with the stock transfer. If that fails the rest stays in the world with its quantity.
-- @treturn bool success
-- @treturn string "merged" when the world item was used up, "transferred" when it moved into the inventory,
-- otherwise the language phrase for the failure
-- @treturn[opt] number on failure, the quantity that was merged into the inventory anyway
function ix.stack.Pickup(client, item)
	local character = IsValid(client) and client:GetCharacter()
	local inventory = character and character:GetInventory()

	if (!inventory or !istable(item) or (item.invID or 0) != 0) then
		return false, "unknownError"
	end

	if (hook.Run("CanTransferItem", item, ix.item.inventories[0], inventory) == false) then
		return false, "notAllowed"
	end

	local units = ix.stack.GetUnits(item)
	local merged = ix.stack.IsStackable(item) and FillPartialStacks(inventory, item.uniqueID, units, item:GetID()) or 0

	if (merged >= units) then
		RemoveItem(item)
		return true, "merged"
	end

	if (merged > 0) then
		SetUnits(item, units - merged)
	end

	local bSuccess, err = item:Transfer(inventory:GetID(), nil, nil, client)

	if (!bSuccess) then
		return false, err or "unknownError", ix.stack.FromUnits(item, merged)
	end

	return true, "transferred"
end

-- Vendor trades. Helix's vendor moves one item instance per trade, and for a stackable that instance is a whole
-- stack. A trade of a stackable is one whole unit instead (1 kg of a kg resource, one piece of a counted item, or
-- ITEM.tradeAmount) for the vendor's price. A sale takes that amount from the player's total across stacks, so
-- splitting a stack before selling it gains nothing. The vendor keeps doing its own money, stock, notices and
-- logging; PrepareVendorTrade only changes what its item operation moves, and only when the vendor is certain to
-- reach it.
local pendingSale -- the instance whose next Remove sells one trade amount
local pendingPurchase -- {inventory, uniqueID, client}: the next stock-style Add of uniqueID there gives one trade amount

--- The quantity of a stackable that changes hands in one vendor trade.
function ix.stack.GetTradeAmount(uniqueID)
	local itemTable = ix.item.list[uniqueID]
	local units = math.max(ix.stack.ToUnits(itemTable, tonumber(itemTable.tradeAmount) or 1), 1)

	return ix.stack.FromUnits(itemTable, units)
end

local function SellTradeAmount(item)
	item.Remove = nil

	if (pendingSale == item) then
		pendingSale = nil
	end

	return ix.stack.Take(ix.item.inventories[item.invID], item.uniqueID, ix.stack.GetTradeAmount(item.uniqueID))
end

--- Clears what PrepareVendorTrade set up, if the vendor did not use it.
function ix.stack.EndVendorTrade()
	if (pendingSale) then
		pendingSale.Remove = nil
		pendingSale = nil
	end

	pendingPurchase = nil
end

--- Called from CanPlayerTradeWithVendor, right before the vendor plugin performs the trade. The checks repeat the
-- vendor's own refusals in its order, so nothing is set up for a trade the vendor will refuse.
-- @treturn[opt] bool false when the player holds less than one trade amount to sell
-- @treturn[opt] number the trade amount, when refused
function ix.stack.PrepareVendorTrade(client, vendor, uniqueID, bSelling)
	ix.stack.EndVendorTrade()

	local character = client:GetCharacter()
	local inventory = character and character:GetInventory()

	if (!inventory or !ix.stack.IsStackable(uniqueID)) then
		return
	end

	local price = vendor:GetPrice(uniqueID, bSelling)
	local stock, max = vendor:GetStock(uniqueID)

	if (bSelling) then
		if (!vendor:HasMoney(price) or (stock and stock >= max)) then
			return
		end

		-- The instance the vendor removes: the first match in its own search order.
		for item in inventory:Iter() do
			if (item.uniqueID == uniqueID and item:GetID() != 0 and ix.item.instances[item:GetID()] and
				item:GetData("equip", false) == false) then
				local amount = ix.stack.GetTradeAmount(uniqueID)
				local total = 0

				-- The same stacks Take draws from.
				for _, stack in ipairs(ix.stack.GetStacks(inventory, uniqueID)) do
					total = total + ix.stack.GetUnits(stack)
				end

				if (total < ix.stack.ToUnits(item, amount)) then
					return false, amount
				end

				-- Shadows ITEM:Remove on this instance only, for the one call the vendor makes next.
				item.Remove = SellTradeAmount
				pendingSale = item

				break
			end
		end
	else
		if ((stock and stock < 1) or !character:HasMoney(price) or !vendor:CanSellToPlayer(client, uniqueID)) then
			return
		end

		pendingPurchase = {inventory = inventory, uniqueID = uniqueID, client = client}
	end

	-- The vendor's trade runs to completion in this same call; this only matters if it errors on the way.
	timer.Simple(0, ix.stack.EndVendorTrade)
end

-- Gives a vendor purchase. If it does not fit it is dropped here, so the vendor's own fallback (spawning a default
-- instance) never runs.
local function GiveVendorPurchase(inventory, uniqueID, client)
	local amount = ix.stack.GetTradeAmount(uniqueID)

	if (!ix.stack.CanGive(inventory, uniqueID, amount) or !ix.stack.Give(inventory, uniqueID, amount)) then
		ix.stack.Spawn(uniqueID, client, amount)
	end

	return true
end

--- Inventory:Add keeps its stock meaning for non-stackables and whenever a position or replication flag is
-- given. For a stackable uniqueID it adds quantity * (data.quantity or 1) merged into existing stacks, and
-- only when all of it fits; otherwise nothing changes and it returns false, "noFit".
function INVENTORY:Add(uniqueID, quantity, data, x, y, noReplication)
	local itemTable = isstring(uniqueID) and ix.item.list[uniqueID]

	if (!itemTable or !ix.stack.IsStackable(itemTable) or x or y or noReplication) then
		return ix.stack.StockAdd(self, uniqueID, quantity, data, x, y, noReplication)
	end

	if (pendingPurchase and pendingPurchase.inventory == self and pendingPurchase.uniqueID == uniqueID and
		quantity == nil and data == nil) then
		local client = pendingPurchase.client

		pendingPurchase = nil

		return GiveVendorPurchase(self, uniqueID, client)
	end

	-- Only quantity is allowed to differ between stacks of the same item; anything else keeps its own instance.
	if (istable(data)) then
		for key in pairs(data) do
			if (key != "quantity") then
				return ix.stack.StockAdd(self, uniqueID, quantity, data, x, y, noReplication)
			end
		end
	end

	quantity = quantity or 1

	local each = istable(data) and tonumber(data.quantity) or 1

	if (!ix.stack.IsFiniteNumber(quantity) or quantity <= 0 or !ix.stack.IsFiniteNumber(each) or each <= 0) then
		return false, "noOwner"
	end

	local total = ix.stack.Normalize(itemTable, quantity * each)

	if (total <= 0) then
		return false, "noOwner"
	end

	if (!ix.stack.CanGive(self, uniqueID, total)) then
		return false, "noFit"
	end

	local bSuccess, leftover = ix.stack.Give(self, uniqueID, total)

	-- CanGive said it fits, so this only happens if a hook refused a bag; drop the rest rather than lose it.
	if (!bSuccess) then
		local owner = self.GetOwner and self:GetOwner()

		if (IsValid(owner)) then
			ix.stack.Spawn(uniqueID, owner, leftover)
		else
			return false, "noFit"
		end
	end

	return true
end
