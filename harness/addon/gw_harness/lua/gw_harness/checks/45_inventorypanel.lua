-- Inventory panel (inventorypanel): the bag, storages, corpses and searches on world panels. Server side: the
-- plugin, its net messages, command and phrases; Rearrange (ixInventoryPanelTidy) keeps every item, quantity, data
-- and bag, refuses a packing that does not fit, syncs whoever sees the grid, is refused for a player who cannot act
-- and is rate limited; moves (ixInventoryPanelMove, ix.stack.MoveTo) between the bot and an open crate, and out of
-- and into a carried bag, merge stacks, keep every item in exactly one cell of one grid, never make or lose any,
-- keep a part's owner and never merge into another character's stack, are logged and rate limited, and are refused
-- before the search ends, out of reach, once closed, for someone else's inventory or item and for a player who
-- cannot act; the server lets go of a storage on ixStorageClose (the panel sends it whenever it closes on its own:
-- looked away, walked off, closed, Tab, another panel; not when the server itself closed it or opened another), on
-- death, a knockout, being tied and opening another storage, and a refused open leaves the first one usable; the
-- actions a panel lists are the old menu's (OnCanRun) and still go through PerformInventoryAction's gates, in a
-- carried bag too. The panels themselves are client-only and are judged in a play session. Split's offered amounts
-- are in 40_stacking.lua. Helix's own ixInventoryMove and storage money handlers are not gated here (draft PR #17).

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

-- What the client sends when a row is chosen: the item, where to, and how much of a stack (nil for all of it).
local function Move(bot, item, inventory, amount)
	bot.ixInventoryPanelNextMove = nil

	local reads = {ReadUInt = {item:GetID(), inventory:GetID()}, ReadBool = {amount != nil}}

	if (amount != nil) then
		reads.ReadDouble = {amount}
	end

	ReceiveReads("ixInventoryPanelMove", bot, reads)
end

local function Tidy(bot, bKeepRate)
	if (!bKeepRate) then
		bot.ixInventoryPanelNextTidy = nil
	end

	ReceiveReads("ixInventoryPanelTidy", bot, {})
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

-- The inventory_id, x and y the database holds for an item, as "id@x,y".
local function Row(item)
	local row = sql.QueryRow("SELECT inventory_id, x, y FROM ix_items WHERE item_id = " .. tonumber(item:GetID()))

	return row and (row.inventory_id .. "@" .. row.x .. "," .. row.y) or "none"
end

-- An inventory a tidy would change: one filler in the middle of an otherwise empty grid.
local function Fragment(bot)
	local inventory = Fresh(bot)

	ix.stack.StockAdd(inventory, FILLER, 1, nil, 3, 2)

	return inventory
end

GWH.Check("inventorypanel: plugin, net messages and phrases exist", function(fail)
	local plugin = Plugin("inventorypanel", fail)

	if (!plugin or !Plugin("worldui", fail) or !Plugin("stacking", fail)) then return end

	for _, name in ipairs({"ixInventoryPanelMove", "ixInventoryPanelTidy", "ixInventoryPanelResult"}) do
		if ((util.NetworkStringToID(name) or 0) == 0) then fail("net message " .. name .. " is not registered") end
	end

	for _, name in ipairs({"ixinventorypanelmove", "ixinventorypaneltidy"}) do
		if (!net.Receivers[name]) then fail("no receiver " .. name) end
	end

	local english, spanish = ix.lang.stored.english, ix.lang.stored.spanish
	local count = 0

	for key in pairs(english) do
		if (key:find("^invPanel")) then
			count = count + 1

			if (!spanish or !spanish[key]) then fail("no Spanish phrase " .. key) end
		end
	end

	if (count < 20) then fail("only " .. count .. " English invPanel phrases") end

	for _, entry in ipairs(plugin.fullness) do
		if (!english[entry[2]]) then fail("no phrase for fullness " .. entry[2]) end
	end

	if (!ix.stack.MoveTo or !ix.stack.GetSplitAmounts) then fail("ix.stack.MoveTo or GetSplitAmounts is missing") end
end)

