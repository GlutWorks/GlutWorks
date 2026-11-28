-- Inventory placement (Inventory:CanItemFit, Inventory:Add and the ixInventoryMove and ixInventoryAction receivers,
-- our changes to Helix in UPSTREAM.md): an item sits wholly inside its grid, a position a caller or the client gives
-- is checked like one the server finds, and a client's inventory messages are rate limited.

local Lib = GWH.Lib
local Scoped, ReceiveReads, Expect = Lib.Scoped, Lib.ReceiveReads, Lib.Expect
local ResetBot, GiveItem, Fresh, FILLER = Lib.ResetBot, Lib.GiveItem, Lib.Fresh, Lib.FILLER

-- What the client sends when the player drags an item to (x, y) of `inventory`. With `bKeepAllowance` the bot's
-- allowance of inventory messages is left as it is; otherwise it starts full.
local function Move(bot, item, inventory, x, y, bKeepAllowance)
	if (!bKeepAllowance) then
		bot.ixItemNetTokens = nil
	end

	ReceiveReads("ixInventoryMove", bot, {ReadUInt = {item.gridX, item.gridY, x, y, item.invID, inventory:GetID()}})
end

local function Where(item)
	return item.gridX .. "," .. item.gridY
end

GWH.Check("inventory: an item can't be placed outside its grid", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBot(bot)
		defer(function() Fresh(bot) end)

		local own = Fresh(bot)
		local w, h = own.w, own.h

		Expect(fail, "1,1 in an empty grid", own:CanItemFit(1, 1, 1, 1), true)
		Expect(fail, "the last cell", own:CanItemFit(w, h, 1, 1), true)
		Expect(fail, "column 0", own:CanItemFit(0, 1, 1, 1), false)
		Expect(fail, "row 0", own:CanItemFit(1, 0, 1, 1), false)
		Expect(fail, "past the last row", own:CanItemFit(1, h + 1, 1, 1), false)
		Expect(fail, "a 1x2 item hanging off the bottom", own:CanItemFit(1, h, 1, 2), false)
		Expect(fail, "a 2x1 item hanging off the side", own:CanItemFit(w, 1, 2, 1), false)
		Expect(fail, "half a cell", own:CanItemFit(1.5, 1, 1, 1), false)

		local item = GiveItem(own, FILLER)
		local before = Where(item)

		Move(bot, item, own, 1, h + 1)
		Expect(fail, "moved past the last row", Where(item), before)

		Move(bot, item, own, 0, 1)
		Expect(fail, "moved to column 0", Where(item), before)
	end)
end)

GWH.Check("inventory: a position given to Add is checked like a found one", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBot(bot)
		defer(function() Fresh(bot) end)

		local own = Fresh(bot)
		local mine = GiveItem(own, FILLER)
		local x, y = mine.gridX, mine.gridY

		local other = ix.inventory.Create(2, 2, 2100300001)
		defer(function()
			for _, v in pairs(other:GetItems()) do v:Remove() end
			ix.item.inventories[other:GetID()] = nil
		end)

		local theirs = GiveItem(other, FILLER)
		local bMoved = theirs:Transfer(own:GetID(), x, y, bot)

		Expect(fail, "transferred onto an occupied cell", bMoved == true, false)
		Expect(fail, "the cell still holds", own:GetItemAt(x, y), mine)
		Expect(fail, "the other item stayed", theirs.invID, other:GetID())

		local free = own:GetItemAt(x == 1 and 2 or 1, y) == nil and (x == 1 and 2 or 1)

		if (free) then
			Expect(fail, "transferred onto a free cell", theirs:Transfer(own:GetID(), free, y, bot) == true, true)
		end
	end)
end)

GWH.Check("inventory: a client's inventory messages are rate limited", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBot(bot)
		defer(function()
			bot.ixItemNetTokens, bot.ixItemNetTime = nil, nil
			Fresh(bot)
		end)

		local own = Fresh(bot)
		local item = GiveItem(own, FILLER)
		local targets = {}

		for y = 1, own.h do
			for x = 1, own.w do
				if (x != item.gridX or y != item.gridY) then
					targets[#targets + 1] = {x, y}
				end
			end
		end

		local burst = ix.item.netBurst or 10
		local sent = burst + 5

		if (#targets < sent) then
			return fail("the inventory has fewer than " .. sent .. " free cells")
		end

		-- all in one tick: the first `burst` are handled, the rest refused
		bot.ixItemNetTokens = nil

		for i = 1, sent do
			Move(bot, item, own, targets[i][1], targets[i][2], true)
		end

		Expect(fail, "where the item is after " .. sent .. " moves at once", Where(item),
			targets[burst][1] .. "," .. targets[burst][2])

		-- a second later the allowance has refilled
		bot.ixItemNetTime = CurTime() - 1
		Move(bot, item, own, targets[sent][1], targets[sent][2], true)
		Expect(fail, "a move a second later", Where(item), targets[sent][1] .. "," .. targets[sent][2])
	end)
end)
