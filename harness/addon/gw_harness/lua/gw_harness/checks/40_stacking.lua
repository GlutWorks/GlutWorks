-- Stacking (the stacking plugin, ix.stack): the API, the stackable item actions (take, combine, split) through
-- the same server entry point the client's net messages reach, stock Inventory:Add, the ixStackSplit answer,
-- stack access through inventory receivers, stored quantities outside the limits, /CharGiveItem, world
-- stacks (drops with a deferred insert, damage, partial pickups) and vendor trades of stacks.
-- Every operation is followed by a balance check: the total quantity before and after must add up.
-- Crafting with stacks is in 41_crafting.lua.

local Lib = GWH.Lib
local FILLER, SCRAP, COAL, Fresh = Lib.FILLER, Lib.SCRAP, Lib.COAL, Lib.Fresh
local Fill, NewStack, Quantities, Expect = Lib.Fill, Lib.NewStack, Lib.Quantities, Lib.Expect
local Scoped, Replace, Receive, Capture, Split = Lib.Scoped, Lib.Replace, Lib.ReceiveReads, Lib.Capture, Lib.Split

local function Stack() return ix.stack end

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

-- Fills the inventory with 1x1 filler until nothing more fits.
local function FillAll(inventory)
	while (ix.stack.StockAdd(inventory, FILLER, 1)) do end
end

-- A second player with a character, for "someone else's stack".
local function OtherBot()
	if (!IsValid(GWH.stackingBot)) then
		GWH.stackingBot = player.CreateNextBot("GWH Stacking")
	end

	local bot = GWH.stackingBot

	if (!IsValid(bot) or !bot:GetCharacter()) then
		error("could not create a second bot with a character")
	end

	return bot
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

