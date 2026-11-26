-- Checks for the stacking and crafting review fixes: vendor trades of stacks, crafting and splitting while
-- incapacitated, recipe results that give nothing, the ixStackSplit answer, stack access through inventory
-- receivers, stored quantities outside the limits, /CharGiveItem, and drop positions with a deferred insert.

local SCRAP = "metal_scrap" -- resource: kg, 0.1 steps, limit 20
local COAL = "coal" -- resource: kg, 0.1 steps
local FILLER = "iron3_junk" -- 1x1, not stackable

local function Inventory(bot)
	return bot:GetCharacter():GetInventory()
end

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

-- One new stack with an exact stored quantity, bypassing merging and the limit.
local function NewStack(inventory, uniqueID, quantity)
	local before = {}

	for _, item in ipairs(ix.stack.GetStacks(inventory, uniqueID)) do
		before[item:GetID()] = true
	end

	ix.stack.StockAdd(inventory, uniqueID, 1, ix.stack.IsStackable(uniqueID) and {quantity = quantity} or nil)

	for _, item in ipairs(ix.stack.GetStacks(inventory, uniqueID)) do
		if (!before[item:GetID()]) then
			return item
		end
	end
end

local function Quantities(inventory, uniqueID)
	local list = {}

	for _, item in ipairs(ix.stack.GetStacks(inventory, uniqueID)) do
		list[#list + 1] = item:GetData("quantity", 1)
	end

	table.sort(list, function(a, b) return a > b end)

	return table.concat(list, ",")
end

local function Fill(inventory)
	while (ix.stack.StockAdd(inventory, FILLER, 1)) do end
end

local function Expect(fail, label, actual, expected)
	if (actual != expected) then
		fail(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

--- Runs fn(defer); every function passed to defer runs afterwards in reverse order, even if fn threw.
local function Scoped(fn)
	local cleanups = {}
	local ok, result = xpcall(fn, debug.traceback, function(cleanup)
		cleanups[#cleanups + 1] = cleanup
	end)

	for i = #cleanups, 1, -1 do
		local bCleaned, fault = xpcall(cleanups[i], debug.traceback)

		if (!bCleaned and ok) then
			ok, result = false, fault
		end
	end

	if (!ok) then error(result, 0) end

	return result
end

local function Replace(defer, target, key, value)
	local original = target[key]
	target[key] = value
	defer(function() target[key] = original end)
end

--- Calls a net receiver as though client had sent it. reads maps a net.Read* name to the values it returns in order.
local function Receive(name, client, reads)
	local receiver = net.Receivers[name:lower()]

	if (!receiver) then
		error("no net receiver " .. name, 2)
	end

	Scoped(function(defer)
		for readName, values in pairs(reads) do
			local index = 0

			Replace(defer, net, readName, function()
				index = index + 1
				return values[index]
			end)
		end

		receiver(0, client)
	end)
end

-- Records the localized notices, plain notices, net messages and log entries sent while fn runs.
local function Capture(client, fn)
	local seen = {notices = {}, texts = {}, nets = {}, logs = {}}

	Scoped(function(defer)
		local notifyLocalized, notify = ix.util.NotifyLocalized, ix.util.Notify
		local start, logAdd = net.Start, ix.log.Add

		Replace(defer, ix.util, "NotifyLocalized", function(message, recipient, ...)
			if (recipient == client) then seen.notices[#seen.notices + 1] = message end
			return notifyLocalized(message, recipient, ...)
		end)
		Replace(defer, ix.util, "Notify", function(message, recipient)
			if (recipient == client) then seen.texts[#seen.texts + 1] = message end
			return notify(message, recipient)
		end)
		Replace(defer, net, "Start", function(name, ...)
			seen.nets[#seen.nets + 1] = name
			return start(name, ...)
		end)
		Replace(defer, ix.log, "Add", function(logClient, logType, ...)
			seen.logs[#seen.logs + 1] = logType
			return logAdd(logClient, logType, ...)
		end)

		fn()
	end)

	seen.notices = table.concat(seen.notices, ",")
	seen.texts = table.concat(seen.texts, " | ")
	seen.nets = table.concat(seen.nets, ",")
	seen.logs = table.concat(seen.logs, ",")

	return seen
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

local function Split(bot, item, text)
	bot.ixStackSplitNext = nil
	Receive("ixStackSplit", bot, {ReadUInt = {item:GetID()}, ReadString = {text}})
end

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
		Fill(inventory)
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

GWH.Check("stacking review: no crafting or splitting while dead, tied or ragdolled", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft) then return {skipped = "ixcraft not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		local recipeID = "gwh_review_state"

		plugin.craft.recipes[recipeID] = setmetatable({uniqueID = recipeID, name = "GWH State",
			requirements = {[SCRAP] = 1}, results = {[COAL] = 1}}, plugin.meta.recipe)
		defer(function() plugin.craft.recipes[recipeID] = nil end)
		defer(function() Fresh(bot) end)

		local ragdoll

		local states = {
			{"dead", function() bot:KillSilent() end, function() bot:Spawn() end},
			{"tied", function() bot:SetNetVar("restricted", true) end, function() bot:SetNetVar("restricted", nil) end},
			{"ragdolled", function()
				ragdoll = ents.Create("prop_physics")
				ragdoll:SetModel("models/props_junk/wood_crate001a.mdl")
				ragdoll:SetPos(bot:GetPos() + Vector(0, 0, 4000))
				ragdoll:Spawn()
				bot.ixRagdoll = ragdoll
			end, function()
				bot.ixRagdoll = nil
				ragdoll:Remove()
			end}
		}

		for _, state in ipairs(states) do
			local label, enter, leave = state[1], state[2], state[3]
			local inventory = Fresh(bot)
			local stack = NewStack(inventory, SCRAP, 5)

			enter()

			local ok, fault = pcall(function()
				Expect(fail, label .. ": CraftRecipe refused", plugin.craft.CraftRecipe(bot, recipeID), false)
				Receive("ixCraftRecipe", bot, {ReadString = {recipeID}})
				Expect(fail, label .. ": ingredients untouched", Quantities(inventory, SCRAP), "5")
				Expect(fail, label .. ": nothing crafted", Quantities(inventory, COAL), "")
				Expect(fail, label .. ": CanAccess refused", ix.stack.CanAccess(bot, stack), false)
				Expect(fail, label .. ": Split refused", (ix.stack.Split(bot, stack, "1")), false)
				Split(bot, stack, "2")
				Expect(fail, label .. ": split answer refused", Quantities(inventory, SCRAP), "5")
			end)

			leave()

			if (!ok) then fail(label .. ": " .. tostring(fault)) end
		end

		-- and both work again once the player is back on their feet
		local inventory = Fresh(bot)
		local stack = NewStack(inventory, SCRAP, 5)

		Expect(fail, "alive: CraftRecipe works", plugin.craft.CraftRecipe(bot, recipeID), true)
		Split(bot, stack, "2")
		Expect(fail, "alive: crafted and split", Quantities(inventory, SCRAP) .. "/" .. Quantities(inventory, COAL), "2,2/1")
	end)
end)

GWH.Check("stacking review: a recipe result that gives nothing leaves the ingredients alone", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft) then return {skipped = "ixcraft not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		local recipes = {
			gwh_review_unregistered = {[COAL] = 1, gwh_no_such_item = 1},
			gwh_review_substep = {[COAL] = 0.04},
			gwh_review_zero = {[COAL] = {0}}
		}

		for recipeID, results in pairs(recipes) do
			plugin.craft.recipes[recipeID] = setmetatable({uniqueID = recipeID, name = recipeID,
				requirements = {[SCRAP] = 2}, results = results}, plugin.meta.recipe)
		end

		defer(function()
			for recipeID in pairs(recipes) do plugin.craft.recipes[recipeID] = nil end
			Fresh(bot)
		end)

		for recipeID in SortedPairs(recipes) do
			local inventory = Fresh(bot)
			local result

			NewStack(inventory, SCRAP, 5)

			local seen = Capture(bot, function()
				result = plugin.craft.CraftRecipe(bot, recipeID)
			end)

			Expect(fail, recipeID .. ": refused", result, false)
			Expect(fail, recipeID .. ": ingredients untouched", Quantities(inventory, SCRAP), "5")
			Expect(fail, recipeID .. ": nothing given", Quantities(inventory, COAL), "")

			if (!seen.texts:find("broken", 1, true)) then
				fail(recipeID .. ": no notice saying the recipe is broken, got '" .. seen.texts .. "'")
			end
		end
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

		Fill(inventory)
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

GWH.Check("stacking review: cleanup", function(fail)
	if (IsValid(GWH.stackingBot)) then
		GWH.stackingBot:Kick("stacking review checks finished")
		GWH.stackingBot = nil
	end
end)
