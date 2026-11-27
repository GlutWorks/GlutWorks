
-- Server half of ix.smelting (data and formats are in sh_smelting.lua).
--
-- A smelter's state lives on the entity as entity.ixSmelting:
--   fuel      tenths of an operation of fuel
--   queue     ordered list of {input uniqueID, operations}; the first entry is smelted first
--   output    [resource uniqueID] = tenths of a kg waiting to be collected
--   progress  seconds spent on the current operation
-- All quantities are whole numbers of tenths so nothing is gained or lost to rounding. Inputs and
-- fuel leave the player's inventory through ix.stack.Take and output enters it through
-- ix.stack.Give; an operation consumes exactly one operation of fuel and one queued input and adds
-- that input's yield, and nothing else changes the totals.

ix.smelting.entities = ix.smelting.entities or {}

local FUEL_PER_OPERATION = ix.smelting.FUEL_PER_OPERATION

-- Played at the smelter when its last queued load is done.
ix.smelting.finishSound = "ambient/levels/canals/toxic_slime_sizzle3.wav"
local ToTenths = ix.smelting.ToTenths

local function NewState()
	return {fuel = 0, queue = {}, output = {}, progress = 0}
end

function ix.smelting.GetConfig(entity)
	local station = entity.GetStationTable and entity:GetStationTable()

	return station and station.smelting
end

function ix.smelting.Register(entity)
	entity.ixSmelting = NewState()
	ix.smelting.entities[entity] = true
	ix.smelting.Network(entity)
end

function ix.smelting.Unregister(entity)
	ix.smelting.entities[entity] = nil
end

local function QueuedOperations(state)
	local total = 0

	for _, entry in ipairs(state.queue) do
		total = total + entry[2]
	end

	return total
end

local function OutputTenths(state)
	local total = 0

	for _, tenths in pairs(state.output) do
		total = total + tenths
	end

	return total
end

function ix.smelting.IsEmpty(state)
	return state.fuel == 0 and #state.queue == 0 and next(state.output) == nil
end

--- Whether the smelter can run its next operation: it has fuel, something queued and room for the result.
function ix.smelting.CanRun(entity)
	local state, config = entity.ixSmelting, ix.smelting.GetConfig(entity)
	local head = state and state.queue[1]

	if (!head or !config or state.fuel < FUEL_PER_OPERATION) then
		return false
	end

	return OutputTenths(state) + ToTenths(ix.smelting.inputs[head[1]].yield) <= config.output * 10
end

--- Updates the networked tooltip state. Only called when something changed.
function ix.smelting.Network(entity)
	local state, config = entity.ixSmelting, ix.smelting.GetConfig(entity)

	entity:SetSmeltFuel(state.fuel)
	entity:SetSmeltContents(ix.smelting.Encode(state.queue, state.output))
	entity:SetSmeltEnd(ix.smelting.CanRun(entity) and CurTime() + config.time - state.progress or 0)
end