GWH.Check("stacking review: vendor trades one unit of a stackable, and whole non-stackables", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local vendorPlugin = ix.plugin.list.vendor
	if (!vendorPlugin) then return {skipped = "vendor plugin not loaded"} end

	Scoped(function(defer)
		local character = bot:GetCharacter()
		local money = character:GetMoney()
		local inventory = Fresh(bot)
		local vendor = ents.Create("ix_vendor")

		vendor:SetPos(bot:GetPos() + Vector(40, 0, 0))
		vendor:Spawn()
		vendor.items[SCRAP] = {[VENDOR_PRICE] = 10, [VENDOR_MODE] = VENDOR_SELLANDBUY, [VENDOR_STOCK] = 50,
			[VENDOR_MAXSTOCK] = 100}
		vendor.items[FILLER] = {[VENDOR_PRICE] = 8, [VENDOR_MODE] = VENDOR_SELLANDBUY}
		vendor.scale = 0.5
		vendor.money = 1000
		bot.ixVendor = vendor

		defer(function()
			bot.ixVendor = nil
			vendor:Remove()
			character:SetMoney(money)
			Fresh(bot)
			timer.Simple(0, function() vendorPlugin:SaveData() end)
		end)

		local function Trade(uniqueID, bSell)
			return Capture(bot, function()
				bot.ixVendorTry = 0
				Receive("ixVendorTrade", bot, {ReadString = {uniqueID}, ReadBool = {bSell}})
			end)
		end

		-- selling a 20 kg stack sells 1 kg of it for the price of one
		local stack = NewStack(inventory, SCRAP, 20)
		character:SetMoney(0)

		local seen = Trade(SCRAP, true)
		Expect(fail, "sell: player money", character:GetMoney(), 5)
		Expect(fail, "sell: stack left", Quantities(inventory, SCRAP), "19")
		Expect(fail, "sell: vendor money", vendor.money, 995)
		Expect(fail, "sell: vendor stock", vendor:GetStock(SCRAP), 51)
		Expect(fail, "sell: notices", seen.notices, "businessSell")
		Expect(fail, "sell: logged", seen.logs:find("vendorSell", 1, true) != nil, true)
		Expect(fail, "sell: nothing left shadowed", rawget(stack, "Remove"), nil)

		-- buying gives 1 kg merged into the existing stack
		character:SetMoney(100)
		seen = Trade(SCRAP, false)
		Expect(fail, "buy: player money", character:GetMoney(), 90)
		Expect(fail, "buy: merged", Quantities(inventory, SCRAP), "20")
		Expect(fail, "buy: vendor money", vendor.money, 1005)
		Expect(fail, "buy: vendor stock", vendor:GetStock(SCRAP), 50)
		Expect(fail, "buy: notices", seen.notices, "businessPurchase")
		Expect(fail, "buy: logged", seen.logs:find("vendorBuy", 1, true) != nil, true)
		Expect(fail, "buy: client told about the item", seen.nets:find("ixVendorAddItem", 1, true) != nil, true)

		-- buy two, split them up, sell them all back: no profit, and the pieces sell as their total
		inventory = Fresh(bot)
		character:SetMoney(100)

		for _ = 1, 2 do Trade(SCRAP, false) end

		Expect(fail, "loop: bought two units", Quantities(inventory, SCRAP), "2")
		Expect(fail, "loop: paid for two", character:GetMoney(), 80)

		stack = ix.stack.GetStacks(inventory, SCRAP)[1]
		ix.stack.Split(bot, stack, "0.3")
		ix.stack.Split(bot, stack, "0.1")
		ix.stack.Split(bot, stack, "0.1")
		Expect(fail, "loop: split up", ix.stack.Count(inventory, SCRAP), 2)
		Expect(fail, "loop: four stacks", #ix.stack.GetStacks(inventory, SCRAP), 4)

		for _ = 1, 6 do Trade(SCRAP, true) end

		Expect(fail, "loop: everything sold", ix.stack.Count(inventory, SCRAP), 0)
		Expect(fail, "loop: money after selling back", character:GetMoney(), 90)

		-- less than one unit cannot be sold, and nothing changes
		stack = NewStack(inventory, SCRAP, 0.5)
		character:SetMoney(0)
		seen = Trade(SCRAP, true)
		Expect(fail, "under a unit: told why", seen.notices:find("stackVendorTooLittle", 1, true) != nil, true)
		Expect(fail, "under a unit: stack", Quantities(inventory, SCRAP), "0.5")
		Expect(fail, "under a unit: no money", character:GetMoney(), 0)
		Expect(fail, "under a unit: nothing shadowed", rawget(stack, "Remove"), nil)
		inventory = Fresh(bot)

		-- a refused sale changes nothing and leaves no shadowed Remove behind
		stack = NewStack(inventory, SCRAP, 5)
		vendor.money = 2
		seen = Trade(SCRAP, true)
		Expect(fail, "no vendor money: notice", seen.notices, "vendorNoMoney")
		Expect(fail, "no vendor money: stack", Quantities(inventory, SCRAP), "5")
		Expect(fail, "no vendor money: nothing shadowed", rawget(stack, "Remove"), nil)
		vendor.money = 1000
		vendor.items[SCRAP][VENDOR_STOCK] = 100
		seen = Trade(SCRAP, true)
		Expect(fail, "full stock: notice", seen.notices, "vendorMaxStock")
		Expect(fail, "full stock: nothing shadowed", rawget(stack, "Remove"), nil)
		vendor.items[SCRAP][VENDOR_STOCK] = 50

		-- a stack in a bag only is not found by the vendor; nothing is sold
		inventory = Fresh(bot)
		ix.stack.StockAdd(inventory, "suitcase", 1)
		local bag = inventory:HasItem("suitcase")
		local bagInventory = bag and bag:GetInventory()

		if (bagInventory) then
			NewStack(bagInventory, SCRAP, 3)
			character:SetMoney(0)
			Trade(SCRAP, true)
			Expect(fail, "bag only: nothing sold", Quantities(bagInventory, SCRAP), "3")
			Expect(fail, "bag only: no money", character:GetMoney(), 0)
		else
			fail("the suitcase has no inventory")
		end

		-- buying with no room drops the purchase through the stack API, not the vendor's default instance
		inventory = Fresh(bot)
		FillAll(inventory)
		character:SetMoney(100)

		local spawned = {}

		Scoped(function(deferSpawn)
			Replace(deferSpawn, ix.item, "Spawn", function(uniqueID, position, callback, angles, data)
				spawned[#spawned + 1] = uniqueID .. "=" .. tostring(istable(data) and data.quantity)
			end)

			Trade(SCRAP, false)
		end)

		Expect(fail, "no room: dropped", table.concat(spawned, ","), SCRAP .. "=1")
		Expect(fail, "no room: paid", character:GetMoney(), 90)

		-- non-stackables trade one whole instance each way, as stock Helix does
		inventory = Fresh(bot)
		ix.stack.StockAdd(inventory, FILLER, 2)
		character:SetMoney(0)
		seen = Trade(FILLER, true)
		Expect(fail, "non-stackable sell: money", character:GetMoney(), 4)
		Expect(fail, "non-stackable sell: one instance left", #ix.stack.GetStacks(inventory, FILLER), 1)
		Expect(fail, "non-stackable sell: notices", seen.notices, "businessSell")

		character:SetMoney(100)
		seen = Trade(FILLER, false)
		Expect(fail, "non-stackable buy: money", character:GetMoney(), 92)
		Expect(fail, "non-stackable buy: two instances", #ix.stack.GetStacks(inventory, FILLER), 2)
		Expect(fail, "non-stackable buy: notices", seen.notices, "businessPurchase")
		Expect(fail, "non-stackable buy: client told", seen.nets:find("ixVendorAddItem", 1, true) != nil, true)
	end)
end)

GWH.Check("stacking review: split answers arrive through ixStackSplit", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	if (!net.Receivers["ixstacksplit"]) then
		return fail("no ixStackSplit receiver")
	end

	Scoped(function(defer)
		defer(function() Fresh(bot) end)

		local inventory = Fresh(bot)
		local scrap = NewStack(inventory, SCRAP, 5)
		local coal = NewStack(inventory, COAL, 5)

		-- the item menu's Split opens the prompt on the client; the server action itself does nothing
		bot.ixStrReqs = {}
		ix.item.PerformInventoryAction(bot, "split", scrap:GetID(), scrap.invID, {})
		Expect(fail, "no RequestString prompt", table.Count(bot.ixStrReqs), 0)
		Expect(fail, "menu action changes nothing", Quantities(inventory, SCRAP), "5")
		Expect(fail, "client-side prompt", isfunction(scrap.functions.split.OnClick), true)

		for _, text in ipairs({"abc", "", "nan", "inf", "1e999", "-1", "0", "0x10", "0.25", "5", "6",
			"0000000000000000000000000000000001.5"}) do
			Split(bot, scrap, text)
			Expect(fail, "split '" .. text .. "' refused", Quantities(inventory, SCRAP), "5")
		end

		-- an unknown instance, a world item, someone else's stack
		bot.ixStackSplitNext = nil
		Receive("ixStackSplit", bot, {ReadUInt = {2147483000}, ReadString = {"1"}})

		local other = OtherBot()
		local otherInventory = other:GetCharacter():GetInventory()
		local foreign = NewStack(otherInventory, SCRAP, 4)

		if (foreign) then
			Split(bot, foreign, "1")
			Expect(fail, "someone else's stack untouched", Quantities(otherInventory, SCRAP), "4")
			foreign:Remove()
		else
			fail("could not give the other bot a stack")
		end

		-- two prompts answered in the same second: each answer splits its own stack
		Split(bot, scrap, "2")
		bot.ixStackSplitNext = CurTime()
		Receive("ixStackSplit", bot, {ReadUInt = {coal:GetID()}, ReadString = {"1.5"}})
		Expect(fail, "first answer", Quantities(inventory, SCRAP), "3,2")
		Expect(fail, "second answer", Quantities(inventory, COAL), "3.5,1.5")

		-- the same tick is rate limited
		Split(bot, scrap, "1")
		Receive("ixStackSplit", bot, {ReadUInt = {scrap:GetID()}, ReadString = {"1"}})
		Expect(fail, "rate limited", Quantities(inventory, SCRAP), "2,2,1")
	end)
end)

GWH.Check("stacking review: stack access follows the inventory's receivers", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		defer(function() Fresh(bot) end)

		local inventory = Fresh(bot)
		local own = NewStack(inventory, SCRAP, 3)

		Expect(fail, "own inventory", ix.stack.CanAccess(bot, own), true)

		-- a bag the player carries, then drops
		ix.stack.StockAdd(inventory, "suitcase", 1)

		local bag = inventory:HasItem("suitcase")
		local bagInventory = bag and bag:GetInventory()

		if (!bagInventory) then
			return fail("the suitcase has no inventory")
		end

		local inBag = NewStack(bagInventory, SCRAP, 5)

		Expect(fail, "carried bag", ix.stack.CanAccess(bot, inBag), true)
		ix.stack.Split(bot, inBag, "1")
		Expect(fail, "split in a carried bag", Quantities(bagInventory, SCRAP), "4,1")

		bag:Transfer(nil, nil, nil, bot)
		defer(function()
			local entity = bag:GetEntity()

			for _, item in pairs(bagInventory:GetItems()) do item:Remove() end
			if (IsValid(entity)) then entity:Remove() end
		end)

		Expect(fail, "bag is on the ground", bag.invID, 0)
		Expect(fail, "dropped bag", ix.stack.CanAccess(bot, inBag), false)
		ix.stack.Split(bot, inBag, "1")
		Expect(fail, "split in a dropped bag refused", Quantities(bagInventory, SCRAP), "4,1")
		Expect(fail, "combine out of a dropped bag refused", (ix.stack.Combine(bot, own, inBag:GetID())), false)

		-- another character's inventory
		local other = OtherBot()
		local foreign = NewStack(other:GetCharacter():GetInventory(), SCRAP, 2)

		if (foreign) then
			Expect(fail, "another character's inventory", ix.stack.CanAccess(bot, foreign), false)
			foreign:Remove()
		end

		-- a container: only while it is open
		local prop = ents.Create("prop_physics")
		prop:SetModel("models/props_junk/wood_crate001a.mdl")
		prop:SetPos(bot:GetPos() + Vector(50, 0, 10))
		prop:Spawn()

		local storage = ix.inventory.Create(4, 4, 2100000000 + math.random(1, 100000))
		local inBox = NewStack(storage, SCRAP, 6)

		defer(function()
			for _, item in pairs(storage:GetItems()) do item:Remove() end
			ix.item.inventories[storage:GetID()] = nil
			prop:Remove()
		end)

		Expect(fail, "closed container", ix.stack.CanAccess(bot, inBox), false)
		ix.storage.Open(bot, storage, {entity = prop, name = "box", searchTime = 0})
		Expect(fail, "open container", ix.stack.CanAccess(bot, inBox), true)
		ix.storage.RemoveReceiver(bot, storage)
		Expect(fail, "closed again", ix.stack.CanAccess(bot, inBox), false)
	end)
end)

GWH.Check("stacking review: stored quantities above the limit or below zero", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		defer(function() Fresh(bot) end)

		local S = ix.stack
		local inventory = Fresh(bot)
		local over = NewStack(inventory, SCRAP, 50)

		Expect(fail, "counted in full", S.Count(inventory, SCRAP), 50)
		Expect(fail, "Give does not add to it", (S.Give(inventory, SCRAP, 1)), true)
		Expect(fail, "Give made a new stack", Quantities(inventory, SCRAP), "50,1")

		local small = S.GetStacks(inventory, SCRAP)[2]

		Expect(fail, "combine into it refused", (S.Combine(bot, over, small:GetID())), false)
		Expect(fail, "split above the limit refused", (S.Split(bot, over, "30")), false)
		Expect(fail, "nothing changed", Quantities(inventory, SCRAP), "50,1")
		Expect(fail, "split at the limit", (S.Split(bot, over, "20")), true)
		Expect(fail, "split made a full stack", Quantities(inventory, SCRAP), "30,20,1")
		Expect(fail, "take across it", (S.Take(inventory, SCRAP, 45)), true)
		Expect(fail, "after take", S.Count(inventory, SCRAP), 6)

		-- a negative stored quantity counts as empty instead of subtracting
		inventory = Fresh(bot)
		NewStack(inventory, SCRAP, 3)

		local negative = NewStack(inventory, SCRAP, -5)

		Expect(fail, "negative reads as zero", S.GetQuantity(negative), 0)
		Expect(fail, "count ignores it", S.Count(inventory, SCRAP), 3)
		Expect(fail, "take still works", (S.Take(inventory, SCRAP, 3)), true)
		Expect(fail, "all taken", S.Count(inventory, SCRAP), 0)
	end)
end)

GWH.Check("stacking review: /CharGiveItem of a stackable goes through the wrapped Inventory:Add", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local command = ix.command.list["chargiveitem"]
	if (!command) then return fail("no CharGiveItem command") end

	Scoped(function(defer)
		defer(function() Fresh(bot) end)

		local character = bot:GetCharacter()
		local inventory = Fresh(bot)

		NewStack(inventory, SCRAP, 15)

		local seen = Capture(bot, function()
			command:OnRun(bot, character, SCRAP, 25)
		end)

		Expect(fail, "25 kg merged and stacked", Quantities(inventory, SCRAP), "20,20")
		Expect(fail, "notice", seen.notices, "itemCreated")

		command:OnRun(bot, character, ix.item.list[SCRAP].name, 2.5)
		Expect(fail, "by name, 2.5 kg", Quantities(inventory, SCRAP), "20,20,2.5")

		command:OnRun(bot, character, FILLER, 3)
		Expect(fail, "non-stackable gives instances", #ix.stack.GetStacks(inventory, FILLER), 3)

		FillAll(inventory)
		Expect(fail, "no room", command:OnRun(bot, character, SCRAP, 25), "@noFit")
		Expect(fail, "nothing added without room", Quantities(inventory, SCRAP), "20,20,2.5")
	end)
end)

GWH.Check("stacking review: a drop at the player is placed before the insert completes", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		local playerMeta = FindMetaTable("Player")
		local dropPos = playerMeta.GetItemDropPos
		local stockInstance = ix.item.Instance
		local queue, calls, spawned = {}, 0, {}

		Scoped(function(deferInsert)
			Replace(deferInsert, ix.item, "Instance", function(...) queue[#queue + 1] = {...} end)
			Replace(deferInsert, playerMeta, "GetItemDropPos", function(...)
				calls = calls + 1
				return dropPos(...)
			end)

			ix.stack.Spawn(SCRAP, bot, 1.5, angle_zero, function(item, entity)
				spawned[#spawned + 1] = {item = item, entity = entity}
			end)
		end)

		Expect(fail, "insert deferred", #queue, 1)
		Expect(fail, "position resolved at the call", calls, 1)

		-- the player is unusable by the time the insert completes
		Scoped(function(deferFlush)
			Replace(deferFlush, playerMeta, "GetItemDropPos", function() error("the player is gone") end)

			for _, args in ipairs(queue) do
				local ok, fault = pcall(stockInstance, unpack(args, 1, 8))
				if (!ok) then fail("insert callback threw: " .. tostring(fault)) end
			end
		end)

		local result = spawned[1]

		Expect(fail, "entity spawned", result != nil and IsValid(result.entity), true)

		if (result and IsValid(result.entity)) then
			defer(function() result.entity:Remove() end)
			Expect(fail, "quantity", ix.stack.GetQuantity(result.item), 1.5)
			Expect(fail, "owner marked", result.entity.ixCharID, bot:GetCharacter():GetID())
			Expect(fail, "not at the map origin", result.entity:GetPos() != vector_origin, true)
		end
	end)
end)

GWH.Check("stacking review: a world stack survives being hit", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local stack, junk

	ix.stack.Spawn(SCRAP, bot:GetPos() + Vector(0, 0, 3000), 20, angle_zero, function(item, entity)
		stack = {item = item, entity = entity}
	end)
	ix.item.Spawn(FILLER, bot:GetPos() + Vector(40, 0, 3000), function(item, entity)
		junk = {item = item, entity = entity}
	end)

	if (!stack or !IsValid(stack.entity) or !junk or !IsValid(junk.entity)) then
		return fail("could not spawn the world items")
	end

	for _, target in ipairs({stack, junk}) do
		local damage = DamageInfo()
		damage:SetDamage(5)
		damage:SetAttacker(bot)
		damage:SetInflictor(bot)
		damage:SetDamageType(DMG_BULLET)
		target.entity:TakeDamageInfo(damage)
	end

	Expect(fail, "stack entity kept", !stack.entity:IsMarkedForDeletion(), true)
	Expect(fail, "stack instance kept", ix.item.instances[stack.item:GetID()] == stack.item, true)
	Expect(fail, "stack quantity kept", ix.stack.GetQuantity(stack.item), 20)
	Expect(fail, "a non-stackable still breaks as in stock Helix", junk.entity:IsMarkedForDeletion(), true)

	stack.entity:Remove()

	if (IsValid(junk.entity)) then junk.entity:Remove() end
end)

GWH.Check("stacking review: a pickup that only partly fits says what was taken", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = Fresh(bot)
	NewStack(inventory, SCRAP, 19)
	FillAll(inventory)

	local world

	ix.stack.Spawn(SCRAP, bot:GetPos() + Vector(0, 0, 3000), 3, angle_zero, function(item, entity)
		world = {item = item, entity = entity}
	end)

	if (!world or !IsValid(world.entity)) then
		return fail("could not spawn the world stack")
	end

	local function Take()
		local result

		world.item.player, world.item.entity = bot, world.entity

		local seen = Capture(bot, function()
			result = world.item.functions.take.OnRun(world.item)
		end)

		world.item.player, world.item.entity = nil, nil

		return result, seen.notices
	end

	local result, notices = Take()

	Expect(fail, "partial pickup keeps the world entity", result, false)
	Expect(fail, "partial pickup notice", notices, "stackPartialPickup")
	Expect(fail, "inventory stack filled", Quantities(inventory, SCRAP), "20")
	Expect(fail, "rest stays in the world", ix.stack.GetQuantity(world.item), 2)

	result, notices = Take()

	Expect(fail, "nothing fits: world entity kept", result, false)
	Expect(fail, "nothing fits: the plain no-room notice", notices, "noFit")
	Expect(fail, "nothing fits: world quantity unchanged", ix.stack.GetQuantity(world.item), 2)

	world.entity:Remove()
	Fresh(bot)
end)

GWH.Check("stacking review: cleanup", function(fail)
	if (IsValid(GWH.stackingBot)) then
		GWH.stackingBot:Kick("stacking review checks finished")
		GWH.stackingBot = nil
	end
end)
