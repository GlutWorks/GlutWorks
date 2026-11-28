-- Storage (ix.storage and the ixInventoryMove receiver, our changes to Helix in UPSTREAM.md): who may act on a
-- container, a corpse or a searched player's inventory. Using one takes a finished search and reach to its entity,
-- the server closes it for whoever loses either, and a moved item has to be reachable at both ends. Each check
-- sends what a modified client could send, through the net receivers a real client reaches.

local Lib = GWH.Lib
local Scoped, ReceiveReads, Expect = Lib.Scoped, Lib.ReceiveReads, Lib.Expect
local ResetBot, OtherBot, GiveItem, Fresh, FILLER = Lib.ResetBot, Lib.OtherBot, Lib.GiveItem, Lib.Fresh, Lib.FILLER

-- Far enough from anything to be out of every storage's reach.
local FAR = Vector(3000, 0, 0)

local nextInventoryID = 2100200000

-- A crate frozen beside the bot and a fresh 4x4 inventory for it; both go, with any items in it, when the
-- check ends.
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
		if (inventory.storageInfo) then
			ix.storage.Close(inventory)
		end

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

-- The second bot, standing beside the first, its position and money put back when the check ends.
local function Beside(defer, bot)
	local target = OtherBot()
	local position, money = target:GetPos(), target:GetCharacter():GetMoney()

	ResetBot(target)
	target:SetPos(bot:GetPos() + Vector(40, 0, 0))

	defer(function()
		if (IsValid(target)) then
			target:SetPos(position)

			if (target:GetCharacter()) then
				target:GetCharacter():SetMoney(money)
			end
		end
	end)

	return target
end

-- Closes whatever storage the bot has open, for the end of a check.
local function CloseOpen(defer, bot)
	defer(function()
		if (bot.ixOpenStorage) then
			ix.storage.Close(bot.ixOpenStorage, bot)
		end
	end)
end

-- What the client sends when the player drags an item to (x, y) of `inventory`, with a full allowance of
-- inventory messages (16_inventory.lua checks the allowance itself).
local function Move(bot, item, inventory, x, y)
	bot.ixItemNetTokens = nil
	ReceiveReads("ixInventoryMove", bot, {ReadUInt = {item.gridX, item.gridY, x, y, item.invID, inventory:GetID()}})
end

GWH.Check("storage: nothing in a storage can be used before its search finishes", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBot(bot)
		defer(function() Fresh(bot) end)
		CloseOpen(defer, bot)

		local prop, crate = Crate(defer, bot)
		local own = Fresh(bot)
		local item = GiveItem(own, FILLER)

		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 5})
		defer(function() timer.Remove("ixStare" .. bot:SteamID64()) end)

		Expect(fail, "the crate is the bot's while it searches", ix.storage.InUseBy(crate, bot), true)
		Expect(fail, "access mid-search", crate:OnCheckAccess(bot), false)

		Move(bot, item, crate, 1, 1)
		Expect(fail, "an item put in mid-search stays out", item.invID, own:GetID())
	end)
end)

GWH.Check("storage: out of reach, a storage can't be used and the server closes it", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBot(bot)
		defer(function() Fresh(bot) end)
		CloseOpen(defer, bot)

		local prop, crate = Crate(defer, bot)
		local own = Fresh(bot)
		local item = GiveItem(own, FILLER)

		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		Expect(fail, "access in reach", crate:OnCheckAccess(bot), true)

		prop:SetPos(prop:GetPos() + FAR)
		Expect(fail, "access out of reach", crate:OnCheckAccess(bot), false)

		Move(bot, item, crate, 1, 1)
		Expect(fail, "an item put in from out of reach stays out", item.invID, own:GetID())

		ix.storage.CloseUnreachable()
		Expect(fail, "closed by the server", ix.storage.InUseBy(crate, bot), false)
		Expect(fail, "nothing left open", bot.ixOpenStorage, nil)
	end)
end)

GWH.Check("storage: opening a second storage closes the first", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBot(bot)
		CloseOpen(defer, bot)

		local first, firstCrate = Crate(defer, bot)
		local second, secondCrate = Crate(defer, bot)

		ix.storage.Open(bot, firstCrate, {entity = first, name = "first", searchTime = 0})
		ix.storage.Open(bot, secondCrate, {entity = second, name = "second", searchTime = 0})

		Expect(fail, "access to the first", firstCrate:OnCheckAccess(bot), false)
		Expect(fail, "access to the second", secondCrate:OnCheckAccess(bot), true)
	end)
end)

