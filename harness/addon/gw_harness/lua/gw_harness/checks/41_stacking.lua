-- Stacking checks: the ix.stack API, the stackable item actions (take, combine, split) through the same
-- server entry point the client's net messages reach, stock Inventory:Add, and every ixcraft recipe.
-- Every operation is followed by a balance check: the total quantity before and after must add up.

local FILLER = "iron3_junk" -- 1x1, not stackable, not used by any recipe
local SCRAP = "metal_scrap" -- resource: kg, 0.1 steps, limit 20

local function Stack() return ix.stack end

local function Inventory(bot)
	return bot:GetCharacter():GetInventory()
end

-- Empties the bot's inventory and returns it.
local function Fresh(bot)
	local inventory = Inventory(bot)

	for _, item in pairs(inventory:GetItems()) do
		item:Remove()
	end

	for x = 1, inventory.w do
		for y = 1, inventory.h do
			if (inventory.slots[x] and inventory.slots[x][y] == true) then
				inventory.slots[x][y] = nil
			end
		end
	end

	return inventory
end

local function FreeCells(inventory)
	local free = 0

	for x = 1, inventory.w do
		for y = 1, inventory.h do
			if (!(inventory.slots[x] and inventory.slots[x][y])) then
				free = free + 1
			end
		end
	end

	return free
end

-- Fills the inventory with 1x1 filler until only `leave` cells are free.
local function Fill(inventory, leave)
	while (FreeCells(inventory) > leave) do
		if (!ix.stack.StockAdd(inventory, FILLER, 1)) then
			break
		end
	end
end

-- Makes one new stack with an exact quantity, bypassing merging.
local function NewStack(inventory, uniqueID, quantity)
	local before = {}

	for _, item in ipairs(Stack().GetStacks(inventory, uniqueID)) do
		before[item:GetID()] = true
	end

	ix.stack.StockAdd(inventory, uniqueID, 1, Stack().IsStackable(uniqueID) and {quantity = quantity} or nil)

	for _, item in ipairs(Stack().GetStacks(inventory, uniqueID)) do
		if (!before[item:GetID()]) then
			return item
		end
	end
end