GWH.Check("inventorypanel: Rearrange keeps every item, quantity, data and bag, and packs largest first", function(fail)
	local bot = GWH.Bot()
	local plugin = PanelPlugin()
	if (!bot or !plugin) then return fail("no bot or no plugin") end

	Scoped(function(defer)
		ResetBotFully(bot)
		defer(function() Fresh(bot) end)

		local inventory = Fresh(bot)

		-- a bot's inventory is not saved; this one is, for the length of the check, to see the positions saved
		Lib.Replace(defer, inventory, "noSave", nil)

		-- a scattered grid: fillers, a stack, a suitcase holding a stack, and an "equipped" filler in the corner
		ix.stack.StockAdd(inventory, FILLER, 1, nil, 1, 1)
		ix.stack.StockAdd(inventory, FILLER, 1, nil, 4, 1)
		ix.stack.StockAdd(inventory, SCRAP, 1, {quantity = 3.7}, 2, 3)
		ix.stack.StockAdd(inventory, "suitcase", 1, nil, 3, 2)

		local bag = inventory:HasItem("suitcase")
		local bagInventory = bag and bag:GetInventory()

		if (!bagInventory) then return fail("the suitcase has no inventory") end

		defer(function() for _, v in pairs(bagInventory:GetItems()) do v:Remove() end end)

		NewStack(bagInventory, COAL, 2.5)

		local worn = GiveItem(inventory, FILLER)

		-- put the "equipped" one in the bottom right corner, where packing will not reach
		inventory:Remove(worn:GetID(), true, true)
		ix.stack.StockAdd(inventory, worn:GetID(), nil, nil, inventory.w, inventory.h)
		worn:SetData("equip", true)

		local wornAt = worn.gridX .. "," .. worn.gridY

		local before, bagBefore = Contents(inventory), Contents(bagInventory)
		local positions = Positions(inventory)

		Tidy(bot)

		Expect(fail, "items, data and inventories", Contents(inventory), before)
		Expect(fail, "what the suitcase holds", Contents(bagInventory), bagBefore)
		Expect(fail, "the suitcase keeps its inventory", bag:GetInventory(), bagInventory)
		Expect(fail, "the equipped item stays put", worn.gridX .. "," .. worn.gridY, wornAt)
		Expect(fail, "the largest first", bag.gridX .. "," .. bag.gridY, "1,1")
		Expect(fail, "the scrap kept its quantity", Quantities(inventory, SCRAP), "3.7")

		if (Positions(inventory) == positions) then fail("nothing moved") end

		CheckGrid(fail, inventory, "after a tidy")

		-- the new positions were saved
		for _, item in pairs(inventory:GetItems(true)) do
			local row = sql.QueryRow("SELECT x, y FROM ix_items WHERE item_id = " .. tonumber(item:GetID()))

			if (!row) then
				fail(item.uniqueID .. " has no row")
			elseif (tonumber(row.x) != item.gridX or tonumber(row.y) != item.gridY) then
				fail(item.uniqueID .. " was saved at " .. tostring(row.x) .. "," .. tostring(row.y))
			end
		end

		-- tidy again: already tidy, nothing changes
		local after = Positions(inventory)
		local bSuccess, phrase = plugin:Tidy(bot)

		Expect(fail, "a second tidy", bSuccess, false)
		Expect(fail, "a second tidy says", phrase, "invPanelTidyDone")
		Expect(fail, "a second tidy moves nothing", Positions(inventory), after)

		-- a slot still waiting for its item: refused
		inventory.slots[inventory.w - 1] = inventory.slots[inventory.w - 1] or {}
		local reserved = inventory.slots[inventory.w - 1][inventory.h]

		if (reserved == nil) then
			inventory.slots[inventory.w - 1][inventory.h] = true
			bSuccess, phrase = plugin:Tidy(bot)
			inventory.slots[inventory.w - 1][inventory.h] = nil
			Expect(fail, "a pending slot", phrase, "invPanelTidyBusy")
		end
	end)
end)

