
-- Smelting: a station whose definition has a `smelting` table (see ixcraft/stations/sh_smelter.lua)
-- burns fuel to turn ore and smeltable junk into resources, one operation at a time.
-- Everything a smelter accepts and produces is defined in this file.
ix.smelting = ix.smelting or {}

-- How many operations one unit of each fuel powers. A unit is 1 kg of a weighed (stackable) item,
-- or one item otherwise; weighed fuel can be added in 0.1 kg steps.
ix.smelting.fuels = {
	coal = 4,
	coal_ore = 2
}

-- One operation consumes `amount` units of the input and produces `yield` kg of `result`.
-- Amounts and yields are in 0.1 steps.
ix.smelting.inputs = {
	iron_ore = {amount = 1, result = "iron", yield = 0.5},
	copper_ore = {amount = 1, result = "copper", yield = 0.5},
	-- there are no tin or gold resources yet, so these ores only give metal scrap
	tin_ore = {amount = 1, result = "metal_scrap", yield = 0.5},
	gold_ore = {amount = 1, result = "metal_scrap", yield = 0.5},

	iron1_junk = {amount = 1, result = "iron", yield = 0.5},
	iron2_junk = {amount = 1, result = "iron", yield = 0.5},
	iron3_junk = {amount = 1, result = "iron", yield = 0.3},
	iron4_junk = {amount = 1, result = "iron", yield = 1.5},
	iron5_junk = {amount = 1, result = "iron", yield = 0.2},
	iron6_junk = {amount = 1, result = "iron", yield = 0.5},
	iron7_junk = {amount = 1, result = "iron", yield = 0.5},
	steel1_junk = {amount = 1, result = "iron", yield = 0.3},
	steel2_junk = {amount = 1, result = "iron", yield = 1},
	alloy1_junk = {amount = 1, result = "metal_scrap", yield = 0.5},
	alloy2_junk = {amount = 1, result = "metal_scrap", yield = 1.5}
}

-- Fuel is kept in tenths of an operation, so that 0.1 kg of any fuel is a whole number.
ix.smelting.FUEL_PER_OPERATION = 10

--- Converts a quantity in 0.1 steps to a whole number of tenths.
function ix.smelting.ToTenths(quantity)
	return math.Round((tonumber(quantity) or 0) * 10)
end

--- Formats a quantity of an item: "1.5 kg" for weighed items, "x3" otherwise.
function ix.smelting.FormatQuantity(uniqueID, tenths)
	local itemTable = ix.item.list[uniqueID]

	if (itemTable and itemTable.stackLimit) then
		return string.format("%.1f %s", tenths / 10, itemTable.stackUnit or "kg")
	end

	return "x" .. math.Round(tenths / 10)
end

--- Describes a quantity of an item in a sentence: "1.5 kg of Iron Ore", "2 Empty Can".
function ix.smelting.Describe(uniqueID, tenths)
	local itemTable = ix.item.list[uniqueID]
	local name = itemTable and itemTable.name or uniqueID

	if (itemTable and itemTable.stackLimit) then
		return ix.smelting.FormatQuantity(uniqueID, tenths) .. " of " .. name
	end

	return math.Round(tenths / 10) .. " " .. name
end

function ix.smelting.GetItemName(uniqueID)
	local itemTable = ix.item.list[uniqueID]

	return itemTable and itemTable.name or uniqueID
end