GWH.Check("storage: a searched player's money can't be taken out of reach", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end
	if (!Schema.SearchPlayer) then return fail("the schema has no SearchPlayer") end

	Scoped(function(defer)
		ResetBot(bot)
		CloseOpen(defer, bot)

		local botMoney = bot:GetCharacter():GetMoney()
		defer(function() bot:GetCharacter():SetMoney(botMoney) end)

		local target = Beside(defer, bot)
		local character = target:GetCharacter()
		local invID = character:GetInventory():GetID()

		character:SetMoney(100)
		Schema:SearchPlayer(bot, target)

		bot.ixStorageMoneyTimer = nil
		ReceiveReads("ixStorageMoneyTake", bot, {ReadUInt = {invID, 10}})
		Expect(fail, "money left after taking 10 in reach", character:GetMoney(), 90)

		target:SetPos(target:GetPos() + FAR)
		bot.ixStorageMoneyTimer = nil
		ReceiveReads("ixStorageMoneyTake", bot, {ReadUInt = {invID, 50}})
		Expect(fail, "money left after trying from out of reach", character:GetMoney(), 90)
	end)
end)

GWH.Check("storage: a searched player keeps their own inventory", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end
	if (!Schema.SearchPlayer) then return fail("the schema has no SearchPlayer") end

	Scoped(function(defer)
		ResetBot(bot)
		CloseOpen(defer, bot)

		local target = Beside(defer, bot)
		local inventory = target:GetCharacter():GetInventory()

		Schema:SearchPlayer(bot, target)
		target:SetPos(target:GetPos() + FAR)

		Expect(fail, "the searched player's own access", inventory:OnCheckAccess(target), true)
		Expect(fail, "the searcher's access from out of reach", inventory:OnCheckAccess(bot), false)

		ix.storage.CloseUnreachable()
		Expect(fail, "the searcher, closed by the server", inventory.receivers[bot], nil)
		Expect(fail, "the searched player, still a receiver", inventory.receivers[target], true)

		target:SetPos(bot:GetPos() + Vector(40, 0, 0))
		Schema:SearchPlayer(bot, target)
		ix.storage.Close(inventory)
		Expect(fail, "the searcher, after Close", inventory.receivers[bot], nil)
		Expect(fail, "the searched player, after Close", inventory.receivers[target], true)
	end)
end)

GWH.Check("storage: an item can't be moved into an inventory out of the player's reach", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBot(bot)
		defer(function() Fresh(bot) end)

		local own = Fresh(bot)

		-- another player's inventory, never opened
		local target = Beside(defer, bot)
		local theirs = target:GetCharacter():GetInventory()
		local x, y = theirs:FindEmptySlot(1, 1)

		if (!x) then return fail("the second bot's inventory is full") end

		local item = GiveItem(own, FILLER)
		defer(function() if (ix.item.instances[item:GetID()]) then item:Remove() end end)

		Move(bot, item, theirs, x, y)
		Expect(fail, "an item put in another player's inventory stays out", item.invID, own:GetID())

		-- the bot's own bag, dropped: it keeps its owner but not its receivers
		ix.stack.StockAdd(own, "suitcase", 1)

		local bag = own:HasItem("suitcase")
		local bagInventory = bag and bag:GetInventory()

		if (!bagInventory) then return fail("the suitcase has no inventory") end

		bag:Transfer(nil, nil, nil, bot)
		defer(function()
			for _, v in pairs(bagInventory:GetItems()) do v:Remove() end

			local entity = bag:GetEntity()
			if (IsValid(entity)) then entity:Remove() end
		end)

		Move(bot, item, bagInventory, 1, 1)
		Expect(fail, "an item put in a dropped bag stays out", item.invID, own:GetID())
	end)
end)

GWH.Check("storage: moves the player can reach still work", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBot(bot)
		defer(function() Fresh(bot) end)
		CloseOpen(defer, bot)

		local prop, crate = Crate(defer, bot)
		local own = Fresh(bot)
		local item = GiveItem(own, FILLER)
		local x, y = item.gridX, item.gridY
		local toX, toY = x == 1 and 2 or 1, y

		Move(bot, item, own, toX, toY)
		Expect(fail, "moved within the bot's own inventory", item.gridX .. "," .. item.gridY, toX .. "," .. toY)

		ix.stack.StockAdd(own, "suitcase", 1)

		local bag = own:HasItem("suitcase")
		local bagInventory = bag and bag:GetInventory()

		if (!bagInventory) then return fail("the suitcase has no inventory") end

		Move(bot, item, bagInventory, 1, 1)
		Expect(fail, "into the carried bag", item.invID, bagInventory:GetID())

		local backX, backY = own:FindEmptySlot(1, 1)
		Move(bot, item, own, backX, backY)
		Expect(fail, "back out of the carried bag", item.invID, own:GetID())

		ix.storage.Open(bot, crate, {entity = prop, name = "crate", searchTime = 0})
		Move(bot, item, crate, 1, 1)
		Expect(fail, "into an open crate in reach", item.invID, crate:GetID())

		backX, backY = own:FindEmptySlot(1, 1)
		Move(bot, item, own, backX, backY)
		Expect(fail, "back out of the crate", item.invID, own:GetID())
	end)
end)
