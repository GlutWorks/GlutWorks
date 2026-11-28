-- Inventory panel (inventorypanel): the bag, storages, corpses and searches as an open case in the world. Server
-- side: the plugin, its net messages, command and phrases; the tap rule (GetTapAction); moves (ixInventoryPanelMove,
-- ix.stack.MoveTo) between the bot and an open crate, and out of and into a carried bag, merge stacks, keep every item
-- in exactly one cell of one grid, never make or lose any, keep a part's owner and never merge into another
-- character's stack, are logged and rate limited, and are refused before the search ends, out of reach, once closed,
-- for someone else's inventory or item and for a player who cannot act; a move to a cell (placing a carried thing)
-- lands exactly there, within one grid (persisted as Helix persists x and y) or across, and a cell out of range,
-- taken, too small, the same one, someone else's or out of reach is refused and changes nothing; putting a thing onto
-- another (ixInventoryPanelCombine) runs the target's combine as the old drag did (stacks merge, a bag takes it)
-- behind the same gates; the server lets go of a storage on ixStorageClose (the case sends it whenever it closes on
-- its own: looked away, walked off, closed, Tab, another case; not when the server itself closed it or opened
-- another), on death, a knockout, being tied and opening another storage, and a refused open leaves the first one
-- usable; the actions an item's options list are the old menu's (OnCanRun) and still go through
-- PerformInventoryAction's gates, in a carried bag too. The case itself is client-only and is judged in a play
-- session. Split's offered amounts and MoveTo's cell are in 40_stacking.lua. Helix's own ixInventoryMove and storage
-- money handlers are not gated here (draft PR #17).

local Lib = GWH.Lib
local Scoped, ReceiveReads, Expect, Plugin = Lib.Scoped, Lib.ReceiveReads, Lib.Expect, Lib.Plugin
local ResetBotFully, OtherBot, Fresh, Fill, NewStack = Lib.ResetBotFully, Lib.OtherBot, Lib.Fresh, Lib.Fill, Lib.NewStack
local Quantities, GiveItem = Lib.Quantities, Lib.GiveItem
local FILLER, SCRAP, COAL = Lib.FILLER, Lib.SCRAP, Lib.COAL

-- Far enough from anything to be out of every storage's reach.
local FAR = Vector(3000, 0, 0)

local nextInventoryID = 2100300000

-- Ties the bot with nothing in its hands: Helix gives back what it held on untying, and a weapon class from an
-- earlier check that no longer exists would make that throw.
local function Tie(bot)
	bot:StripWeapons()
	bot:SetRestricted(true)
end

local function PanelPlugin()
	return ix.plugin.list.inventorypanel
end

-- A crate frozen beside the bot and a fresh 4x4 inventory for it; both go, with anything in them, when the check
-- ends.
local function Crate(defer, bot)
	local prop = ents.Create("prop_physics")
	prop:SetModel("models/props_junk/wood_crate001a.mdl")
	prop:SetPos(bot:GetPos() + Vector(50, 0, 10))
	prop:Spawn()

	local physics = prop:GetPhysicsObject()

	if (IsValid(physics)) then
		physics:EnableMotion(false)
	end

	nextInventoryID = nextInventoryID + 1

	local inventory = ix.inventory.Create(4, 4, nextInventoryID)

	defer(function()
		if (bot.ixOpenStorage == inventory) then
			ix.storage.RemoveReceiver(bot, inventory)
		end

		inventory.storageInfo = nil

		for _, item in pairs(inventory:GetItems()) do
			item:Remove()
		end

		ix.item.inventories[inventory:GetID()] = nil

		if (IsValid(prop)) then
			prop:Remove()
		end
	end)

	return prop, inventory
end

-- What the client sends for a move: the item, where to, how much of a stack (nil for all of it) and the cell it was
-- put at (nil for any free one).
local function Move(bot, item, inventory, amount, x, y)
	bot.ixInventoryPanelNextMove = nil

	local reads = {ReadUInt = {item:GetID(), inventory:GetID()}, ReadBool = {amount != nil, x != nil}}

	if (amount != nil) then
		reads.ReadDouble = {amount}
	end

	if (x != nil) then
		reads.ReadUInt[3], reads.ReadUInt[4] = x, y
	end

	ReceiveReads("ixInventoryPanelMove", bot, reads)
end

-- What the client sends when a carried thing is put down onto another.
local function Combine(bot, item, target)
	bot.ixInventoryPanelNextMove = nil

	ReceiveReads("ixInventoryPanelCombine", bot, {ReadUInt = {item:GetID(), target:GetID()}})
end

-- Every item in the inventory and its bags as "id:uniqueID:inventory:data", sorted, to compare before and after.
local function Contents(inventory)
	local list = {}

	for _, item in pairs(inventory:GetItems()) do
		list[#list + 1] = item:GetID() .. ":" .. item.uniqueID .. ":" .. tostring(item.invID) .. ":" ..
			util.TableToJSON(item.data or {})
	end

	table.sort(list)

	return table.concat(list, ",")
end

local function Positions(inventory)
	local list = {}

	for _, item in pairs(inventory:GetItems(true)) do
		list[#list + 1] = item:GetID() .. "@" .. tostring(item.gridX) .. "," .. tostring(item.gridY)
	end

	table.sort(list)

	return table.concat(list, ";")
end

-- Fails unless every cell of the grid points at the item whose rectangle covers it, and every item covers its own.
local function CheckGrid(fail, inventory, label)
	for x = 1, inventory.w do
		for y = 1, inventory.h do
			local item = inventory.slots[x] and inventory.slots[x][y]

			if (istable(item) and (x < item.gridX or x >= item.gridX + item.width or y < item.gridY or
				y >= item.gridY + item.height)) then
				fail(label .. ": cell " .. x .. "," .. y .. " points at an item that is elsewhere")
			end
		end
	end

	for _, item in pairs(inventory:GetItems(true)) do
		for x = item.gridX, item.gridX + item.width - 1 do
			for y = item.gridY, item.gridY + item.height - 1 do
				if ((inventory.slots[x] or {})[y] != item) then
					fail(label .. ": " .. item.uniqueID .. " is missing from cell " .. x .. "," .. y)
				end
			end
		end
	end
end

-- Fails unless `item` is in exactly one of `inventories`: the one its invID names, every cell of its rectangle from
-- gridX, gridY pointing at it, and no other cell of any of them.
local function CheckPlaced(fail, label, item, inventories)
	local found = {}

	for _, inventory in ipairs(inventories) do
		for x = 1, inventory.w do
			for y = 1, inventory.h do
				local slot = inventory.slots[x] and inventory.slots[x][y]

				if (istable(slot) and slot.id == item.id) then
					found[inventory] = (found[inventory] or 0) + 1
				end
			end
		end
	end

	local holders = table.Count(found)
	local holder = next(found)

	if (holders != 1) then
		return fail(label .. ": in " .. holders .. " grids")
	end

	if (holder:GetID() != item.invID) then
		fail(label .. ": in the grid of inventory " .. holder:GetID() .. " but says " .. tostring(item.invID))
	end

	if (found[holder] != item.width * item.height or !istable((holder.slots[item.gridX] or {})[item.gridY])) then
		fail(label .. ": covers " .. found[holder] .. " cells, not its own " .. item.width * item.height)
	end
end

-- Fails unless every grid of `inventories` is sound (CheckGrid) and every item in them is in exactly one grid of them
-- (CheckPlaced): after any move, nothing is in two places, nowhere, or half in a cell.
local function CheckAll(fail, label, inventories)
	for _, inventory in ipairs(inventories) do
		CheckGrid(fail, inventory, label)

		for _, item in pairs(inventory:GetItems(true)) do
			CheckPlaced(fail, label .. ": " .. item.uniqueID .. " #" .. item:GetID(), item, inventories)
		end
	end
end

-- The inventory_id, x and y the database holds for an item, as "id@x,y".
local function Row(item)
	local row = sql.QueryRow("SELECT inventory_id, x, y FROM ix_items WHERE item_id = " .. tonumber(item:GetID()))

	return row and (row.inventory_id .. "@" .. row.x .. "," .. row.y) or "none"
end

GWH.Check("inventorypanel: plugin, net messages and phrases exist", function(fail)
	local plugin = Plugin("inventorypanel", fail)

	if (!plugin or !Plugin("worldui", fail) or !Plugin("stacking", fail)) then return end

	for _, name in ipairs({"ixInventoryPanelMove", "ixInventoryPanelCombine", "ixInventoryPanelResult"}) do
		if ((util.NetworkStringToID(name) or 0) == 0) then fail("net message " .. name .. " is not registered") end
	end

	for _, name in ipairs({"ixinventorypanelmove", "ixinventorypanelcombine"}) do
		if (!net.Receivers[name]) then fail("no receiver " .. name) end
	end

	if (net.Receivers.ixinventorypaneltidy or (util.NetworkStringToID("ixInventoryPanelTidy") or 0) != 0) then
		fail("Rearrange (ixInventoryPanelTidy) is still there")
	end

	if (!ix.command.list.menu) then fail("no /Menu command") end

	local english, spanish = ix.lang.stored.english, ix.lang.stored.spanish
	local count = 0

	for key in pairs(english) do
		if (key:find("^invPanel")) then
			count = count + 1

			if (!spanish or !spanish[key]) then fail("no Spanish phrase " .. key) end
		end
	end

	if (count < 25) then fail("only " .. count .. " English invPanel phrases") end

	for _, entry in ipairs(plugin.fullness) do
		if (!english[entry[2]]) then fail("no phrase for fullness " .. entry[2]) end
	end

	if (!ix.stack.MoveTo or !ix.stack.GetSplitAmounts or !ix.stack.FitsAt) then
		fail("ix.stack.MoveTo, GetSplitAmounts or FitsAt is missing")
	end
end)

GWH.Check("inventorypanel: moves between the bot and an open crate merge stacks, refuse a full side, never make or lose any", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBotFully(bot)
		defer(function() Fresh(bot) end)

		local prop, crate = Crate(defer, bot)
		local own = Fresh(bot)

		NewStack(own, SCRAP, 3)

		local theirs = NewStack(crate, SCRAP, 5)

		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})

		local function Total()
			return ix.stack.Count(own, SCRAP) + ix.stack.Count(crate, SCRAP)
		end

		-- the crate's whole stack into the bot's: merged into the one stack there
		Move(bot, theirs, own)
		Expect(fail, "taken: the bot's", Quantities(own, SCRAP), "8")
		Expect(fail, "taken: the crate's", Quantities(crate, SCRAP), "")
		CheckAll(fail, "taken", {own, crate})

		-- part of it back: a new stack in the crate
		local mine = ix.stack.GetStacks(own, SCRAP)[1]

		Move(bot, mine, crate, 2.5)
		Expect(fail, "part left: the bot's", Quantities(own, SCRAP), "5.5")
		Expect(fail, "part left: the crate's", Quantities(crate, SCRAP), "2.5")
		CheckAll(fail, "part left", {own, crate})

		-- what the client cannot ask for
		for _, amount in ipairs({0, -1, 0 / 0, math.huge, 0.05, 5.6, 100}) do
			Move(bot, mine, crate, amount)
			Expect(fail, "amount " .. tostring(amount) .. " refused: the bot's", Quantities(own, SCRAP), "5.5")
			Expect(fail, "amount " .. tostring(amount) .. " refused: the crate's", Quantities(crate, SCRAP), "2.5")
			CheckAll(fail, "amount " .. tostring(amount) .. " refused", {own, crate})
		end

		-- the rest, all of it: tops up the crate's stack, which is not full, so it merges
		Move(bot, mine, crate)
		Expect(fail, "all of it: the bot's", Quantities(own, SCRAP), "")
		Expect(fail, "all of it: the crate's", Quantities(crate, SCRAP), "8")
		Expect(fail, "total", Total(), 8)
		CheckAll(fail, "all of it", {own, crate})

		-- into a nearly full stack: the stack itself moves, then fills that one
		for _, stack in ipairs(ix.stack.GetStacks(crate, SCRAP)) do stack:Remove() end

		NewStack(crate, SCRAP, 19.5)
		NewStack(own, SCRAP, 4)

		local total = Total()

		Move(bot, ix.stack.GetStacks(own, SCRAP)[1], crate)
		Expect(fail, "filling: the bot's", Quantities(own, SCRAP), "")
		Expect(fail, "filling: the crate's", Quantities(crate, SCRAP), "20,3.5")
		Expect(fail, "filling: total", Total(), total)
		CheckAll(fail, "filling", {own, crate})

		-- part of a stack where a partial stack there takes a little: that one is filled and a new stack holds the rest
		NewStack(own, SCRAP, 6)

		for _, stack in ipairs(ix.stack.GetStacks(crate, SCRAP)) do
			stack:SetData("quantity", ix.stack.GetQuantity(stack) == 20 and 19 or 20)
		end

		total = Total()

		Move(bot, ix.stack.GetStacks(own, SCRAP)[1], crate, 5)
		Expect(fail, "part, filling: the bot's", Quantities(own, SCRAP), "1")
		Expect(fail, "part, filling: the crate's", Quantities(crate, SCRAP), "20,20,4")
		Expect(fail, "part, filling: total", Total(), total)
		CheckAll(fail, "part, filling", {own, crate})

		-- a plain item, there and back
		local filler = GiveItem(own, FILLER)

		Move(bot, filler, crate)
		Expect(fail, "a filler put in", filler.invID, crate:GetID())
		Move(bot, filler, own)
		Expect(fail, "a filler taken back", filler.invID, own:GetID())
		Move(bot, filler, crate, 1.5)
		Expect(fail, "part of a filler", filler.invID, own:GetID())
		CheckAll(fail, "a filler there and back", {own, crate})

		-- no room on the other side, and no partial stack there: refused, nothing changes
		for _, item in pairs(crate:GetItems()) do item:Remove() end

		Fill(crate, 0)
		total = Total()

		local quantities, crateQuantities = Quantities(own, SCRAP), Quantities(crate, SCRAP)
		local fillers = #crate:GetItemsByUniqueID(FILLER)

		Move(bot, ix.stack.GetStacks(own, SCRAP)[1], crate)
		Move(bot, ix.stack.GetStacks(own, SCRAP)[1], crate, 1)
		Move(bot, filler, crate)
		Expect(fail, "no room: the bot's", Quantities(own, SCRAP), quantities)
		Expect(fail, "no room: the crate's", Quantities(crate, SCRAP), crateQuantities)
		Expect(fail, "no room: total", Total(), total)
		Expect(fail, "no room: the filler", filler.invID, own:GetID())
		Expect(fail, "no room: the crate's fillers", #crate:GetItemsByUniqueID(FILLER), fillers)
		CheckAll(fail, "no room", {own, crate})
	end)
end)

GWH.Check("inventorypanel: a storage can't be used from a panel before its search ends, out of reach or closed", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBotFully(bot)
		defer(function() ResetBotFully(bot) Fresh(bot) end)

		local prop, crate = Crate(defer, bot)
		local own = Fresh(bot)
		local filler = GiveItem(own, FILLER)

		-- mid-search: the bot is a receiver already, but nothing moves
		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 5})
		defer(function() timer.Remove("ixStare" .. bot:SteamID64()) end)

		Expect(fail, "a receiver mid-search", ix.storage.InUseBy(crate, bot), true)
		Move(bot, filler, crate)
		Expect(fail, "put in mid-search", filler.invID, own:GetID())

		-- nor does putting a thing of the crate's onto one of the bot's (or the bot's onto the crate's)
		local mine, crates = NewStack(own, SCRAP, 2), NewStack(crate, SCRAP, 3)

		Combine(bot, crates, mine)
		Combine(bot, mine, crates)
		Expect(fail, "combined mid-search", Quantities(own, SCRAP) .. "/" .. Quantities(crate, SCRAP), "2/3")
		CheckAll(fail, "combined mid-search", {own, crate})
		mine:Remove()
		crates:Remove()
		CheckAll(fail, "put in mid-search", {own, crate})

		timer.Remove("ixStare" .. bot:SteamID64())
		ix.storage.RemoveReceiver(bot, crate)

		-- searched: it moves
		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		Move(bot, filler, crate)
		Expect(fail, "put in once searched", filler.invID, crate:GetID())
		CheckAll(fail, "put in once searched", {own, crate})

		-- out of reach: nothing moves either way
		prop:SetPos(prop:GetPos() + FAR)
		Move(bot, filler, own)
		Expect(fail, "taken from out of reach", filler.invID, crate:GetID())
		CheckAll(fail, "taken from out of reach", {own, crate})
		prop:SetPos(prop:GetPos() - FAR)

		-- tied, then dead
		Tie(bot)
		Move(bot, filler, own)
		Expect(fail, "taken while tied", filler.invID, crate:GetID())
		CheckAll(fail, "taken while tied", {own, crate})
		ResetBotFully(bot)

		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		bot:Kill()
		Move(bot, filler, own)
		Expect(fail, "taken while dead", filler.invID, crate:GetID())
		CheckAll(fail, "taken while dead", {own, crate})
		ResetBotFully(bot)

		-- respawning put the bot on a spawn point
		prop:SetPos(bot:GetPos() + Vector(50, 0, 10))

		-- closed: nothing moves
		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		Move(bot, filler, own)
		Expect(fail, "taken back while open", filler.invID, own:GetID())
		CheckAll(fail, "taken back while open", {own, crate})
		ReceiveReads("ixStorageClose", bot, {})
		Move(bot, filler, crate)
		Expect(fail, "put in once closed", filler.invID, own:GetID())
		CheckAll(fail, "put in once closed", {own, crate})

		-- a storage never opened, and another player's inventory
		local _, other = Crate(defer, bot)

		Move(bot, filler, other)
		Expect(fail, "put in a crate never opened", filler.invID, own:GetID())

		local target = OtherBot()
		local theirs = target:GetCharacter():GetInventory()

		Move(bot, filler, theirs)
		Expect(fail, "put in another player's inventory", filler.invID, own:GetID())
		CheckAll(fail, "put in a crate never opened or another player's inventory", {own, other, theirs})

		-- a carried bag is the bot's own
		ix.stack.StockAdd(own, "suitcase", 1)

		local bag = own:HasItem("suitcase")
		local bagInventory = bag and bag:GetInventory()

		if (!bagInventory) then return fail("the suitcase has no inventory") end

		defer(function() for _, v in pairs(bagInventory:GetItems()) do v:Remove() end end)

		Move(bot, filler, bagInventory)
		Expect(fail, "into the carried bag", filler.invID, bagInventory:GetID())
		Move(bot, filler, own)
		Expect(fail, "out of the carried bag", filler.invID, own:GetID())
		CheckAll(fail, "into and out of the carried bag", {own, bagInventory})

		-- a stack out of the carried bag into the inventory around it, which counts the bag's stacks as its own: the
		-- stack is never taken for room for itself
		local coal = NewStack(bagInventory, COAL, 3)

		Move(bot, coal, own)
		Expect(fail, "coal out of the carried bag: total", ix.stack.Count(own, COAL), 3)
		Expect(fail, "coal out of the carried bag: where", coal.invID, own:GetID())

		coal = NewStack(bagInventory, COAL, 2)
		Move(bot, coal, own, 1)
		Expect(fail, "part of the coal out of the carried bag: total", ix.stack.Count(own, COAL), 5)
		Expect(fail, "part of the coal out of the carried bag: left in the bag", Quantities(bagInventory, COAL), "1")

		Move(bot, coal, own)
		Expect(fail, "the rest of the coal: total", ix.stack.Count(own, COAL), 5)
		Expect(fail, "the rest of the coal: the bag", Quantities(bagInventory, COAL), "")
		CheckAll(fail, "coal out of the carried bag", {own, bagInventory})
		Lib.RemoveAll(own, COAL)

		-- a bag never goes into a bag
		ix.stack.StockAdd(own, "suitcase", 1)

		for _, second in ipairs(own:GetItemsByUniqueID("suitcase", true)) do
			if (second != bag) then
				Move(bot, second, bagInventory)
				Expect(fail, "a bag into a bag", second.invID, own:GetID())
				second:Remove()
			end
		end
	end)