GWH.Check("inventorypanel: Rearrange is refused for a dead, tied or downed player, and rate limited", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		defer(function() ResetBotFully(bot) Fresh(bot) end)

		for _, state in ipairs({"tied", "downed", "dead"}) do
			ResetBotFully(bot)

			local inventory = Fragment(bot)
			local positions = Positions(inventory)

			if (state == "tied") then
				Tie(bot)
			elseif (state == "downed") then
				bot:SetRagdolled(true)
			else
				bot:Kill()
			end

			Tidy(bot)
			Expect(fail, "a " .. state .. " player's grid", Positions(inventory), positions)
		end

		ResetBotFully(bot)

		local inventory = Fragment(bot)

		Tidy(bot)

		if (Positions(inventory) == "") then return fail("the filler went missing") end

		local first = Positions(inventory)

		-- scattered again at once: the second request in the interval is dropped
		inventory = Fragment(bot)

		local positions = Positions(inventory)

		if (positions == first) then return fail("could not scatter the grid again") end

		Tidy(bot, true)
		Expect(fail, "a second tidy at once", Positions(inventory), positions)
	end)
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

		-- part of it back: a new stack in the crate
		local mine = ix.stack.GetStacks(own, SCRAP)[1]

		Move(bot, mine, crate, 2.5)
		Expect(fail, "part left: the bot's", Quantities(own, SCRAP), "5.5")
		Expect(fail, "part left: the crate's", Quantities(crate, SCRAP), "2.5")

		-- what the client cannot ask for
		for _, amount in ipairs({0, -1, 0 / 0, math.huge, 0.05, 5.6, 100}) do
			Move(bot, mine, crate, amount)
			Expect(fail, "amount " .. tostring(amount) .. " refused: the bot's", Quantities(own, SCRAP), "5.5")
			Expect(fail, "amount " .. tostring(amount) .. " refused: the crate's", Quantities(crate, SCRAP), "2.5")
		end

		-- the rest, all of it: tops up the crate's stack, which is not full, so it merges
		Move(bot, mine, crate)
		Expect(fail, "all of it: the bot's", Quantities(own, SCRAP), "")
		Expect(fail, "all of it: the crate's", Quantities(crate, SCRAP), "8")
		Expect(fail, "total", Total(), 8)

		-- into a nearly full stack: the stack itself moves, then fills that one
		for _, stack in ipairs(ix.stack.GetStacks(crate, SCRAP)) do stack:Remove() end

		NewStack(crate, SCRAP, 19.5)
		NewStack(own, SCRAP, 4)

		local total = Total()

		Move(bot, ix.stack.GetStacks(own, SCRAP)[1], crate)
		Expect(fail, "filling: the bot's", Quantities(own, SCRAP), "")
		Expect(fail, "filling: the crate's", Quantities(crate, SCRAP), "20,3.5")
		Expect(fail, "filling: total", Total(), total)

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

		-- a plain item, there and back
		local filler = GiveItem(own, FILLER)

		Move(bot, filler, crate)
		Expect(fail, "a filler put in", filler.invID, crate:GetID())
		Move(bot, filler, own)
		Expect(fail, "a filler taken back", filler.invID, own:GetID())
		Move(bot, filler, crate, 1.5)
		Expect(fail, "part of a filler", filler.invID, own:GetID())

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

		timer.Remove("ixStare" .. bot:SteamID64())
		ix.storage.RemoveReceiver(bot, crate)

		-- searched: it moves
		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		Move(bot, filler, crate)
		Expect(fail, "put in once searched", filler.invID, crate:GetID())

		-- out of reach: nothing moves either way
		prop:SetPos(prop:GetPos() + FAR)
		Move(bot, filler, own)
		Expect(fail, "taken from out of reach", filler.invID, crate:GetID())
		prop:SetPos(prop:GetPos() - FAR)

		-- tied, then dead
		Tie(bot)
		Move(bot, filler, own)
		Expect(fail, "taken while tied", filler.invID, crate:GetID())
		ResetBotFully(bot)

		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		bot:Kill()
		Move(bot, filler, own)
		Expect(fail, "taken while dead", filler.invID, crate:GetID())
		ResetBotFully(bot)

		-- respawning put the bot on a spawn point
		prop:SetPos(bot:GetPos() + Vector(50, 0, 10))

		-- closed: nothing moves
		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		Move(bot, filler, own)
		Expect(fail, "taken back while open", filler.invID, own:GetID())
		ReceiveReads("ixStorageClose", bot, {})
		Move(bot, filler, crate)
		Expect(fail, "put in once closed", filler.invID, own:GetID())

		-- a storage never opened, and another player's inventory
		local _, other = Crate(defer, bot)

		Move(bot, filler, other)
		Expect(fail, "put in a crate never opened", filler.invID, own:GetID())

		local target = OtherBot()
		local theirs = target:GetCharacter():GetInventory()

		Move(bot, filler, theirs)
		Expect(fail, "put in another player's inventory", filler.invID, own:GetID())

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

		-- two at once: the second is dropped
		local a, b = GiveItem(own, FILLER), GiveItem(own, FILLER)

		Move(bot, a, crate)
		ReceiveReads("ixInventoryPanelMove", bot, {ReadUInt = {b:GetID(), crate:GetID()}, ReadBool = {false}})
		Expect(fail, "the first of two", a.invID, crate:GetID())
		Expect(fail, "the second of two, at once", b.invID, own:GetID())

		-- someone else's item, out of their inventory
		local theirs = GiveItem(Fresh(target), FILLER)

		Move(bot, theirs, own)
		Expect(fail, "someone else's item", theirs.invID, target:GetCharacter():GetInventory():GetID())

		-- a tied player searched: their things can be taken in reach, not from out of it
		target:SetPos(bot:GetPos() + Vector(40, 0, 0))
		Tie(target)
		Schema:SearchPlayer(bot, target)

		Move(bot, theirs, own)
		Expect(fail, "from a searched player", theirs.invID, own:GetID())

		local back = GiveItem(target:GetCharacter():GetInventory(), FILLER)

		target:SetPos(target:GetPos() + FAR)
		Move(bot, back, own)
		Expect(fail, "from a searched player out of reach", back.invID, target:GetCharacter():GetInventory():GetID())
	end)
