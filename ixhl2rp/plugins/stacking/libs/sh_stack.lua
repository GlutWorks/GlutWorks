
--- Item stacks. A stack is one item instance whose quantity is `data.quantity`; the definition's
-- `stackLimit` caps it and `stackStep` is the smallest amount it can hold.
-- All arithmetic is done in whole steps ("units") so fractional quantities never drift.
ix.stack = ix.stack or {}

local function Definition(item)
	if (isstring(item)) then
		return ix.item.list[item]
	end

	return item
end

local function IsFiniteNumber(value)
	return isnumber(value) and value == value and value != math.huge and value != -math.huge
end

ix.stack.IsFiniteNumber = IsFiniteNumber

--- Whether the definition (or instance, or uniqueID) is stackable.
function ix.stack.IsStackable(itemTable)
	itemTable = Definition(itemTable)

	return istable(itemTable) and isnumber(itemTable.stackLimit) and itemTable.stackLimit > 0
end

--- The smallest amount a stack of this item can hold. Non-stackables count in whole items.
function ix.stack.GetStep(itemTable)
	itemTable = Definition(itemTable)

	local step = ix.stack.IsStackable(itemTable) and tonumber(itemTable.stackStep) or 1

	if (!IsFiniteNumber(step) or step <= 0) then
		step = 1
	end

	return step
end

--- Converts a quantity to a whole number of steps, rounding to the nearest step.
function ix.stack.ToUnits(itemTable, quantity)
	local step = ix.stack.GetStep(itemTable)

	if (!IsFiniteNumber(quantity)) then
		return 0
	end

	if (step < 1) then
		return math.Round(quantity * math.Round(1 / step))
	end

	return math.Round(quantity / step)
end

--- Converts a whole number of steps back to a quantity. Dividing by 1/step instead of multiplying by step
-- yields the nearest double, so 3 steps of 0.1 is 0.3 and not 0.30000000000000004.
function ix.stack.FromUnits(itemTable, units)
	local step = ix.stack.GetStep(itemTable)

	if (step < 1) then
		return units / math.Round(1 / step)
	end

	return units * step
end

--- Rounds a quantity to the item's step.
function ix.stack.Normalize(itemTable, quantity)
	return ix.stack.FromUnits(itemTable, ix.stack.ToUnits(itemTable, quantity))
end

--- The stack limit in steps; 1 for non-stackables.
function ix.stack.GetLimitUnits(itemTable)
	itemTable = Definition(itemTable)

	if (!ix.stack.IsStackable(itemTable)) then
		return 1
	end

	return math.max(ix.stack.ToUnits(itemTable, itemTable.stackLimit), 1)
end

--- The quantity of an item instance; 1 for non-stackables.
function ix.stack.GetQuantity(item)
	if (!istable(item)) then
		return 0
	end

	if (!ix.stack.IsStackable(item)) then
		return 1
	end

	-- A negative stored quantity (a corrupt row) counts as empty rather than subtracting from totals.
	return math.max(ix.stack.Normalize(item, tonumber(item:GetData("quantity", 1)) or 1), 0)
end

function ix.stack.GetUnits(item)
	return ix.stack.ToUnits(item, ix.stack.GetQuantity(item))
end

--- Formats a quantity with the item's unit, e.g. "4.5 kg" or "3 gears".
function ix.stack.Format(itemTable, quantity)
	itemTable = Definition(itemTable)

	local step = ix.stack.GetStep(itemTable)
	local text

	if (step < 1) then
		local decimals = math.ceil(math.log10(math.Round(1 / step)))

		text = string.format("%." .. decimals .. "f", ix.stack.Normalize(itemTable, quantity))
		text = text:find("%.") and text:gsub("0+$", ""):gsub("%.$", "") or text
	else
		text = tostring(ix.stack.Normalize(itemTable, quantity))
	end

	local unit = istable(itemTable) and itemTable.stackUnit

	if (isstring(unit) and unit != "") then
		return text .. " " .. unit
	end

	return text