end)

GWH.Check("inventorypanel: the server lets go of a storage on ixStorageClose, death, a knockout or being tied", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBotFully(bot)
		defer(function() ResetBotFully(bot) end)

		local prop, crate = Crate(defer, bot)

		local function Released(label)
			Expect(fail, label .. ": a receiver", ix.storage.InUseBy(crate, bot), false)
			Expect(fail, label .. ": open storage", bot.ixOpenStorage, nil)
			Expect(fail, label .. ": in use", ix.storage.InUse(crate), false)
			Expect(fail, label .. ": context", crate.storageInfo, nil)
			Expect(fail, label .. ": ready", bot.ixInventoryPanelReady, nil)
		end

		-- the panel closing for any reason on the client: ixStorageClose
		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		Expect(fail, "opened", bot.ixOpenStorage, crate)
		ReceiveReads("ixStorageClose", bot, {})
		Released("closed")

		-- dying with it open, whatever the client says
		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		bot:Kill()
		Released("died")
		ResetBotFully(bot)

		-- being tied with it open
		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		Tie(bot)
		Released("tied")
		ResetBotFully(bot)

		-- knocked out with it open
		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		bot:SetRagdolled(true)
		Released("knocked out")
		ResetBotFully(bot)

		-- a search broken off
		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 5})
		defer(function() timer.Remove("ixStare" .. bot:SteamID64()) end)
		ReceiveReads("ixStorageClose", bot, {})
		timer.Remove("ixStare" .. bot:SteamID64())
		Released("mid-search")
	end)