-- The queue and the finished output reach clients as one short networked string:
-- "iron_ore*3,iron1_junk*1|iron*15" is three iron ore operations and one iron sheet queued, and
-- 1.5 kg iron ready. Queue counts are operations, output counts tenths of a kg.
function ix.smelting.Encode(queue, output)
	local queued, ready = {}, {}

	for _, entry in ipairs(queue) do
		queued[#queued + 1] = entry[1] .. "*" .. entry[2]
	end

	for uniqueID, tenths in SortedPairs(output) do
		ready[#ready + 1] = uniqueID .. "*" .. tenths
	end

	return table.concat(queued, ",") .. "|" .. table.concat(ready, ",")
end

function ix.smelting.Decode(text)
	local queuedText, readyText = string.match(text or "", "^([^|]*)|(.*)$")
	local queue, output = {}, {}

	for uniqueID, count in string.gmatch(queuedText or "", "([%w_]+)%*(%d+)") do
		queue[#queue + 1] = {uniqueID, tonumber(count)}
	end

	for uniqueID, tenths in string.gmatch(readyText or "", "([%w_]+)%*(%d+)") do
		output[uniqueID] = tonumber(tenths)
	end

	return queue, output
end

local NUMBERS = {"one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"}

local function Number(count)
	return NUMBERS[count] or tostring(count)
end

local function Loads(count, bMore)
	return Number(count) .. (bMore and " more" or "") .. (count == 1 and " load" or " loads")
end

--- What a smelter is doing, in words a person would use, as the rows Examine reads: {id, text} for whether it
-- burns and how far along it is, its fuel, what is inside and what is ready. Read from the networked state, so
-- it is the same on the server and on every client. It never gives seconds.
-- @entity entity A smelter station
-- @number[opt] now The time to describe it at (CurTime())
-- @treturn table Ordered rows
function ix.smelting.DescribeState(entity, now)
	local station = entity.GetStationTable and entity:GetStationTable()
	local config = station and station.smelting

	if (!config) then
		return {}
	end

	now = now or CurTime()

	local queue, output = ix.smelting.Decode(entity:GetSmeltContents())
	local fuel = entity:GetSmeltFuel()
	local smeltEnd = entity:GetSmeltEnd()
	local loads = fuel / ix.smelting.FUEL_PER_OPERATION
	local queued = 0
	local rows = {}

	for _, entry in ipairs(queue) do
		queued = queued + entry[2]
	end

	local function Add(id, text)
		rows[#rows + 1] = {id = id, text = text}
	end

	if (smeltEnd > 0) then
		-- the loads still to run, as far as the fuel goes, counting what is left of the current one
		local current = math.Clamp((smeltEnd - now) / config.time, 0, 1)
		local left = math.max(math.min(queued, math.floor(loads)) - 1, 0) + current

		if (left <= 0.5) then
			Add("smeltStatus", "It is burning and nearly done")
		elseif (left <= 2.5) then
			Add("smeltStatus", "It is burning and will be done soon")
		else
			Add("smeltStatus", "It is burning, with a good while to go")
		end
	elseif (fuel > 0) then
		if (queued > 0 and loads < 1) then
			Add("smeltStatus", "Embers glow inside, but there is not enough fuel to smelt")
		elseif (queued > 0) then
			Add("smeltStatus", "Embers glow inside, but it has no room for more until it is emptied")
		else
			Add("smeltStatus", "Embers glow inside, but nothing is smelting")
		end
	elseif (queued > 0 or next(output)) then
		Add("smeltStatus", "It is cold")
	else
		Add("smeltStatus", "It is cold and empty")
	end

	-- Whole loads the fuel can still start. A load's fuel is taken when it finishes, so while one burns its fuel
	-- is still counted and is not another load.
	local bBurning = smeltEnd > 0
	local startable = math.floor(loads) - (bBurning and 1 or 0)

	if (bBurning) then
		if (startable <= 0) then
			Add("smeltFuel", "There is no fuel for another load")
		else
			Add("smeltFuel", "There is fuel for " .. Loads(startable, true))
		end
	elseif (fuel <= 0) then
		if (queued > 0) then
			Add("smeltFuel", "There is no fuel")
		end
	elseif (startable < 1) then
		Add("smeltFuel", "There is a little fuel, not enough for a load")
	else
		Add("smeltFuel", "There is fuel for " .. Loads(startable, false))
	end

	if (queued > 0) then
		local inside = {}

		for _, entry in ipairs(queue) do
			local input = ix.smelting.inputs[entry[1]]
			local tenths = input and ix.smelting.ToTenths(input.amount) * entry[2] or 0

			inside[#inside + 1] = ix.smelting.GetItemName(entry[1]) .. " " .. ix.smelting.FormatQuantity(entry[1], tenths)
		end

		Add("smeltInside", "Inside: " .. table.concat(inside, ", "))
	end

	if (next(output)) then
		local ready = {}

		for uniqueID, tenths in SortedPairs(output) do
			ready[#ready + 1] = ix.smelting.GetItemName(uniqueID) .. " " .. ix.smelting.FormatQuantity(uniqueID, tenths)
		end

		Add("smeltReady", "Ready to collect: " .. table.concat(ready, ", "))
	end

	return rows
end

--- Whether a smelter holds finished output.
function ix.smelting.HasOutput(entity)
	local _, output = ix.smelting.Decode(entity:GetSmeltContents())

	return next(output) != nil
end