end

--- Every instance of uniqueID in the inventory and the bags inside it, oldest first.
function ix.stack.GetStacks(inventory, uniqueID)
	local stacks = {}

	if (!inventory or !inventory.GetItems) then
		return stacks
	end

	for _, item in pairs(inventory:GetItems()) do
		if (item.uniqueID == uniqueID) then
			stacks[#stacks + 1] = item
		end
	end

	table.sort(stacks, function(a, b)
		return a:GetID() < b:GetID()
	end)

	return stacks
end

--- Total quantity of uniqueID across the inventory, including bags inside it.
function ix.stack.Count(inventory, uniqueID)
	local units = 0

	for _, item in ipairs(ix.stack.GetStacks(inventory, uniqueID)) do
		units = units + ix.stack.GetUnits(item)
	end

	return ix.stack.FromUnits(uniqueID, units)
end

--- The item instance and its quantity for an ix_item entity, or nil if the entity is not one.
-- On the client, where world items have no instance, the definition is returned with the networked quantity.
function ix.stack.FromEntity(entity)
	if (!IsValid(entity) or entity:GetClass() != "ix_item") then
		return
	end

	if (SERVER) then
		local item = ix.item.instances[entity.ixItemID]

		if (!item) then
			return
		end

		return item, ix.stack.GetQuantity(item)
	end

	local itemTable = entity:GetItemTable()

	if (!itemTable) then
		return
	end

	local quantity = 1

	if (ix.stack.IsStackable(itemTable)) then
		quantity = ix.stack.Normalize(itemTable, tonumber(entity:GetData("quantity", 1)) or 1)
	end

	return itemTable, quantity
end

--- Whether source can be merged into target, ignoring who is asking. Used for the drag highlight and as the
-- first step of the server-side combine.
function ix.stack.CanCombine(target, source)
	if (!istable(target) or !istable(source)) then
		return false, "stackInvalid"
	end

	if (target:GetID() == source:GetID()) then
		return false, "stackInvalid"
	end

	if (target.uniqueID != source.uniqueID or !ix.stack.IsStackable(target)) then
		return false, "stackMismatch"
	end

	if (ix.stack.GetUnits(target) >= ix.stack.GetLimitUnits(target)) then
		return false, "stackFull"
	end

	return true
end

-- Members of base_stackable every stackable definition receives unless it defines its own.
local INHERITED = {"PaintOver", "PopulateTooltip", "OnEntityTakeDamage"}
local INHERITED_FUNCTIONS = {"combine", "split"}

--- Gives a stackable definition the members of base_stackable. The stock "take" is always replaced, because
-- Helix gives every item a default one that would not merge into existing stacks.
function ix.stack.ApplyBase(itemTable)
	local base = ix.item.base["base_stackable"]

	if (!base or !ix.stack.IsStackable(itemTable)) then
		return
	end

	for _, key in ipairs(INHERITED) do
		if (itemTable[key] == nil) then
			itemTable[key] = base[key]
		end
	end

	itemTable.functions = itemTable.functions or {}

	for _, key in ipairs(INHERITED_FUNCTIONS) do
		if (itemTable.functions[key] == nil) then
			itemTable.functions[key] = base.functions[key]
		end
	end

	itemTable.functions.take = base.functions.take
end

function ix.stack.ApplyBaseToAll()
	for _, itemTable in pairs(ix.item.list) do
		ix.stack.ApplyBase(itemTable)
	end
end

--- The quantity of a stackable that changes hands in one vendor trade (sv_stack.lua has the trades).
function ix.stack.GetTradeAmount(uniqueID)
	local itemTable = ix.item.list[uniqueID]
	local units = math.max(ix.stack.ToUnits(itemTable, tonumber(itemTable.tradeAmount) or 1), 1)

	return ix.stack.FromUnits(itemTable, units)
end