end)

GWH.Check("inventorypanel: the actions a panel lists are the old menu's, and still refused by OnCanRun and state", function(fail)
	local bot = GWH.Bot()
	local plugin = PanelPlugin()
	if (!bot or !plugin) then return fail("no bot or no plugin") end

	Scoped(function(defer)
		ResetBotFully(bot)
		defer(function() ResetBotFully(bot) Fresh(bot) end)

		local inventory = Fresh(bot)
		local scrap = NewStack(inventory, SCRAP, 5)
		local small = NewStack(inventory, SCRAP, 3)
		local gears = NewStack(inventory, "box_of_gears", 1)

		local function Keys(item)
			local actions, drop = plugin:GetItemActions(item, bot)
			local keys = {}

			for _, action in ipairs(actions) do keys[#keys + 1] = action.key end

			return table.concat(keys, ","), drop and drop.key
		end

		local keys, drop = Keys(scrap)

		Expect(fail, "a stack's actions", keys, "split")
		Expect(fail, "a stack's drop", drop, "drop")
		Expect(fail, "a single piece's actions", (Keys(gears)), "")
		Expect(fail, "split is offered as amounts", scrap.functions.split.isMulti, true)

		-- combine: the other stack of the same item and a bag, not another kind
		ix.stack.StockAdd(inventory, "suitcase", 1)
		NewStack(inventory, COAL, 1)

		local bag = inventory:HasItem("suitcase")
		local targets = {}

		for _, item in ipairs(plugin:GetCombineTargets(small, inventory:GetItems(), bot)) do
			targets[#targets + 1] = item.uniqueID
		end

		table.sort(targets)
		Expect(fail, "what a stack combines with", table.concat(targets, ","), SCRAP .. ",suitcase")
		Expect(fail, "what a bag combines with", #plugin:GetCombineTargets(bag, inventory:GetItems(), bot), 0)

		-- combining as the panel sends it: onto the other stack
		ix.item.PerformInventoryAction(bot, "combine", scrap:GetID(), inventory:GetID(), {small:GetID()})
		Expect(fail, "combined", Quantities(inventory, SCRAP), "8")

		-- an action its OnCanRun refuses (take, for something already carried) does nothing
		ix.item.PerformInventoryAction(bot, "take", scrap:GetID(), inventory:GetID(), {})
		Expect(fail, "take refused", inventory:GetItemByID(scrap:GetID()) != nil, true)

		-- a tied player's drop is refused
		Tie(bot)
		ix.item.PerformInventoryAction(bot, "drop", scrap:GetID(), inventory:GetID(), {})
		Expect(fail, "a tied player's drop", inventory:GetItemByID(scrap:GetID()) != nil, true)
		ResetBotFully(bot)

		-- how full it reads, from the real grid
		inventory = Fresh(bot)
		Expect(fail, "an empty bag", (plugin:GetFullness(inventory)), "invPanelEmpty")
		Fill(inventory, 0)
		Expect(fail, "a full bag", (plugin:GetFullness(inventory)), "invPanelFull")
	end)
end)

GWH.Check("inventorypanel: out of a carried bag into a full inventory stays in the bag; with room it lands in a cell", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBotFully(bot)
		defer(function() Fresh(bot) end)

		local own = Fresh(bot)

		-- saved for the length of the check, to see where the rows say things are
		Lib.Replace(defer, own, "noSave", nil)
		ix.stack.StockAdd(own, "suitcase", 1)

		local bag = own:HasItem("suitcase")
		local bagInventory = bag and bag:GetInventory()

		if (!bagInventory) then return fail("the suitcase has no inventory") end

		Lib.Replace(defer, bagInventory, "noSave", nil)
		defer(function() for _, v in pairs(bagInventory:GetItems()) do v:Remove() end end)

		local filler = ix.stack.StockAdd(bagInventory, FILLER, 1) and bagInventory:HasItem(FILLER)
		local scrap = NewStack(bagInventory, SCRAP, 3)
		NewStack(bagInventory, SCRAP, 2)

		Fill(own, 0)

		if (Lib.FreeCells(own) != 0 or Lib.FreeCells(bagInventory) == 0) then
			return fail("could not fill the inventory and leave room in the bag")
		end

		local inventories = {own, bagInventory}
		local row = Row(filler)

		-- a full inventory: refused, everything stays where it was (the bag has room, and is never used for it)
		Move(bot, filler, own)
		CheckPlaced(fail, "a filler into a full inventory", filler, inventories)
		Expect(fail, "a filler into a full inventory: where", filler.invID, bagInventory:GetID())
		Expect(fail, "a filler into a full inventory: its row", Row(filler), row)

		Move(bot, scrap, own)
		Move(bot, scrap, own, 1)
		CheckPlaced(fail, "scrap into a full inventory", scrap, inventories)
		Expect(fail, "scrap into a full inventory: the bag's", Quantities(bagInventory, SCRAP), "3,2")
		Expect(fail, "scrap into a full inventory: the inventory's", Quantities(own, SCRAP), "3,2")

		-- exactly one free cell: the filler lands in it
		local last

		for _, item in pairs(own:GetItems(true)) do
			if (item.uniqueID == FILLER) then last = item end
		end

		local x, y = last.gridX, last.gridY

		last:Remove()
		Move(bot, filler, own)
		CheckPlaced(fail, "a filler into the one free cell", filler, inventories)
		Expect(fail, "a filler into the one free cell: where", filler.invID .. "@" .. filler.gridX .. "," .. filler.gridY,
			own:GetID() .. "@" .. x .. "," .. y)
		Expect(fail, "a filler into the one free cell: its row", Row(filler), own:GetID() .. "@" .. x .. "," .. y)

		-- the same for the scrap: one free cell, and the other stack in the bag is never merged into
		for _, item in pairs(own:GetItems(true)) do
			if (item.uniqueID == FILLER and item != filler) then last = item break end
		end

		last:Remove()
		Move(bot, scrap, own)
		CheckPlaced(fail, "scrap into the one free cell", scrap, inventories)
		Expect(fail, "scrap into the one free cell: where", scrap.invID, own:GetID())
		Expect(fail, "scrap into the one free cell: the bag's", Quantities(bagInventory, SCRAP), "2")

		-- a part, with no free cell left: refused; and the part never comes back into the bag it is in
		local part = NewStack(bagInventory, SCRAP, 4)

		for _, stack in ipairs(ix.stack.GetStacks(own, SCRAP)) do
			if (stack.invID == own:GetID()) then stack:SetData("quantity", 20) end
		end

		Move(bot, part, own, 1)
		Expect(fail, "a part with no room: the bag's", Quantities(bagInventory, SCRAP), "4,2")
		Expect(fail, "a part with no room: total", ix.stack.Count(own, SCRAP), 26)
	end)
end)

GWH.Check("inventorypanel: a part left in a crate stays its character's, and another character's stack is never merged into", function(fail)
	local target = OtherBot()
	if (!target) then return fail("no second bot") end

	Scoped(function(defer)
		ResetBotFully(target)

		local first = target:GetCharacter()
		local prop, crate = Crate(defer, target)

		local function Near()
			target:SetPos(prop:GetPos() - Vector(50, 0, 10))
		end

		local function Open()
			Near()
			ix.storage.Open(target, crate, {entity = prop, name = "crate", searchTime = 0})
		end

		defer(function()
			if (target:GetCharacter() != first) then Lib.Switch(target, first) end
			Fresh(target)
		end)

		local own = Fresh(target)
		local stack = NewStack(own, SCRAP, 5)

		Open()
		Move(target, stack, crate, 2)

		local left = ix.stack.GetStacks(crate, SCRAP)[1]

		if (!left) then return fail("nothing was left in the crate") end

		Expect(fail, "the part's character", left:GetCharacterID(), first:GetID())
		Expect(fail, "the part's player", left:GetPlayerID(), target:SteamID64())

		-- the same player on another character: cannot take it
		local second = Lib.NewCharacter(target)

		Lib.Switch(target, second)
		Open()

		local secondInventory = second:GetInventory()

		-- a real load makes the player a receiver of the character's inventory; Switch loads without networking
		secondInventory:AddReceiver(target)

		-- control: something nobody owns, they can take
		local loose = ix.stack.StockAdd(crate, FILLER, 1) and crate:HasItem(FILLER)

		Move(target, loose, secondInventory)
		Expect(fail, "the other character takes an unowned filler", loose.invID, secondInventory:GetID())

		Move(target, left, secondInventory)
		Expect(fail, "taken by another character: the crate's", Quantities(crate, SCRAP), "2")
		Expect(fail, "taken by another character: theirs", Quantities(secondInventory, SCRAP), "")

		-- that character's own stack in the crate
		local theirs = NewStack(crate, SCRAP, 4)
		theirs.characterID, theirs.playerID = second:GetID(), target:SteamID64()

		Lib.Switch(target, first)
		own = first:GetInventory()
		Open()

		Expect(fail, "what the first character kept", Quantities(own, SCRAP), "3")

		-- the first character's own part there is full, so the only partial stack is the other character's
		left:SetData("quantity", 20)

		Move(target, ix.stack.GetStacks(own, SCRAP)[1], crate)
		Expect(fail, "the other character's stack", ix.stack.GetQuantity(theirs), 4)
		Expect(fail, "the crate's", Quantities(crate, SCRAP), "20,4,3")
		Expect(fail, "the bot's", Quantities(own, SCRAP), "")
	end)
end)

GWH.Check("inventorypanel: opening another storage lets go of the first, and a refused one keeps it usable", function(fail)
	local bot, other = GWH.Bot(), OtherBot()
	if (!bot or !other) then return fail("no bots") end

	Scoped(function(defer)
		ResetBotFully(bot)
		ResetBotFully(other)
		defer(function() Fresh(bot) Fresh(other) end)

		local firstProp, first = Crate(defer, bot)
		local secondProp, second = Crate(defer, bot)

		ix.storage.Open(bot, first, {entity = firstProp, name = "first", searchTime = 0})
		ix.storage.Open(bot, second, {entity = secondProp, name = "second", searchTime = 0})
		Expect(fail, "the first, let go of", ix.storage.InUseBy(first, bot), false)
		Expect(fail, "the first, free", ix.storage.InUse(first), false)
		Expect(fail, "the second, open", bot.ixOpenStorage, second)
		Expect(fail, "the second, ready", bot.ixInventoryPanelReady, second)

		-- the other bot has the first open, then is refused the second (the bot has it)
		other:SetPos(firstProp:GetPos() - Vector(50, 0, 10))
		ix.storage.Open(other, first, {entity = firstProp, name = "first", searchTime = 0})
		ix.storage.Open(other, second, {entity = secondProp, name = "second", searchTime = 0})
		Expect(fail, "refused: still open", other.ixOpenStorage, first)
		Expect(fail, "refused: still ready", other.ixInventoryPanelReady, first)

		local filler = GiveItem(Fresh(other), FILLER)

		Move(other, filler, first)
		Expect(fail, "refused: the first still takes things", filler.invID, first:GetID())

		ReceiveReads("ixStorageClose", other, {})
		ReceiveReads("ixStorageClose", bot, {})
	end)
end)

GWH.Check("inventorypanel: things in a carried bag keep their actions, and a bag in a storage can be emptied", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBotFully(bot)
		defer(function() Fresh(bot) end)

		local own = Fresh(bot)

		ix.stack.StockAdd(own, "suitcase", 1)

		local bagInventory = own:HasItem("suitcase"):GetInventory()

		defer(function() for _, v in pairs(bagInventory:GetItems()) do v:Remove() end end)

		-- split, as the bag panel sends it for something in the bag
		local stack = NewStack(bagInventory, SCRAP, 5)

		Lib.Split(bot, stack, "1")
		Expect(fail, "split in the carried bag", Quantities(bagInventory, SCRAP), "4,1")

		local keys = {}

		for _, action in ipairs(PanelPlugin():GetItemActions(stack, bot)) do keys[#keys + 1] = action.key end

		Expect(fail, "actions in the carried bag", table.concat(keys, ","), "split")

		-- a suitcase inside a crate: something in it can be taken once the crate is open, not before
		local prop, crate = Crate(defer, bot)

		ix.stack.StockAdd(crate, "suitcase", 1)

		local inner = crate:HasItem("suitcase"):GetInventory()

		if (!inner) then return fail("the suitcase in the crate has no inventory") end

		defer(function() for _, v in pairs(inner:GetItems()) do v:Remove() end end)

		local filler = ix.stack.StockAdd(inner, FILLER, 1) and inner:HasItem(FILLER)

		Move(bot, filler, own)
		Expect(fail, "out of a bag in a closed crate", filler.invID, inner:GetID())

		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		Move(bot, filler, own)
		Expect(fail, "out of a bag in an open crate", filler.invID, own:GetID())
		CheckPlaced(fail, "out of a bag in an open crate", filler, {own, inner, crate})

		ReceiveReads("ixStorageClose", bot, {})
	end)
end)

GWH.Check("inventorypanel: moves are logged, rate limited, and refused for someone else's item; a searched player", function(fail)
	local bot = GWH.Bot()
	local target = OtherBot()
	if (!bot or !target or !Schema.SearchPlayer) then return fail("no bots or no Schema.SearchPlayer") end

	Scoped(function(defer)
		ResetBotFully(bot)
		ResetBotFully(target)
		defer(function() ResetBotFully(target) Fresh(target) Fresh(bot) ReceiveReads("ixStorageClose", bot, {}) end)

		local own = Fresh(bot)
		local prop, crate = Crate(defer, bot)

		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		NewStack(crate, SCRAP, 2)

		-- a move that only merges is logged, with who did it
		local mine = NewStack(own, SCRAP, 3)
		local seen = Lib.Capture(bot, function() Move(bot, mine, crate) end)

		Expect(fail, "a merge is logged", seen.logs:find("inventoryPanelMove", 1, true) != nil, true)
		CheckAll(fail, "a merge", {own, crate})

		-- two at once: the second is dropped
		local a, b = GiveItem(own, FILLER), GiveItem(own, FILLER)

		Move(bot, a, crate)
		ReceiveReads("ixInventoryPanelMove", bot, {ReadUInt = {b:GetID(), crate:GetID()}, ReadBool = {false}})
		Expect(fail, "the first of two", a.invID, crate:GetID())
		Expect(fail, "the second of two, at once", b.invID, own:GetID())
		CheckAll(fail, "two at once", {own, crate})

		-- someone else's item, out of their inventory
		local theirs = GiveItem(Fresh(target), FILLER)

		Move(bot, theirs, own)
		Expect(fail, "someone else's item", theirs.invID, target:GetCharacter():GetInventory():GetID())
		CheckAll(fail, "someone else's item", {own, crate, target:GetCharacter():GetInventory()})

		-- a tied player searched: their things can be taken in reach, not from out of it
		target:SetPos(bot:GetPos() + Vector(40, 0, 0))
		Tie(target)
		Schema:SearchPlayer(bot, target)

		Move(bot, theirs, own)
		Expect(fail, "from a searched player", theirs.invID, own:GetID())
		CheckAll(fail, "from a searched player", {own, crate, target:GetCharacter():GetInventory()})

		local back = GiveItem(target:GetCharacter():GetInventory(), FILLER)

		target:SetPos(target:GetPos() + FAR)
		Move(bot, back, own)
		Expect(fail, "from a searched player out of reach", back.invID, target:GetCharacter():GetInventory():GetID())
		CheckAll(fail, "from a searched player out of reach", {own, crate, target:GetCharacter():GetInventory()})
	end)
end)

GWH.Check("inventorypanel: a tap does the first of the tap actions an item offers, or nothing", function(fail)
	local bot = GWH.Bot()
	local plugin = PanelPlugin()
	if (!bot or !plugin) then return fail("no bot or no plugin") end

	Scoped(function(defer)
		ResetBotFully(bot)
		defer(function() Fresh(bot) end)

		local inventory = Fresh(bot)

		local function Key(uniqueID)
			local item = GiveItem(inventory, uniqueID)
			local action = plugin:GetTapAction(item, bot)

			return action and action.key or "none"
		end

		Expect(fail, "water", Key("water"), "Drink")
		Expect(fail, "a pistol", Key("pistol"), "Equip")
		Expect(fail, "a stack of scrap", (function()
			local action = plugin:GetTapAction(NewStack(inventory, SCRAP, 3), bot)

			return action and action.key or "none"
		end)(), "none")

		for _, key in ipairs(plugin.tapActions) do
			if (key == "split" or key == "drop" or key == "combine") then fail("a tap would " .. key) end
		end
	end)
end)

GWH.Check("inventorypanel: a move to a cell lands exactly there, within one grid (saved as Helix saves it) or across", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBotFully(bot)
		defer(function() Fresh(bot) ReceiveReads("ixStorageClose", bot, {}) end)

		local own = Fresh(bot)

		-- saved for the length of the check, to see the position the row gets
		Lib.Replace(defer, own, "noSave", nil)

		local filler = GiveItem(own, FILLER)
		local inventories = {own}

		-- within the grid: the cells, the item's position and its row move; nothing else does
		Move(bot, filler, own, nil, 4, 3)
		Expect(fail, "a filler within the grid", filler.gridX .. "," .. filler.gridY, "4,3")
		Expect(fail, "a filler within the grid: its row", Row(filler), own:GetID() .. "@4,3")
		CheckPlaced(fail, "a filler within the grid", filler, inventories)
		CheckGrid(fail, own, "a filler within the grid")

		-- a 2x2 moved one cell over its own old cells
		ix.stack.StockAdd(own, "suitcase", 1, nil, 1, 1)

		local bag = own:HasItem("suitcase")
		local bagInventory = bag and bag:GetInventory()

		if (!bagInventory) then return fail("the suitcase has no inventory") end

		defer(function() for _, v in pairs(bagInventory:GetItems()) do v:Remove() end end)

		Move(bot, bag, own, nil, 2, 1)
		Expect(fail, "a suitcase over its own cells", bag.gridX .. "," .. bag.gridY, "2,1")
		Expect(fail, "the suitcase keeps its inventory", bag:GetInventory(), bagInventory)
		CheckPlaced(fail, "a suitcase over its own cells", bag, inventories)
		CheckGrid(fail, own, "a suitcase over its own cells")

		-- a stack to a cell: lies there whole, merged into nothing (another partial stack is in the grid)
		local first = NewStack(own, SCRAP, 3)
		local second = NewStack(own, SCRAP, 2)

		Move(bot, second, own, nil, 6, 4)
		Expect(fail, "a stack within the grid", second.gridX .. "," .. second.gridY, "6,4")
		Expect(fail, "a stack within the grid: both stacks", Quantities(own, SCRAP), "3,2")
		CheckPlaced(fail, "a stack within the grid", second, inventories)

		-- into a carried bag at a cell (an explicit cell needs no rule about spilling into bags)
		Move(bot, filler, bagInventory, nil, 3, 2)
		Expect(fail, "a filler into the carried bag's cell", filler.invID .. "@" .. filler.gridX .. "," .. filler.gridY,
			bagInventory:GetID() .. "@3,2")
		CheckPlaced(fail, "a filler into the carried bag", filler, {own, bagInventory})

		-- across into an open crate's cell, whole and in part
		local prop, crate = Crate(defer, bot)

		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		NewStack(crate, SCRAP, 1)

		inventories = {own, bagInventory, crate}

		Move(bot, filler, crate, nil, 4, 4)
		Expect(fail, "a filler into the crate's cell", filler.invID .. "@" .. filler.gridX .. "," .. filler.gridY,
			crate:GetID() .. "@4,4")
		CheckPlaced(fail, "a filler into the crate", filler, inventories)

		Move(bot, first, crate, nil, 1, 4)
		Expect(fail, "a whole stack into the crate's cell", first.invID .. "@" .. first.gridX .. "," .. first.gridY,
			crate:GetID() .. "@1,4")
		Expect(fail, "a whole stack into the crate's cell: merged into nothing", Quantities(crate, SCRAP), "3,1")
		CheckPlaced(fail, "a whole stack into the crate", first, inventories)

		Move(bot, second, crate, 1, 2, 4)

		local part = crate.slots[2] and crate.slots[2][4]

		Expect(fail, "part of a stack into the crate's cell", istable(part) and part.uniqueID or "nothing", SCRAP)
		Expect(fail, "part of a stack: what is left", ix.stack.GetQuantity(second), 1)
		Expect(fail, "part of a stack: the crate's", Quantities(crate, SCRAP), "3,1,1")

		if (istable(part)) then
			Expect(fail, "part of a stack keeps its owner", part:GetCharacterID(), bot:GetCharacter():GetID())
			CheckPlaced(fail, "part of a stack", part, inventories)
		end

		CheckPlaced(fail, "what is left of the stack", second, inventories)

		-- and back out to a cell of the bot's own grid
		Move(bot, filler, own, nil, 1, 4)
		Expect(fail, "a filler back to a cell", filler.invID .. "@" .. filler.gridX .. "," .. filler.gridY,
			own:GetID() .. "@1,4")
		CheckPlaced(fail, "a filler back", filler, inventories)

		for _, inventory in ipairs(inventories) do
			CheckGrid(fail, inventory, "after the moves")
		end
	end)
end)

GWH.Check("inventorypanel: a cell out of range, taken, too small, the same, someone else's or out of reach is refused and changes nothing", function(fail)
	local bot, target = GWH.Bot(), OtherBot()
	local plugin = PanelPlugin()
	if (!bot or !target or !plugin or !Schema.SearchPlayer) then return fail("no bots, plugin or Schema.SearchPlayer") end

	Scoped(function(defer)
		ResetBotFully(bot)
		ResetBotFully(target)
		defer(function() ResetBotFully(target) Fresh(target) Fresh(bot) ReceiveReads("ixStorageClose", bot, {}) end)

		local own = Fresh(bot)

		Lib.Replace(defer, own, "noSave", nil)

		local filler = GiveItem(own, FILLER)
		local blocker = GiveItem(own, FILLER)

		ix.stack.StockAdd(own, "suitcase", 1)

		local bag = own:HasItem("suitcase")
		local bagInventory = bag and bag:GetInventory()

		if (!bagInventory) then return fail("the suitcase has no inventory") end

		defer(function() for _, v in pairs(bagInventory:GetItems()) do v:Remove() end end)

		-- the filler and the suitcase where the checks expect them
		Move(bot, filler, own, nil, 1, 1)
		Move(bot, blocker, own, nil, 3, 3)
		Move(bot, bag, own, nil, 5, 1)

		local inventories = {own, bagInventory}
		local positions = Positions(own)
		local row = Row(filler)

		local function Unchanged(label)
			Expect(fail, label .. ": the grid", Positions(own), positions)
			Expect(fail, label .. ": the filler's row", Row(filler), row)
			CheckPlaced(fail, label .. ": the filler", filler, inventories)
			CheckPlaced(fail, label .. ": the suitcase", bag, inventories)
			CheckGrid(fail, own, label)
		end

		Expect(fail, "set up", filler.gridX .. "," .. filler.gridY .. " " .. bag.gridX .. "," .. bag.gridY, "1,1 5,1")

		-- out of range, or not a whole number of cells (straight to MoveItem: the net message only carries 0..255)
		for _, cell in ipairs({{0, 1}, {1, 0}, {own.w + 1, 1}, {1, own.h + 1}, {255, 255}}) do
			Move(bot, filler, own, nil, cell[1], cell[2])
			Unchanged("cell " .. cell[1] .. "," .. cell[2])
		end

		for _, cell in ipairs({{2.5, 1}, {-1, 1}, {0 / 0, 1}, {math.huge, 1}, {1, -math.huge}}) do
			bot.ixInventoryPanelNextMove = nil
			plugin:MoveItem(bot, filler:GetID(), own:GetID(), nil, cell[1], cell[2])
			Unchanged("cell " .. tostring(cell[1]) .. "," .. tostring(cell[2]))
		end

		-- onto another item, partly over one, and off the edge
		Move(bot, filler, own, nil, 3, 3)
		Unchanged("onto another filler")
		Move(bot, bag, own, nil, 2, 2)
		Unchanged("a suitcase over a filler")
		Move(bot, bag, own, nil, own.w, 1)
		Unchanged("a suitcase off the right edge")
		Move(bot, bag, own, nil, 1, own.h)
		Unchanged("a suitcase off the bottom edge")

		-- the cell it is already in
		local bMoved, phrase = plugin:MoveItem(bot, filler:GetID(), own:GetID(), nil, 1, 1)

		Expect(fail, "onto itself", bMoved, false)
		Expect(fail, "onto itself says", phrase, "invPanelSamePlace")
		Unchanged("onto itself")

		-- part of a stack within its own grid is no move at all
		local stack = NewStack(own, SCRAP, 4)
		local quantities = Quantities(own, SCRAP)

		positions = Positions(own)
		Move(bot, stack, own, 1, 1, 4)
		Expect(fail, "part of a stack within its grid", Quantities(own, SCRAP), quantities)
		Unchanged("part of a stack within its grid")

		-- a bag into a bag, and something equipped out of the inventory, at a free cell
		Move(bot, bag, bagInventory, nil, 1, 1)
		Unchanged("a bag into a bag")

		local pistol = GiveItem(own, "pistol")

		pistol:SetData("equip", true)
		defer(function() if (ix.item.instances[pistol:GetID()]) then pistol:SetData("equip", nil) end end)
		positions = Positions(own)
		Move(bot, pistol, bagInventory, nil, 3, 1)
		Expect(fail, "an equipped pistol into the bag", pistol.invID, own:GetID())
		Unchanged("an equipped pistol into the bag")

		-- another player's inventory, at a free cell
		local theirs = target:GetCharacter():GetInventory()

		Fresh(target)
		Move(bot, filler, theirs, nil, 1, 1)
		Unchanged("into another player's inventory")

		-- a searched player out of reach: nothing of theirs comes to a cell of the bot's, nothing goes to theirs
		local their = GiveItem(theirs, FILLER)

		target:SetPos(bot:GetPos() + Vector(40, 0, 0))
		Tie(target)
		Schema:SearchPlayer(bot, target)
		target:SetPos(target:GetPos() + FAR)

		Move(bot, their, own, nil, 2, 4)
		Expect(fail, "from a searched player out of reach", their.invID, theirs:GetID())
		Move(bot, filler, theirs, nil, 6, 4)
		Unchanged("to a searched player out of reach")

		-- in reach again it lands at the cell asked for
		target:SetPos(bot:GetPos() + Vector(40, 0, 0))
		Move(bot, their, own, nil, 2, 4)
		Expect(fail, "from a searched player in reach", their.invID .. "@" .. their.gridX .. "," .. their.gridY,
			own:GetID() .. "@2,4")
		CheckPlaced(fail, "from a searched player", their, {own, theirs})
	end)
end)

GWH.Check("inventorypanel: a thing put onto another combines as the old drag did, behind the case's gates", function(fail)
	local bot, target = GWH.Bot(), OtherBot()
	local plugin = PanelPlugin()
	if (!bot or !target or !plugin) then return fail("no bots or no plugin") end

	Scoped(function(defer)
		ResetBotFully(bot)
		ResetBotFully(target)
		defer(function() ResetBotFully(bot) Fresh(bot) Fresh(target) ReceiveReads("ixStorageClose", bot, {}) end)

		local own = Fresh(bot)

		-- a stack onto a stack: merged, logged
		local a, b = NewStack(own, SCRAP, 3), NewStack(own, SCRAP, 2)
		local seen = Lib.Capture(bot, function() Combine(bot, b, a) end)

		Expect(fail, "a stack onto a stack", Quantities(own, SCRAP), "5")
		Expect(fail, "a combine is logged", seen.logs:find("inventoryPanelCombine", 1, true) != nil, true)

		-- a filler onto the suitcase: the bag's own combine takes it
		ix.stack.StockAdd(own, "suitcase", 1)

		local bag = own:HasItem("suitcase")
		local bagInventory = bag and bag:GetInventory()

		if (!bagInventory) then return fail("the suitcase has no inventory") end

		defer(function() for _, v in pairs(bagInventory:GetItems()) do v:Remove() end end)

		local filler = GiveItem(own, FILLER)

		Combine(bot, filler, bag)
		Expect(fail, "a filler onto the suitcase", filler.invID, bagInventory:GetID())
		CheckPlaced(fail, "a filler onto the suitcase", filler, {own, bagInventory})

		-- what does not combine changes nothing: onto itself, a filler onto a filler, a bag onto a bag
		local other = GiveItem(own, FILLER)
		local before = Contents(own)

		Combine(bot, other, other)
		Combine(bot, other, GiveItem(own, FILLER))

		ix.stack.StockAdd(own, "suitcase", 1)

		for _, second in ipairs(own:GetItemsByUniqueID("suitcase", true)) do
			if (second != bag) then
				Combine(bot, second, bag)
				Expect(fail, "a bag onto a bag", second.invID, own:GetID())
				bot.ixInventoryPanelNextMove = nil
				Expect(fail, "a bag onto a bag says", select(2, plugin:CombineItems(bot, second:GetID(), bag:GetID())),
					"invPanelNoBagInBag")
			end
		end

		before = Contents(own)

		local bSuccess, phrase = plugin:CombineItems(bot, other:GetID(), other:GetID())

		Expect(fail, "onto itself", bSuccess, false)
		Expect(fail, "onto itself says", phrase, "invPanelNoCombine")
		Expect(fail, "nothing changed", Contents(own), before)

		-- the reason given is the real one: something equipped, a bag with no room left
		local pistol = GiveItem(own, "pistol")

		pistol:SetData("equip", true)
		Expect(fail, "an equipped pistol onto the bag says", select(2, plugin:CombineItems(bot, pistol:GetID(),
			bag:GetID())), "invPanelTakeOffFirst")
		Expect(fail, "an equipped pistol onto the bag: where", pistol.invID, own:GetID())
		pistol:SetData("equip", nil)
		pistol:Remove()

		Fill(bagInventory, 0)
		other = GiveItem(own, FILLER)
		Expect(fail, "onto a full bag says", select(2, plugin:CombineItems(bot, other:GetID(), bag:GetID())),
			"invPanelBagFull")
		Expect(fail, "onto a full bag: where", other.invID, own:GetID())
		CheckAll(fail, "onto a full bag", {own, bagInventory})

		for _, v in pairs(bagInventory:GetItems()) do
			if (v != filler) then v:Remove() end
		end

		-- from an open crate onto the bot's stack: merged; once the crate is closed or out of reach: nothing
		local prop, crate = Crate(defer, bot)
		local mine = ix.stack.GetStacks(own, SCRAP)[1]
		local theirs = NewStack(crate, SCRAP, 4)

		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		Combine(bot, theirs, mine)
		Expect(fail, "from an open crate", Quantities(own, SCRAP) .. "/" .. Quantities(crate, SCRAP), "9/")

		theirs = NewStack(crate, SCRAP, 2)
		prop:SetPos(prop:GetPos() + FAR)
		Combine(bot, theirs, mine)
		Expect(fail, "from a crate out of reach", Quantities(own, SCRAP) .. "/" .. Quantities(crate, SCRAP), "9/2")
		prop:SetPos(prop:GetPos() - FAR)

		ReceiveReads("ixStorageClose", bot, {})
		Combine(bot, theirs, mine)
		Expect(fail, "from a closed crate", Quantities(own, SCRAP) .. "/" .. Quantities(crate, SCRAP), "9/2")

		-- someone else's stack onto the bot's, and the bot's onto theirs
		local elsewhere = NewStack(Fresh(target), SCRAP, 1)

		Combine(bot, elsewhere, mine)
		Combine(bot, mine, elsewhere)
		Expect(fail, "someone else's", Quantities(own, SCRAP) .. "/" .. Quantities(target:GetCharacter():GetInventory(),
			SCRAP), "9/1")

		-- a tied player combines nothing
		local small = NewStack(own, SCRAP, 1)

		Tie(bot)
		Combine(bot, small, mine)
		Expect(fail, "tied", Quantities(own, SCRAP), "9,1")
		ResetBotFully(bot)
	end)
end)

GWH.Check("inventorypanel: a plain thing moved across to a cell that is taken, too small or off the grid is refused, both ways", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBotFully(bot)
		defer(function() Fresh(bot) ReceiveReads("ixStorageClose", bot, {}) end)

		local own = Fresh(bot)

		ix.stack.StockAdd(own, "suitcase", 1)

		local bag = own:HasItem("suitcase")
		local bagInventory = bag and bag:GetInventory()

		if (!bagInventory) then return fail("the suitcase has no inventory") end

		defer(function() for _, v in pairs(bagInventory:GetItems()) do v:Remove() end end)

		local prop, crate = Crate(defer, bot)

		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})

		local inventories = {own, bagInventory, crate}

		-- plain (not stackable) things: a 1x1 and a 2x2 in the carried bag, a 1x1 blocker in each of the others
		local small = ix.stack.StockAdd(bagInventory, FILLER, 1, nil, 1, 1) and bagInventory:GetItemAt(1, 1)
		local big = ix.stack.StockAdd(bagInventory, "resistance_uniform", 1, nil, 3, 1) and bagInventory:GetItemAt(3, 1)
		local crateBlocker = ix.stack.StockAdd(crate, FILLER, 1, nil, 4, 4) and crate:GetItemAt(4, 4)
		local bagBlocker = ix.stack.StockAdd(bagInventory, FILLER, 1, nil, 2, 2) and bagInventory:GetItemAt(2, 2)

		if (!istable(small) or !istable(big) or !istable(crateBlocker) or !istable(bagBlocker)) then
			return fail("could not set up the things")
		end

		if (ix.stack.IsStackable(small) or ix.stack.IsStackable(big)) then
			return fail("the things are meant to be plain items")
		end

		local function Refused(label, item, from, x, y)
			local before = Contents(own) .. "|" .. Contents(crate) .. "|" .. Positions(bagInventory) .. "|" ..
				Positions(crate)

			Move(bot, item, from == crate and bagInventory or crate, nil, x, y)
			Expect(fail, label .. ": where it is", item.invID, from:GetID())
			Expect(fail, label .. ": nothing changed", Contents(own) .. "|" .. Contents(crate) .. "|" ..
				Positions(bagInventory) .. "|" .. Positions(crate), before)
			CheckPlaced(fail, label .. ": the crate's blocker", crateBlocker, inventories)
			CheckPlaced(fail, label .. ": the bag's blocker", bagBlocker, inventories)
			CheckAll(fail, label, inventories)
		end

		-- carried bag -> crate: onto the blocker, off the 4x4 grid, a 2x2 partly over the blocker, a 2x2 off the edge
		Refused("a filler onto the crate's blocker", small, bagInventory, 4, 4)
		Refused("a filler off the crate's grid", small, bagInventory, 5, 1)
		Refused("a 2x2 partly over the crate's blocker", big, bagInventory, 3, 3)
		Refused("a 2x2 off the crate's edge", big, bagInventory, 4, 1)

		-- what does fit lands there
		Move(bot, small, crate, nil, 1, 1)
		Move(bot, big, crate, nil, 2, 2)
		Expect(fail, "a filler to a free cell of the crate", small.invID .. "@" .. small.gridX .. "," .. small.gridY,
			crate:GetID() .. "@1,1")
		Expect(fail, "a 2x2 to free cells of the crate", big.invID .. "@" .. big.gridX .. "," .. big.gridY,
			crate:GetID() .. "@2,2")
		CheckAll(fail, "into the crate", inventories)

		-- crate -> carried bag (4x2): onto the bag's blocker, off its grid, a 2x2 partly over the blocker, off its edge
		Refused("a filler onto the bag's blocker", small, crate, 2, 2)
		Refused("a filler off the bag's grid", small, crate, 1, 3)
		Refused("a 2x2 partly over the bag's blocker", big, crate, 1, 1)
		Refused("a 2x2 off the bag's edge", big, crate, 4, 1)

		Move(bot, big, bagInventory, nil, 3, 1)
		Expect(fail, "a 2x2 back to free cells of the bag", big.invID .. "@" .. big.gridX .. "," .. big.gridY,
			bagInventory:GetID() .. "@3,1")
		CheckAll(fail, "back into the bag", inventories)
	end)
