-- Vendor panel (vendorpanel, over Helix's vendor plugin): the plugin, its net message and phrases; using a vendor
-- still opens the trade on the server (receivers, ixVendorOpen) and now also sends whether the vendor keeps
-- money; a vendor that refuses the player still refuses; a trade the panel asks for (ixVendorTrade) still buys and
-- is refused when the player cannot afford it; closing (ixVendorClose) leaves the vendor free; the vendor editor
-- still opens for staff and not for others. The panel itself is client-only and is judged in a play session.
-- Trades of stacks are in 40_stacking.lua.

local Lib = GWH.Lib
local S = Lib.NewS()
local Scoped, Plugin, Capture, Expect, Fresh = Lib.Scoped, Lib.Plugin, Lib.Capture, Lib.Expect, Lib.Fresh
local Receive = S.Net

local FILLER = Lib.FILLER

-- A vendor beside the bot that sells and buys FILLER for 8, with stock, and keeps money.
local function NewVendor(defer, bot)
	local vendor = ents.Create("ix_vendor")
	vendor:SetPos(bot:GetPos() + Vector(50, 0, 0))
	vendor:Spawn()
	vendor.items[FILLER] = {[VENDOR_PRICE] = 8, [VENDOR_MODE] = VENDOR_SELLANDBUY, [VENDOR_STOCK] = 3, [VENDOR_MAXSTOCK] = 5}
	vendor.money = 100

	defer(function()
		if (IsValid(vendor)) then vendor:Remove() end

		bot.ixVendor = nil
		timer.Simple(0, function()
			local plugin = ix.plugin.list.vendor
			if (plugin) then plugin:SaveData() end
		end)
	end)

	return vendor
end

local function IsReceiver(vendor, client)
	for _, v in ipairs(vendor.receivers or {}) do
		if (v == client) then return true end
	end

	return false
end

GWH.Check("vendorpanel: plugin, net message and phrases exist", function(fail)
	if (!Plugin("vendorpanel", fail) or !Plugin("vendor", fail)) then return end

	if (!util.NetworkStringToID("ixVendorPanelMoney") or util.NetworkStringToID("ixVendorPanelMoney") == 0) then
		fail("net message ixVendorPanelMoney is not registered")
	end

	local english, spanish = ix.lang.stored.english, ix.lang.stored.spanish

	for _, key in ipairs({"vendorPanelYou", "vendorPanelThey", "vendorPanelSelling", "vendorPanelBuying",
		"vendorPanelNothingSold", "vendorPanelNothingBought", "vendorPanelStock", "vendorPanelSoldOut", "vendorPanelBuyRow",
		"vendorPanelSellRow"}) do
		if (!english[key]) then fail("no English phrase " .. key) end
		if (!spanish or !spanish[key]) then fail("no Spanish phrase " .. key) end
	end

	-- the trade unit is known to the client as well, to label the rows
	if (!ix.stack or !ix.stack.GetTradeAmount) then fail("no ix.stack.GetTradeAmount") end
end)

GWH.Check("vendorpanel: using a vendor opens the trade, trades still go through, and closing frees it", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end
	if (!ix.plugin.list.vendor) then return {skipped = "vendor plugin not loaded"} end

	Scoped(function(defer)
		local character = bot:GetCharacter()
		local money = character:GetMoney()
		defer(function() character:SetMoney(money) Fresh(bot) end)

		local inventory = Fresh(bot)
		local vendor = NewVendor(defer, bot)

		-- Use: the player is a receiver and is told whether the vendor keeps money
		local seen = Capture(bot, function()
			vendor:Use(bot, bot, USE_ON, 1)
		end)

		Expect(fail, "use: opened", seen.nets:find("ixVendorOpen", 1, true) != nil, true)
		Expect(fail, "use: money sent", seen.nets:find("ixVendorPanelMoney", 1, true) != nil, true)
		Expect(fail, "use: receiver", IsReceiver(vendor, bot), true)
		Expect(fail, "use: trading with it", bot.ixVendor, vendor)

		-- buying one, as a panel row sends it
		character:SetMoney(20)
		bot.ixVendorTry = 0
		seen = Capture(bot, function() Receive("ixVendorTrade", bot, {FILLER, false}) end)
		Expect(fail, "buy: notice", seen.notices, "businessPurchase")
		Expect(fail, "buy: paid", character:GetMoney(), 12)
		Expect(fail, "buy: got one", #inventory:GetItemsByUniqueID(FILLER), 1)
		Expect(fail, "buy: stock", vendor:GetStock(FILLER), 2)

		-- selling it back
		bot.ixVendorTry = 0
		seen = Capture(bot, function() Receive("ixVendorTrade", bot, {FILLER, true}) end)
		Expect(fail, "sell: notice", seen.notices, "businessSell")
		Expect(fail, "sell: gone", #inventory:GetItemsByUniqueID(FILLER), 0)
		Expect(fail, "sell: paid", character:GetMoney(), 16)

		-- the player cannot afford it: refused, nothing changes
		character:SetMoney(3)
		bot.ixVendorTry = 0
		seen = Capture(bot, function() Receive("ixVendorTrade", bot, {FILLER, false}) end)
		Expect(fail, "cannot afford: notice", seen.notices, "canNotAfford")
		Expect(fail, "cannot afford: money", character:GetMoney(), 3)
		Expect(fail, "cannot afford: nothing given", #inventory:GetItemsByUniqueID(FILLER), 0)

		-- the vendor cannot afford what the player sells
		ix.stack.StockAdd(inventory, FILLER, 1)
		vendor.money = 1
		bot.ixVendorTry = 0
		seen = Capture(bot, function() Receive("ixVendorTrade", bot, {FILLER, true}) end)
		Expect(fail, "vendor cannot afford: notice", seen.notices, "vendorNoMoney")
		Expect(fail, "vendor cannot afford: kept", #inventory:GetItemsByUniqueID(FILLER), 1)

		-- closing, which the panel sends whenever it closes
		Receive("ixVendorClose", bot, {})
		Expect(fail, "close: no longer a receiver", IsReceiver(vendor, bot), false)
		Expect(fail, "close: not trading", bot.ixVendor, nil)

		-- and no trade goes through once closed
		character:SetMoney(100)
		vendor.money = 100
		bot.ixVendorTry = 0
		Receive("ixVendorTrade", bot, {FILLER, false})
		Expect(fail, "after close: nothing bought", character:GetMoney(), 100)

		-- a vendor for another faction still refuses to open
		vendor.factions = {gwh_no_such_faction = true}
		seen = Capture(bot, function() vendor:Use(bot, bot, USE_ON, 1) end)
		Expect(fail, "refused: not opened", seen.nets:find("ixVendorOpen", 1, true) == nil, true)
		Expect(fail, "refused: told why", seen.notices, "vendorNoTrade")
		Expect(fail, "refused: not a receiver", IsReceiver(vendor, bot), false)
	end)
end)

GWH.Check("vendorpanel: the vendor editor still opens for staff only", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local property = properties.List and properties.List.vendor_edit
	if (!property) then return fail("no vendor_edit property") end

	Scoped(function(defer)
		local usergroup = bot:GetUserGroup()
		defer(function() bot:SetUserGroup(usergroup) end)

		local vendor = NewVendor(defer, bot)

		local function Open()
			bot.ixVendor = nil

			return Capture(bot, function()
				Lib.Scoped(function(deferRead)
					Lib.Replace(deferRead, net, "ReadEntity", function() return vendor end)
					property:Receive(0, bot)
				end)
			end)
		end

		bot:SetUserGroup("user")
		Expect(fail, "player: no editor", Open().nets:find("ixVendorEditor", 1, true) == nil, true)

		bot:SetUserGroup("superadmin")
		Expect(fail, "staff: editor", Open().nets:find("ixVendorEditor", 1, true) != nil, true)
		Expect(fail, "staff: editing this vendor", bot.ixVendor, vendor)

		Receive("ixVendorClose", bot, {})
	end)
end)

GWH.Check("vendorpanel: the vendor's money reaches open panels in full whenever it changes", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end
	if (!ix.plugin.list.vendor) then return {skipped = "vendor plugin not loaded"} end

	Scoped(function(defer)
		local character = bot:GetCharacter()
		local money = character:GetMoney()
		defer(function() character:SetMoney(money) Fresh(bot) end)

		local inventory = Fresh(bot)
		local vendor = NewVendor(defer, bot)
		vendor.money = 70000

		vendor:Use(bot, bot, USE_ON, 1)

		-- what ixVendorPanelMoney carries, read back as the client reads it
		local sent = {}

		local function Watch(fn)
			table.Empty(sent)

			Lib.Scoped(function(deferNet)
				local start, writeBool, writeUInt = net.Start, net.WriteBool, net.WriteUInt
				local current

				Lib.Replace(deferNet, net, "Start", function(name, ...)
					current = name
					return start(name, ...)
				end)
				Lib.Replace(deferNet, net, "WriteBool", function(value, ...)
					if (current == "ixVendorPanelMoney") then sent.bTracks = value end
					return writeBool(value, ...)
				end)
				Lib.Replace(deferNet, net, "WriteUInt", function(value, bits, ...)
					if (current == "ixVendorPanelMoney" and bits == 32) then sent.money = value end
					return writeUInt(value, bits, ...)
				end)

				fn()
			end)
		end

		-- the player sells one: the vendor pays 4 and the panel is told 69996, not that modulo 65536
		ix.stack.StockAdd(inventory, FILLER, 1)
		bot.ixVendorTry = 0
		Watch(function() Receive("ixVendorTrade", bot, {FILLER, true}) end)
		Expect(fail, "after a sale: vendor money", vendor.money, 69996)
		Expect(fail, "after a sale: sent in full", sent.money, 69996)
		Expect(fail, "after a sale: keeps money", sent.bTracks, true)

		-- exactly 65535 is an amount, not "keeps no money"
		Watch(function() vendor:SetMoney(65535) end)
		Expect(fail, "65535: sent", sent.money, 65535)
		Expect(fail, "65535: keeps money", sent.bTracks, true)

		-- a vendor that keeps no money says so
		Watch(function() vendor:SetMoney(nil) end)
		Expect(fail, "no money kept", sent.bTracks, false)

		Receive("ixVendorClose", bot, {})
	end)
end)