local function Quantities(inventory, uniqueID)
	local list = {}

	for _, item in ipairs(Stack().GetStacks(inventory, uniqueID)) do
		list[#list + 1] = item:GetData("quantity", 1)
	end

	table.sort(list, function(a, b) return a > b end)

	return table.concat(list, ",")
end

-- Every stored quantity must be an exact multiple of the step (no 0.30000000000000004).
local function CheckClean(fail, inventory, uniqueID, label)
	for _, item in ipairs(Stack().GetStacks(inventory, uniqueID)) do
		local stored = item:GetData("quantity", 1)

		if (stored != Stack().Normalize(item, stored) or #tostring(stored) > 8) then
			fail(label .. ": stored quantity drifted: " .. string.format("%.17g", stored))
		end

		if (stored > item.stackLimit or stored <= 0) then
			fail(label .. ": stored quantity out of range: " .. tostring(stored))
		end
	end
end

local function Expect(fail, label, actual, expected)
	if (actual != expected) then
		fail(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function DBRow(id)
	return sql.Query("SELECT item_id FROM ix_items WHERE item_id = " .. tonumber(id)) != nil
end

-- Places a world stack within reach in front of the bot.
local function SpawnNear(bot, uniqueID, quantity, distance)
	local spawned

	Stack().Spawn(uniqueID, bot:GetShootPos() + bot:GetAimVector() * (distance or 30), quantity, angle_zero,
		function(item, entity) spawned = {item = item, entity = entity} end)

	return spawned
end

-- Answers the bot's open Split prompt the way the client does: an ixStackSplit message naming the stack.
local function Answer(bot, text)
	local itemID = bot.gwhSplitPrompt

	if (!itemID) then
		return false
	end

	bot.gwhSplitPrompt = nil
	bot.ixStackSplitNext = nil

	local readUInt, readString = net.ReadUInt, net.ReadString

	net.ReadUInt = function() return itemID end
	net.ReadString = function() return text end

	local ok, fault = pcall(net.Receivers["ixstacksplit"], 0, bot)

	net.ReadUInt, net.ReadString = readUInt, readString

	if (!ok) then
		error(fault, 0)
	end

	return true
end

-- Earlier checks leave items and props around the bot until the next tick, and entities removed in this tick
-- still exist; PerformInventoryAction refuses a world item that is not the player's use entity, so move every
-- other loose entity out of the way first.
local function ClearAround(bot, keep)
	for _, entity in ipairs(ents.FindInSphere(bot:GetShootPos(), 200)) do
		if (entity != keep and entity != bot and entity:GetOwner() != bot and !entity:IsPlayer() and
			(entity:GetClass() == "ix_item" or IsValid(entity:GetPhysicsObject()))) then
			entity:SetPos(entity:GetPos() + Vector(0, 0, 4000))
		end
	end
end

-- Runs an item action the way the ixInventoryAction / ixItemEntityAction receivers do: by instance ID, or by entity.
local function Act(bot, action, item, data)
	if (isentity(item)) then
		ClearAround(bot, item)

		local useEntity = bot:GetUseEntity()

		if (IsValid(useEntity) and useEntity != item) then
			error("the bot's use entity is " .. tostring(useEntity) .. ", not " .. tostring(item))
		end

		return ix.item.PerformInventoryAction(bot, action, item)
	end

	return ix.item.PerformInventoryAction(bot, action, item:GetID(), item.invID or 0, data or {})
end

-- Entity:Remove only takes effect at the end of the tick.
local function Gone(entity)
	return !IsValid(entity) or entity:IsMarkedForDeletion()
end

GWH.Check("stacking: stackable definitions get the stack base", function(fail)
	if (!ix.stack) then return fail("ix.stack is missing") end

	local base = ix.item.base["base_stackable"]
	if (!base) then return fail("base_stackable is not registered") end

	local stackables = 0

	for uniqueID, itemTable in SortedPairs(ix.item.list) do
		if (ix.stack.IsStackable(itemTable)) then
			stackables = stackables + 1

			if (itemTable.functions.take != base.functions.take) then fail(uniqueID .. ": stock take, would not merge") end
			if (!itemTable.functions.combine or !itemTable.functions.split) then fail(uniqueID .. ": no combine/split") end
		elseif (itemTable.functions.split == base.functions.split or itemTable.functions.take == base.functions.take) then
			fail(uniqueID .. ": not stackable but has stack actions")
		end
	end

	for _, uniqueID in ipairs({"metal_scrap", "coal", "box_of_gears", "duct_tape", "iron_ore"}) do
		if (!ix.stack.IsStackable(uniqueID)) then fail(uniqueID .. " should be stackable") end
	end

	for _, uniqueID in ipairs({"wood3_junk", "iron1_junk", "car_battery", "blowtorch"}) do
		if (ix.stack.IsStackable(uniqueID)) then fail(uniqueID .. " should not be stackable") end
	end

	Expect(fail, "coal step", ix.stack.GetStep("coal"), 0.1)
	Expect(fail, "gears step", ix.stack.GetStep("box_of_gears"), 1)
	Expect(fail, "cable step", ix.stack.GetStep("cable_spool"), 0.1)
	Expect(fail, "format kg", ix.stack.Format("coal", 4.5), "4.5 kg")
	Expect(fail, "format whole kg", ix.stack.Format("coal", 4), "4 kg")
	Expect(fail, "format gears", ix.stack.Format("box_of_gears", 3), "3 gears")

	return {stackables = stackables}
end)

GWH.Check("stacking: Give, Count and Take on the bot's inventory", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = Fresh(bot)
	local S = Stack()

	-- empty inventory
	Expect(fail, "give 5 into empty", S.Give(inventory, SCRAP, 5), true)
	Expect(fail, "count after 5", S.Count(inventory, SCRAP), 5)
	Expect(fail, "stacks after 5", Quantities(inventory, SCRAP), "5")

	-- partial stack
	Expect(fail, "give 3 into partial", S.Give(inventory, SCRAP, 3), true)
	Expect(fail, "stacks after +3", Quantities(inventory, SCRAP), "8")

	-- across the stack boundary
	Expect(fail, "give 15 across limit", S.Give(inventory, SCRAP, 15), true)
	Expect(fail, "stacks after +15", Quantities(inventory, SCRAP), "20,3")
	Expect(fail, "count after +15", S.Count(inventory, SCRAP), 23)

	-- more than one full stack at once
	Expect(fail, "give 45", S.Give(inventory, SCRAP, 45), true)
	Expect(fail, "stacks after +45", Quantities(inventory, SCRAP), "20,20,20,8")
	Expect(fail, "count after +45", S.Count(inventory, SCRAP), 68)

	-- fractional quantities: no floating-point drift into stored data
	inventory = Fresh(bot)

	for _ = 1, 3 do
		S.Give(inventory, SCRAP, 0.1)
	end

	Expect(fail, "0.1 three times", S.Count(inventory, SCRAP), 0.3)
	Expect(fail, "0.1 three times stored", Quantities(inventory, SCRAP), "0.3")

	local expectedUnits = 3

	for i = 1, 60 do
		local amount = (i % 7) * 0.1 + (i % 3) * 0.7

		S.Give(inventory, SCRAP, amount)
		expectedUnits = expectedUnits + math.Round(amount * 10)
	end

	Expect(fail, "60 fractional gives", S.Count(inventory, SCRAP), expectedUnits / 10)
	CheckClean(fail, inventory, SCRAP, "fractional gives")
	Expect(fail, "input is rounded to the step", S.Give(inventory, "coal", 0.30000000000000004), true)
	Expect(fail, "rounded coal", S.Count(inventory, "coal"), 0.3)

	-- Take: all or nothing, smallest stacks first
	inventory = Fresh(bot)
	NewStack(inventory, SCRAP, 20)
	NewStack(inventory, SCRAP, 3)
	NewStack(inventory, SCRAP, 0.5)

	Expect(fail, "count 23.5", S.Count(inventory, SCRAP), 23.5)
	Expect(fail, "take more than held", S.Take(inventory, SCRAP, 23.6), false)
	Expect(fail, "nothing taken on failure", Quantities(inventory, SCRAP), "20,3,0.5")
	Expect(fail, "take 21", S.Take(inventory, SCRAP, 21), true)
	Expect(fail, "after take 21", Quantities(inventory, SCRAP), "2.5")
	Expect(fail, "take 0.7", S.Take(inventory, SCRAP, 0.7), true)
	Expect(fail, "after take 0.7", S.Count(inventory, SCRAP), 1.8)
	CheckClean(fail, inventory, SCRAP, "take")
	Expect(fail, "take exact rest", S.Take(inventory, SCRAP, 1.8), true)
	Expect(fail, "empty after taking all", #S.GetStacks(inventory, SCRAP), 0)
	Expect(fail, "take from nothing", S.Take(inventory, SCRAP, 0.1), false)
	Expect(fail, "take negative", S.Take(inventory, SCRAP, -1), false)
	Expect(fail, "take unknown item", S.Take(inventory, "no_such_item", 1), false)

	-- non-stackables count and take as separate items
	S.Give(inventory, FILLER, 3)
	Expect(fail, "non-stackable give 3", #S.GetStacks(inventory, FILLER), 3)
	Expect(fail, "non-stackable count", S.Count(inventory, FILLER), 3)
	Expect(fail, "non-stackable take 4", S.Take(inventory, FILLER, 4), false)
	Expect(fail, "non-stackable take 2", S.Take(inventory, FILLER, 2), true)
	Expect(fail, "non-stackable left", S.Count(inventory, FILLER), 1)

	-- full inventory: false plus the exact leftover, nothing lost
	inventory = Fresh(bot)
	NewStack(inventory, SCRAP, 15)
	Fill(inventory, 1)

	local ok, leftover = S.Give(inventory, SCRAP, 30.3)

	Expect(fail, "give into nearly full returns false", ok, false)
	Expect(fail, "leftover", leftover, 5.3)
	Expect(fail, "placed before running out", Quantities(inventory, SCRAP), "20,20")
	Expect(fail, "balance full give", S.Count(inventory, SCRAP) + leftover, 45.3)

	ok, leftover = S.Give(inventory, SCRAP, 2)
	Expect(fail, "give into full returns false", ok, false)
	Expect(fail, "full leftover", leftover, 2)
	Expect(fail, "full unchanged", S.Count(inventory, SCRAP), 40)

	ok, leftover = S.Give(inventory, FILLER, 2)
	Expect(fail, "non-stackable into full", ok, false)
	Expect(fail, "non-stackable leftover", leftover, 2)

	Expect(fail, "give unknown item", (S.Give(inventory, "no_such_item", 1)), false)
	Expect(fail, "give NaN", (S.Give(inventory, SCRAP, 0 / 0)), false)

	-- SetQuantity
	inventory = Fresh(bot)
	local stack = NewStack(inventory, SCRAP, 4)

	Expect(fail, "SetQuantity above limit refused", S.SetQuantity(stack, 25), false)
	Expect(fail, "SetQuantity above limit unchanged", S.GetQuantity(stack), 4)
	Expect(fail, "SetQuantity 7.7", S.SetQuantity(stack, 7.7), true)
	Expect(fail, "after SetQuantity", S.GetQuantity(stack), 7.7)
	Expect(fail, "SetQuantity 0", S.SetQuantity(stack, 0), true)
	Expect(fail, "SetQuantity 0 removes the instance", ix.item.instances[stack:GetID()], nil)
	Expect(fail, "SetQuantity 0 removes the row", DBRow(stack:GetID()), false)

	Fresh(bot)
end)

GWH.Check("stacking: Give is safe with an asynchronous database", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = Fresh(bot)
	local S = Stack()
	local stockInstance = ix.item.Instance
	local queue = {}

	-- Defer every insert, as mysqloo would: Instance returns before the item exists.
	ix.item.Instance = function(...)
		queue[#queue + 1] = {...}
	end

	local okGive, errGive = pcall(function()
		NewStack(inventory, SCRAP, 1) -- stays pending
		return S.Give(inventory, SCRAP, 45)
	end)

	local okSplit

	ix.item.Instance = stockInstance

	if (!okGive) then
		return fail("Give threw with a deferred insert: " .. tostring(errGive))
	end

	Expect(fail, "Give returns true before the inserts complete", errGive, true)
	Expect(fail, "inserts pending", #queue, 4)

	local reserved = 0

	for x = 1, inventory.w do
		for y = 1, inventory.h do
			if (inventory.slots[x] and inventory.slots[x][y] == true) then reserved = reserved + 1 end
		end
	end

	Expect(fail, "slots reserved while pending", reserved, 4)

	for _, args in ipairs(queue) do
		stockInstance(unpack(args, 1, 8))
	end

	Expect(fail, "stacks after the inserts complete", Quantities(inventory, SCRAP), "20,20,5,1")
	Expect(fail, "count after the inserts complete", S.Count(inventory, SCRAP), 46)

	-- Split with a deferred insert: the source shrinks now, the new stack appears when the insert completes.
	inventory = Fresh(bot)
	local stack = NewStack(inventory, SCRAP, 5)

	queue = {}
	ix.item.Instance = function(...)
		queue[#queue + 1] = {...}
	end

	okSplit, errGive = pcall(S.Split, bot, stack:GetID(), "2")
	ix.item.Instance = stockInstance

	if (!okSplit) then return fail("Split threw with a deferred insert: " .. tostring(errGive)) end

	Expect(fail, "split pending", #queue, 1)
	Expect(fail, "source reduced at once", S.GetQuantity(stack), 3)

	for _, args in ipairs(queue) do
		stockInstance(unpack(args, 1, 8))
	end

	Expect(fail, "split stacks after insert", Quantities(inventory, SCRAP), "3,2")

	Fresh(bot)
end)

GWH.Check("stacking: Spawn, FromEntity and pickup", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = Fresh(bot)
	local S = Stack()
	local entities = {}

	local spawned = SpawnNear(bot, SCRAP, 4.5)

	if (!spawned or !IsValid(spawned.entity)) then
		return fail("Spawn did not create an entity")
	end

	entities[#entities + 1] = spawned.entity

	local item, quantity = S.FromEntity(spawned.entity)

	Expect(fail, "FromEntity item", item, spawned.item)
	Expect(fail, "FromEntity quantity", quantity, 4.5)
	Expect(fail, "entity networks quantity", spawned.entity:GetNetVar("data", {}).quantity, 4.5)
	Expect(fail, "FromEntity non-item", S.FromEntity(bot), nil)

	-- more than one stack's worth spawns several stacks
	local count, total = 0, 0

	S.Spawn(SCRAP, bot:GetPos() + Vector(0, 0, 400), 45, angle_zero, function(spawnedItem, entity)
		count = count + 1
		total = total + S.GetQuantity(spawnedItem)
		entities[#entities + 1] = entity
	end)

	Expect(fail, "Spawn 45 entities", count, 3)
	Expect(fail, "Spawn 45 total", total, 45)

	-- pickup merges into a partial stack; the world instance and its row are deleted
	NewStack(inventory, SCRAP, 18)
	local worldID = spawned.item:GetID()

	Act(bot, "take", spawned.entity)

	Expect(fail, "pickup merges first", Quantities(inventory, SCRAP), "20,2.5")
	Expect(fail, "partial pickup moved the rest into the inventory", spawned.item.invID, inventory:GetID())
	Expect(fail, "world entity gone after pickup", Gone(spawned.entity), true)
	Expect(fail, "world list cleaned", ix.item.inventories[0][worldID], nil)

	-- fully merged pickup
	local small = SpawnNear(bot, SCRAP, 1.5)
	entities[#entities + 1] = small.entity
	local smallID = small.item:GetID()

	Act(bot, "take", small.entity)

	Expect(fail, "fully merged pickup", Quantities(inventory, SCRAP), "20,4")
	Expect(fail, "merged world entity removed", Gone(small.entity), true)
	Expect(fail, "merged instance removed", ix.item.instances[smallID], nil)
	Expect(fail, "merged row removed", DBRow(smallID), false)
	Expect(fail, "merged world list cleaned", ix.item.inventories[0][smallID], nil)

	-- pickup into a full inventory with some room in a partial stack: the rest stays in the world
	Fill(inventory, 0)

	local big = SpawnNear(bot, SCRAP, 18)
	entities[#entities + 1] = big.entity

	Act(bot, "take", big.entity)

	Expect(fail, "partial room filled", Quantities(inventory, SCRAP), "20,20")
	Expect(fail, "rest stays in the world", Gone(big.entity), false)
	Expect(fail, "world remainder", S.GetQuantity(big.item), 2)
	Expect(fail, "world remainder networked", IsValid(big.entity) and big.entity:GetNetVar("data", {}).quantity, 2)
	Expect(fail, "balance partial pickup", S.Count(inventory, SCRAP) + S.GetQuantity(big.item), 40 + 2)

	-- no room at all: nothing changes
	Act(bot, "take", big.entity)
	Expect(fail, "full pickup leaves the entity", Gone(big.entity), false)
	Expect(fail, "full pickup keeps quantity", S.GetQuantity(big.item), 2)

	-- OnItemTransferred still fires for a pickup into a free slot (bags rely on it)
	inventory = Fresh(bot)
	local transferred = false

	hook.Add("OnItemTransferred", "gwh_stacking", function(transferItem) transferred = transferred or transferItem end)
	local free = SpawnNear(bot, SCRAP, 3)
	entities[#entities + 1] = free.entity
	Act(bot, "take", free.entity)
	hook.Remove("OnItemTransferred", "gwh_stacking")

	Expect(fail, "OnItemTransferred on pickup", transferred, free.item)
	Expect(fail, "pickup into empty", Quantities(inventory, SCRAP), "3")

	for _, entity in ipairs(entities) do
		if (IsValid(entity)) then entity:Remove() end
	end

	Fresh(bot)
end)

GWH.Check("stacking: Combine validates what the client sends", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = Fresh(bot)
	local S = Stack()
	local entities = {}

	-- the normal case through the net entry point
	local a = NewStack(inventory, SCRAP, 5)
	local b = NewStack(inventory, SCRAP, 7)

	Act(bot, "combine", a, {b:GetID()})
	Expect(fail, "combine 5 + 7", Quantities(inventory, SCRAP), "12")
	Expect(fail, "combined source removed", ix.item.instances[b:GetID()], nil)
	Expect(fail, "combined source row removed", DBRow(b:GetID()), false)

	-- overflow stays in the source
	local c = NewStack(inventory, SCRAP, 10.4)
	Act(bot, "combine", a, {c:GetID()})
	Expect(fail, "combine overflow", Quantities(inventory, SCRAP), "20,2.4")
	CheckClean(fail, inventory, SCRAP, "combine overflow")

	-- refused: full target, unknown or self source, other item, same display name
	local function Refused(label, target, data, direct)
		local before = S.Count(inventory, SCRAP)
		local quantities = Quantities(inventory, SCRAP)

		Act(bot, "combine", target, data)
		Expect(fail, label .. " (net path) changed nothing", Quantities(inventory, SCRAP), quantities)

		if (direct != false) then
			local bSuccess = S.Combine(bot, target, istable(data) and data[1] or nil)

			Expect(fail, label .. " (Combine) refused", bSuccess, false)
			Expect(fail, label .. " (Combine) changed nothing", Quantities(inventory, SCRAP), quantities)
		end

		Expect(fail, label .. " balance", S.Count(inventory, SCRAP), before)
	end

	Refused("full target", a, {c:GetID()})
	Refused("unknown source", c, {987654321})
	Refused("source is target", c, {c:GetID()})
	Refused("non-numeric source", c, {"x"})
	Refused("no data", c, nil)

	local wood = NewStack(inventory, "wooden_scrap", 2)
	local junk = NewStack(inventory, "wood3_junk")
	local gears = NewStack(inventory, "box_of_gears", 2)

	Refused("same display name, other item", wood, {junk:GetID()})
	Expect(fail, "junk not absorbed", ix.item.instances[junk:GetID()] != nil, true)
	Expect(fail, "wooden scrap unchanged", S.GetQuantity(wood), 2)
	Refused("different stackable", c, {gears:GetID()})

	-- a stack in an inventory the bot cannot open
	local foreign = ix.inventory.Create(4, 4, 2000000000 + math.random(1, 100000))
	local foreignStack = NewStack(foreign, SCRAP, 3)

	if (!foreignStack) then
		fail("could not create a stack in a foreign inventory")
	else
		Refused("source in an inventory the bot cannot access", c, {foreignStack:GetID()})
		Expect(fail, "foreign stack untouched", S.GetQuantity(foreignStack), 3)

		local bSuccess = S.Combine(bot, foreignStack, c:GetID())
		Expect(fail, "target in an inventory the bot cannot access", bSuccess, false)
		Expect(fail, "foreign target untouched", S.GetQuantity(foreignStack), 3)
		foreignStack:Remove()
	end

	ix.item.inventories[foreign:GetID()] = nil

	-- world items: out of reach refused, within reach allowed, overflow back into the world target
	local far = SpawnNear(bot, SCRAP, 4, 2000)
	entities[#entities + 1] = far.entity

	Refused("world source out of reach", c, {far.item:GetID()})
	Expect(fail, "far world stack untouched", S.GetQuantity(far.item), 4)

	local near = SpawnNear(bot, SCRAP, 15)
	entities[#entities + 1] = near.entity
	local before = S.Count(inventory, SCRAP) + S.GetQuantity(near.item)

	Expect(fail, "world target within reach", S.Combine(bot, near.item, c:GetID()), true)
	Expect(fail, "world target filled", S.GetQuantity(near.item), 17.4)
	Expect(fail, "world target networked", near.entity:GetNetVar("data", {}).quantity, 17.4)
	Expect(fail, "balance world target", S.Count(inventory, SCRAP) + S.GetQuantity(near.item), before)

	local d = NewStack(inventory, SCRAP, 6)
	before = S.Count(inventory, SCRAP) + S.GetQuantity(near.item)

	Expect(fail, "world target overflow", S.Combine(bot, near.item, d:GetID()), true)
	Expect(fail, "world target at limit", S.GetQuantity(near.item), 20)
	Expect(fail, "overflow left in source", S.GetQuantity(d), 3.4)
	Expect(fail, "balance world overflow", S.Count(inventory, SCRAP) + S.GetQuantity(near.item), before)

	-- a world source within reach that is used up entirely is deleted with its row
	local loose = SpawnNear(bot, SCRAP, 1.6, 40)
	entities[#entities + 1] = loose.entity
	local looseID = loose.item:GetID()
	local e = NewStack(inventory, SCRAP, 2)

	Expect(fail, "world source within reach", S.Combine(bot, e, looseID), true)
	Expect(fail, "world source absorbed", S.GetQuantity(e), 3.6)
	Expect(fail, "absorbed world instance removed", ix.item.instances[looseID], nil)
	Expect(fail, "absorbed world row removed", DBRow(looseID), false)
	Expect(fail, "absorbed world entity removed", Gone(loose.entity), true)

	for _, entity in ipairs(entities) do
		if (IsValid(entity)) then entity:Remove() end
	end

	Fresh(bot)
end)

GWH.Check("stacking: Split validates the answer when it arrives", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = Fresh(bot)
	local S = Stack()

	-- The client opens the prompt itself when the menu offers Split.
	local function Ask(item)
		local split = item.functions.split

		bot.gwhSplitPrompt = (split.OnCanRun(item) != false and isfunction(split.OnClick)) and item:GetID() or nil

		return bot.gwhSplitPrompt != nil
	end

	local stack = NewStack(inventory, SCRAP, 5)

	Expect(fail, "split asks for an amount", Ask(stack), true)
	Answer(bot, "1.5")
	Expect(fail, "split 1.5", Quantities(inventory, SCRAP), "3.5,1.5")

	for _, text in ipairs({"abc", "", "nan", "inf", "-inf", "1e999", "-1", "0", "0x10", "3.5", "4", "0.25", " "}) do
		local quantities = Quantities(inventory, SCRAP)

		Ask(stack)
		Answer(bot, text)
		Expect(fail, "split '" .. text .. "' refused", Quantities(inventory, SCRAP), quantities)
	end

	Ask(stack)
	Answer(bot, "0.3")
	Expect(fail, "split 0.3", Quantities(inventory, SCRAP), "3.2,1.5,0.3")
	CheckClean(fail, inventory, SCRAP, "split")

	-- the stack shrinks between the prompt and the answer
	Ask(stack)
	S.Take(inventory, SCRAP, 4.8) -- takes the 0.3 and 1.5 stacks and 3 kg of this one
	Expect(fail, "stack shrank", S.GetQuantity(stack), 0.2)
	Answer(bot, "2")
	Expect(fail, "stale split refused", Quantities(inventory, SCRAP), "0.2")

	-- the stack is gone when the answer arrives
	Ask(stack)
	S.Take(inventory, SCRAP, 0.2)
	Answer(bot, "0.1")
	Expect(fail, "split of a removed stack makes nothing", S.Count(inventory, SCRAP), 0)

	-- whole-piece step
	local gears = NewStack(inventory, "box_of_gears", 4)

	Ask(gears)
	Answer(bot, "1.5")
	Expect(fail, "gears 1.5 refused", Quantities(inventory, "box_of_gears"), "4")
	Ask(gears)
	Answer(bot, "1")
	Expect(fail, "gears split 1", Quantities(inventory, "box_of_gears"), "3,1")

	-- no free slot: refused, nothing changes
	inventory = Fresh(bot)
	stack = NewStack(inventory, SCRAP, 5)
	Fill(inventory, 0)
	Ask(stack)
	Answer(bot, "1")
	Expect(fail, "split without room refused", Quantities(inventory, SCRAP), "5")

	-- someone else's stack
	local foreign = ix.inventory.Create(2, 2, 2000000000 + math.random(100001, 200000))
	local foreignStack = NewStack(foreign, SCRAP, 4)

	if (foreignStack) then
		Expect(fail, "split of an inaccessible stack refused", (S.Split(bot, foreignStack:GetID(), "1")), false)
		Expect(fail, "inaccessible stack untouched", S.GetQuantity(foreignStack), 4)
		foreignStack:Remove()
	end

	ix.item.inventories[foreign:GetID()] = nil

	-- no split offered for one step or for world items
	inventory = Fresh(bot)
	local single = NewStack(inventory, "box_of_gears", 1)
	Expect(fail, "no split for a single piece", single.functions.split.OnCanRun(single), false)

	Fresh(bot)
end)

GWH.Check("stacking: stock Inventory:Add and the item-added hook", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = Fresh(bot)
	local S = Stack()
	local added = {}
	local errorsBefore = #GWH.errors

	hook.Add("InventoryItemAdded", "gwh_stacking", function(oldInv, newInv, item)
		added[#added + 1] = item
	end)

	-- non-stackables keep the stock meaning: n separate items
	Expect(fail, "Add non-stackable x3", inventory:Add(FILLER, 3) != false, true)
	Expect(fail, "three filler items", #S.GetStacks(inventory, FILLER), 3)

	-- stackables merge
	Expect(fail, "Add stackable x3", inventory:Add(SCRAP, 3) != false, true)
	Expect(fail, "Add stackable merged", Quantities(inventory, SCRAP), "3")
	Expect(fail, "Add with quantity data", inventory:Add(SCRAP, 1, {quantity = 2.5}) != false, true)
	Expect(fail, "Add with quantity merged", Quantities(inventory, SCRAP), "5.5")

	-- the hook only ever sees real instances
	for _, item in ipairs(added) do
		if (!istable(item) or !item.id or ix.item.instances[item.id] != item) then
			fail("InventoryItemAdded got something that is not an instance: " .. tostring(item))
		end
	end

	local countBefore = #added
	S.Give(inventory, SCRAP, 1)
	Expect(fail, "merge fires no InventoryItemAdded", #added, countBefore)

	-- all or nothing when the inventory cannot take everything
	Fill(inventory, 0)
	Expect(fail, "Add more than fits", inventory:Add(SCRAP, 1, {quantity = 15}), false)
	Expect(fail, "nothing added on failure", Quantities(inventory, SCRAP), "6.5")
	Expect(fail, "Add what fits in the partial stack", inventory:Add(SCRAP, 1, {quantity = 13.5}) != false, true)
	Expect(fail, "partial stack filled", Quantities(inventory, SCRAP), "20")
	Expect(fail, "Add non-stackable into full", inventory:Add(FILLER), false)

	hook.Remove("InventoryItemAdded", "gwh_stacking")

	for i = errorsBefore + 1, #GWH.errors do
		fail("Lua error: " .. GWH.errors[i].error)
	end

	Fresh(bot)
end)

-- Gives the bot exactly what the recipe consumes (with the first interchangeable option), less `short` steps
-- of one requirement when given.
local function GiveRequirements(inventory, recipe, shortID)
	local needs = {}

	for uniqueID, amount in pairs(recipe.requirements or {}) do
		needs[uniqueID] = (needs[uniqueID] or 0) + amount
	end

	for uniqueID, amount in SortedPairs(recipe.interchangeable_req or {}) do
		needs[uniqueID] = (needs[uniqueID] or 0) + amount
		break
	end

	for _, uniqueID in ipairs(recipe.tools or {}) do
		needs[uniqueID] = (needs[uniqueID] or 0) + 1
	end

	for uniqueID, amount in pairs(needs) do
		if (uniqueID == shortID) then
			amount = amount - ix.stack.GetStep(uniqueID)
		end

		if (amount > 0 and !ix.stack.Give(inventory, uniqueID, amount)) then
			return false
		end
	end

	return needs
end

local function Snapshot(inventory, ids)
	local counts = {}

	for uniqueID in pairs(ids) do
		counts[uniqueID] = ix.stack.Count(inventory, uniqueID)
	end

	return counts
end

GWH.Check("stacking: every recipe crafts with exactly its requirements", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft) then return {skipped = "ixcraft not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local craft = plugin.craft
	local crafted = 0
	local stations = {}

	local function Station(id)
		if (!stations[id]) then
			local entity = ents.Create("ix_station_" .. id)

			if (IsValid(entity)) then
				entity:SetPos(bot:GetPos() + Vector(40, 0, 0))
				entity:Spawn()
				stations[id] = entity
			end
		end

		return stations[id]
	end

	for recipeID, recipe in SortedPairs(craft.recipes) do
		local inventory = Fresh(bot)

		if (recipe.station and !IsValid(Station(recipe.station))) then
			fail(recipeID .. ": could not spawn station " .. recipe.station)
		end

		local needs = GiveRequirements(inventory, recipe)

		if (!needs) then
			fail(recipeID .. ": requirements do not fit the bot's inventory")
			continue
		end

		local watched = table.Copy(needs)

		for uniqueID in pairs(recipe.results or {}) do
			watched[uniqueID] = true
		end

		local before = Snapshot(inventory, watched)
		local canCraft, reason = recipe:OnCanCraft(bot)

		if (!canCraft) then
			fail(recipeID .. ": cannot craft with exactly its requirements: " .. tostring(reason))
			continue
		end

		if (!craft.CraftRecipe(bot, recipeID)) then
			fail(recipeID .. ": CraftRecipe failed with exactly its requirements")
			continue
		end

		crafted = crafted + 1

		local after = Snapshot(inventory, watched)
		local consumed = {}

		for uniqueID, amount in pairs(recipe.requirements or {}) do
			consumed[uniqueID] = (consumed[uniqueID] or 0) + amount
		end

		for uniqueID, amount in SortedPairs(recipe.interchangeable_req or {}) do
			consumed[uniqueID] = (consumed[uniqueID] or 0) + amount
			break
		end

		for uniqueID in pairs(watched) do
			local result = recipe.results and recipe.results[uniqueID]
			local gained = isnumber(result) and result or 0
			local expected = ix.stack.Normalize(uniqueID, before[uniqueID] - (consumed[uniqueID] or 0) + gained)

			if (istable(result)) then
				local low, high = result["min"] or result[1], result["max"] or result[#result]
				local delta = after[uniqueID] - before[uniqueID] + (consumed[uniqueID] or 0)

				if (delta < low or delta > high) then
					fail(recipeID .. ": " .. uniqueID .. " result " .. delta .. " outside " .. low .. "-" .. high)
				end
			elseif (after[uniqueID] != expected) then
				fail(recipeID .. ": " .. uniqueID .. " is " .. tostring(after[uniqueID]) .. " after crafting, expected " ..
					tostring(expected))
			end
		end

		-- one step short of each requirement: refused, nothing consumed
		local short = {}

		for uniqueID in pairs(recipe.requirements or {}) do short[uniqueID] = true end
		for uniqueID in SortedPairs(recipe.interchangeable_req or {}) do short[uniqueID] = true break end
		for _, uniqueID in ipairs(recipe.tools or {}) do short[uniqueID] = true end

		for shortID in SortedPairs(short) do
			inventory = Fresh(bot)

			if (!GiveRequirements(inventory, recipe, shortID)) then
				fail(recipeID .. ": short requirements do not fit")
				continue
			end

			local held = Snapshot(inventory, needs)

			if (recipe:OnCanCraft(bot) or craft.CraftRecipe(bot, recipeID)) then
				fail(recipeID .. ": crafted while one step short of " .. shortID)
			end

			for uniqueID, amount in pairs(Snapshot(inventory, needs)) do
				if (amount != held[uniqueID]) then
					fail(recipeID .. ": refused craft changed " .. uniqueID .. " from " .. held[uniqueID] .. " to " .. amount)
				end
			end
		end

		-- the station is required
		if (recipe.station) then
			inventory = Fresh(bot)
			GiveRequirements(inventory, recipe)

			-- earlier checks may have left their own station entities nearby, so move all of them away
			local moved = {}

			for _, entity in ipairs(ents.FindByClass("ix_station_" .. recipe.station)) do
				moved[entity] = entity:GetPos()
				entity:SetPos(entity:GetPos() + Vector(0, 0, 5000))
			end

			if (recipe:OnCanCraft(bot)) then
				fail(recipeID .. ": craftable away from its station")
			end

			for entity, position in pairs(moved) do
				entity:SetPos(position)
			end
		end
	end

	for _, entity in pairs(stations) do
		if (IsValid(entity)) then entity:Remove() end
	end

	Fresh(bot)

	return {recipes = table.Count(craft.recipes), crafted = crafted}
end)

GWH.Check("stacking: crafting results that do not fit are dropped with their quantity", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft or !plugin.craft.recipes.plastic_bd) then return {skipped = "plastic_bd missing"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = Fresh(bot)
	local dropped = {}

	ix.stack.Give(inventory, "plastic1_junk", 1)
	Fill(inventory, 0)

	-- Refuse plastic_scrap in the inventory so the result cannot go in even after the junk frees its slot.
	hook.Add("CanTransferItem", "gwh_stacking", function(item, oldInv, newInv)
		if (item.uniqueID == "plastic_scrap" and newInv == inventory) then return false end
	end)

	hook.Add("OnItemSpawned", "gwh_stacking", function(entity)
		dropped[#dropped + 1] = entity
	end)

	local bSuccess = plugin.craft.CraftRecipe(bot, "plastic_bd")

	hook.Remove("CanTransferItem", "gwh_stacking")
	hook.Remove("OnItemSpawned", "gwh_stacking")

	Expect(fail, "breakdown crafted", bSuccess, true)
	Expect(fail, "junk consumed", ix.stack.Count(inventory, "plastic1_junk"), 0)
	Expect(fail, "nothing in the inventory", ix.stack.Count(inventory, "plastic_scrap"), 0)
	Expect(fail, "one item dropped", #dropped, 1)

	if (IsValid(dropped[1])) then
		local item, quantity = ix.stack.FromEntity(dropped[1])

		Expect(fail, "dropped item", item and item.uniqueID, "plastic_scrap")
		Expect(fail, "dropped quantity", quantity, 0.1)
		dropped[1]:Remove()
	end

	Fresh(bot)
end)