end)

GWH.Check("inventorypanel: Rearrange refuses a packing that does not fit, syncs whoever sees the grid, /Menu exists", function(fail)
	local bot = GWH.Bot()
	local plugin = PanelPlugin()
	if (!bot or !plugin) then return fail("no bot or no plugin") end

	Scoped(function(defer)
		ResetBotFully(bot)
		defer(function() Fresh(bot) end)

		local inventory = Fragment(bot)
		local seen = Lib.Capture(bot, function() Tidy(bot) end)

		Expect(fail, "synced", seen.nets:find("ixInventorySync", 1, true) != nil, true)
		Expect(fail, "logged", seen.logs:find("inventoryPanelTidy", 1, true) != nil, true)

		-- an item no packing can place (forced wider than the grid for the check): refused, nothing moves
		inventory = Fragment(bot)

		local item = next(inventory:GetItems(true)) and select(2, next(inventory:GetItems(true)))
		local positions = Positions(inventory)

		Lib.Replace(defer, item, "width", inventory.w + 1)

		local bSuccess, phrase = plugin:Tidy(bot)

		Expect(fail, "no packing", bSuccess, false)
		Expect(fail, "no packing says", phrase, "invPanelTidyNoRoom")
		Expect(fail, "no packing moves nothing", Positions(inventory), positions)

		if (!ix.command.list.menu) then fail("no /Menu command") end
	end)
end)