--- Runs the smelter for `seconds`, completing as many operations as fit in the time.
-- @treturn number operations completed
function ix.smelting.Advance(entity, seconds)
	local state, config = entity.ixSmelting, ix.smelting.GetConfig(entity)

	if (!state or !config) then
		return 0
	end

	if (!ix.smelting.CanRun(entity)) then
		state.progress = 0
		return 0
	end

	local completed = 0
	state.progress = state.progress + seconds

	while (state.progress >= config.time and ix.smelting.CanRun(entity)) do
		local head = state.queue[1]
		local input = ix.smelting.inputs[head[1]]

		state.progress = state.progress - config.time
		state.fuel = state.fuel - FUEL_PER_OPERATION
		state.output[input.result] = (state.output[input.result] or 0) + ToTenths(input.yield)
		head[2] = head[2] - 1

		if (head[2] <= 0) then
			table.remove(state.queue, 1)
		end

		completed = completed + 1
	end

	-- time left over when the smelter runs dry does not carry over to the next operation
	if (!ix.smelting.CanRun(entity)) then
		state.progress = 0
	end

	if (completed > 0) then
		ix.smelting.Network(entity)

		-- the batch is done: everyone near hears it, and the fire (and its smoke) dies down on the clients
		if (#state.queue == 0) then
			entity:EmitSound(ix.smelting.finishSound, 70, math.random(96, 104), 0.9)
		end
	end

	return completed
end

--- Moves as much of a fuel from the inventory into the smelter as it has room for.
-- @treturn bool whether anything was added
-- @treturn string message for the player
function ix.smelting.AddFuel(entity, inventory, uniqueID)
	local value = ix.smelting.fuels[uniqueID]
	local state, config = entity.ixSmelting, ix.smelting.GetConfig(entity)
	local itemTable = ix.item.list[uniqueID]

	if (!value or !itemTable) then
		return false, "That cannot be used as fuel."
	end

	-- weighed fuel goes in 0.1 kg steps, anything else whole items at a time (both in tenths of a unit)
	local step = ix.stack.IsStackable(itemTable) and 1 or 10
	local have = ToTenths(ix.stack.Count(inventory, uniqueID))
	local room = math.floor((config.fuel * FUEL_PER_OPERATION - state.fuel) / value)
	local take = math.min(have, room)
	take = take - take % step

	if (have < step) then
		return false, "You do not have any " .. itemTable.name .. "."
	elseif (take <= 0) then
		return false, "The smelter cannot hold any more fuel."
	end

	if (!ix.stack.Take(inventory, uniqueID, take / 10)) then
		return false, "You do not have that much " .. itemTable.name .. "."
	end

	state.fuel = state.fuel + take * value

	return true, "You add " .. ix.smelting.Describe(uniqueID, take) .. " as fuel."
end

--- Queues as many whole operations of an input from the inventory as the smelter has room for.
function ix.smelting.AddInput(entity, inventory, uniqueID)
	local input = ix.smelting.inputs[uniqueID]
	local state, config = entity.ixSmelting, ix.smelting.GetConfig(entity)
	local itemTable = ix.item.list[uniqueID]

	if (!input or !itemTable) then
		return false, "That cannot be smelted."
	end

	local perOperation = ToTenths(input.amount)
	local have = ToTenths(ix.stack.Count(inventory, uniqueID))
	local operations = math.min(math.floor(have / perOperation), config.input - QueuedOperations(state))

	if (have < perOperation) then
		return false, "You need at least " .. ix.smelting.Describe(uniqueID, perOperation) .. "."
	elseif (operations <= 0) then
		return false, "The smelter is full."
	end

	local taken = operations * perOperation

	if (!ix.stack.Take(inventory, uniqueID, taken / 10)) then
		return false, "You do not have that much " .. itemTable.name .. "."
	end

	local last = state.queue[#state.queue]

	if (last and last[1] == uniqueID) then
		last[2] = last[2] + operations
	else
		state.queue[#state.queue + 1] = {uniqueID, operations}
	end

	return true, "You put " .. ix.smelting.Describe(uniqueID, taken) .. " in the smelter."
end

--- Gives the finished output to the inventory. Whatever does not fit stays in the smelter.
function ix.smelting.Collect(entity, inventory)
	local state = entity.ixSmelting
	local collected = false

	if (next(state.output) == nil) then
		return false, "There is nothing to collect."
	end

	for uniqueID, tenths in SortedPairs(table.Copy(state.output)) do
		local bSuccess, leftover = ix.stack.Give(inventory, uniqueID, tenths / 10)
		local left = bSuccess and 0 or math.Clamp(ToTenths(leftover or tenths / 10), 0, tenths)

		state.output[uniqueID] = left > 0 and left or nil
		collected = collected or left < tenths
	end

	if (!collected) then
		return false, "You have no room for the smelter's output."
	end

	return true, next(state.output) and "You take what fits; the rest stays in the smelter." or "You collect the smelter's output."
end

--- Runs a menu choice made by a player at the smelter. The entity has checked range and state.
function ix.smelting.HandleAction(entity, client, data)
	local inventory = client:GetCharacter():GetInventory()
	local bSuccess, message

	if (data.action == "fuel" and isstring(data.uniqueID)) then
		bSuccess, message = ix.smelting.AddFuel(entity, inventory, data.uniqueID)
	elseif (data.action == "smelt" and isstring(data.uniqueID)) then
		bSuccess, message = ix.smelting.AddInput(entity, inventory, data.uniqueID)
	elseif (data.action == "collect") then
		bSuccess, message = ix.smelting.Collect(entity, inventory)
	else
		return
	end

	if (bSuccess) then
		ix.smelting.Network(entity)

		-- inventories are saved immediately, so the smelter is too: a crash must not undo one side only
		if (ix.station) then
			ix.station.Save()
		end
	end

	if (message) then
		client:Notify(message)
	end
end

--- A copy of the smelter's state for saving, or nil when it is empty.
function ix.smelting.Serialize(entity)
	local state = entity.ixSmelting

	if (!state or ix.smelting.IsEmpty(state)) then
		return nil
	end

	return table.Copy(state)
end

--- Restores a saved state, dropping anything that no longer exists in the definitions above.
function ix.smelting.Restore(entity, data)
	if (!entity.ixSmelting or !istable(data)) then
		return
	end

	local state = NewState()
	state.fuel = math.max(math.floor(tonumber(data.fuel) or 0), 0)
	state.progress = math.max(tonumber(data.progress) or 0, 0)

	for _, entry in ipairs(istable(data.queue) and data.queue or {}) do
		local count = istable(entry) and math.floor(tonumber(entry[2]) or 0)

		if (count and count > 0 and ix.smelting.inputs[entry[1]] and ix.item.list[entry[1]]) then
			state.queue[#state.queue + 1] = {entry[1], count}
		end
	end

	for uniqueID, tenths in pairs(istable(data.output) and data.output or {}) do
		tenths = math.floor(tonumber(tenths) or 0)

		if (isstring(uniqueID) and ix.item.list[uniqueID] and tenths > 0) then
			state.output[uniqueID] = tenths
		end
	end

	entity.ixSmelting = state
	ix.smelting.Network(entity)
end

timer.Create("ixSmelting", 1, 0, function()
	for entity in pairs(ix.smelting.entities) do
		if (IsValid(entity)) then
			ix.smelting.Advance(entity, 1)
		else
			ix.smelting.entities[entity] = nil
		end
	end
end)
