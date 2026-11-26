
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