end)

-- Calls fn and returns every net message started while it ran as {name, recipients (a set of players)}.
local function CaptureSends(fn)
	local sent = {}

	Scoped(function(defer)
		local start, send, current = net.Start, net.Send, nil

		Lib.Replace(defer, net, "Start", function(name, ...)
			current = name
			return start(name, ...)
		end)

		Lib.Replace(defer, net, "Send", function(recipients, ...)
			local set = {}

			if (isentity(recipients)) then
				set[recipients] = true
			elseif (istable(recipients)) then
				for _, v in ipairs(recipients) do set[v] = true end
			elseif (recipients and recipients.GetPlayers) then
				for _, v in ipairs(recipients:GetPlayers()) do set[v] = true end
			end

			sent[#sent + 1] = {name = current, recipients = set}

			return send(recipients, ...)
		end)

		fn()
	end)

	return sent
end

GWH.Check("inventorypanel: a move within one grid is sent to everyone who sees that grid", function(fail)
	local bot, other = GWH.Bot(), OtherBot()
	if (!bot or !other) then return fail("no bots") end

	Scoped(function(defer)
		ResetBotFully(bot)
		ResetBotFully(other)
		defer(function()
			Fresh(bot)
			Fresh(other)
			ReceiveReads("ixStorageClose", bot, {})
			ReceiveReads("ixStorageClose", other, {})
		end)

		local function Sent(sent, label, item, inventory, receivers)
			local found

			for _, message in ipairs(sent) do
				if (message.name == "ixInventoryMove") then
					found = message
				end
			end

			if (!found) then
				return fail(label .. ": no ixInventoryMove was sent")
			end

			for _, receiver in ipairs(receivers) do
				Expect(fail, label .. ": sent to " .. receiver:Name(), found.recipients[receiver] == true, true)
			end

			CheckAll(fail, label, {inventory})
		end

		-- the bot's own inventory: to the bot
		local own = Fresh(bot)
		local filler = GiveItem(own, FILLER)
		local sent = CaptureSends(function() Move(bot, filler, own, nil, 5, 4) end)

		Expect(fail, "own grid: moved", filler.gridX .. "," .. filler.gridY, "5,4")
		Sent(sent, "own grid", filler, own, {bot})

		-- a crate two players have open: to both
		local prop, crate = Crate(defer, bot)

		other:SetPos(prop:GetPos() - Vector(50, 0, 10))
		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0, bMultipleUsers = true})
		ix.storage.Open(other, crate, {entity = prop, name = "crate", searchTime = 0, bMultipleUsers = true})

		if (!ix.storage.InUseBy(crate, bot) or !ix.storage.InUseBy(crate, other)) then
			return fail("could not open the crate for both")
		end

		local thing = ix.stack.StockAdd(crate, FILLER, 1, nil, 1, 1) and crate:GetItemAt(1, 1)

		sent = CaptureSends(function() Move(bot, thing, crate, nil, 3, 3) end)
		Expect(fail, "shared crate: moved", thing.gridX .. "," .. thing.gridY, "3,3")
		Sent(sent, "shared crate", thing, crate, {bot, other})

		-- a refused one sends nothing of the kind
		sent = CaptureSends(function() Move(bot, thing, crate, nil, 5, 5) end)

		for _, message in ipairs(sent) do
			if (message.name == "ixInventoryMove") then fail("a refused move sent ixInventoryMove") end
		end
	end)
end)
