-- City economy (cityeconomy): ix.city treasury and stockpile seeding, taking without overdrawing,
-- PayPlayer, stock quantities and unknown items, saving and loading, the salary hook against an
-- empty, short and funded treasury, ration tokens paid from the treasury, and /CityFunds.
-- Every check puts the city state, its saved data and the config back.

local Lib = GWH.Lib
local Plugin, WithConfig, Scoped, Capture, Expect, GiveItem = Lib.Plugin, Lib.WithConfig, Lib.Scoped, Lib.Capture, Lib.Expect, Lib.GiveItem
local RemoveAll, Fresh = Lib.RemoveAll, Lib.Fresh

local S = Lib.NewS()

local function Near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 0.001)
end

-- Puts the treasury, the stockpile and their saved data back when the check ends, and stops a
-- queued save from writing the check's state after it.
local function KeepCity(defer, plugin)
	local treasury, stock = plugin.treasury, table.Copy(plugin.stock or {})

	defer(function()
		timer.Remove("ixCityEconomySave")
		plugin.treasury = treasury
		plugin.stock = stock
		plugin:SaveData()
	end)
end

local function KeepMoney(defer, bot)
	local character = bot:GetCharacter()
	local money = character:GetMoney()

	defer(function() character:SetMoney(money) end)

	return character
end

GWH.Check("cityeconomy: a fresh city is seeded from config and PLUGIN.seedStock", function(fail)
	local plugin = Plugin("cityeconomy", fail)
	if (!plugin or !ix.city) then return fail("no plugin or ix.city") end

	return Scoped(function(defer)
		KeepCity(defer, plugin)

		WithConfig({cityEconomyEnabled = true, cityTreasurySeed = 1234}, function()
			plugin:SetData({})
			plugin.treasury = 999999
			plugin.stock = {metal_scrap = 1}
			plugin:LoadData()

			Expect(fail, "seeded treasury", ix.city.GetTreasury(), 1234)

			local seeded = 0

			for uniqueID, quantity in pairs(plugin.seedStock) do
				seeded = seeded + 1

				if (!ix.item.list[uniqueID]) then fail("seed stock names unknown item " .. uniqueID) end
				if (!Near(ix.city.GetStock(uniqueID), quantity)) then
					fail("seed stock " .. uniqueID .. " is " .. ix.city.GetStock(uniqueID) .. ", expected " .. quantity)
				end
			end

			if (table.Count(plugin.stock) != seeded) then fail("seeded stock holds more than PLUGIN.seedStock") end
		end)
	end)
end)

GWH.Check("cityeconomy: the treasury never overdraws and refuses bad amounts", function(fail)
	local plugin = Plugin("cityeconomy", fail)
	if (!plugin) then return end

	return Scoped(function(defer)
		KeepCity(defer, plugin)

		plugin.treasury = 100
		plugin.stock = {}

		Expect(fail, "treasury", ix.city.GetTreasury(), 100)
		Expect(fail, "take 30", ix.city.TakeTreasury(30), 30)
		Expect(fail, "treasury after taking", ix.city.GetTreasury(), 70)
		Expect(fail, "take more than there is", ix.city.TakeTreasury(1000), 70)
		Expect(fail, "treasury emptied, not negative", ix.city.GetTreasury(), 0)
		Expect(fail, "take from empty", ix.city.TakeTreasury(10), 0)

		Expect(fail, "add", ix.city.AddTreasury(25), true)
		Expect(fail, "treasury after adding", ix.city.GetTreasury(), 25)
		Expect(fail, "add floors to whole tokens", ix.city.AddTreasury(2.9), true)
		Expect(fail, "treasury after a fractional add", ix.city.GetTreasury(), 27)

		Expect(fail, "add a negative amount", ix.city.AddTreasury(-5), false)
		Expect(fail, "add a string", ix.city.AddTreasury("5"), false)
		Expect(fail, "add infinity", ix.city.AddTreasury(math.huge), false)
		Expect(fail, "take a negative amount", ix.city.TakeTreasury(-1), 0)
		Expect(fail, "treasury after refused amounts", ix.city.GetTreasury(), 27)
	end)
end)

GWH.Check("cityeconomy: PayPlayer pays only what the treasury holds", function(fail)
	local plugin = Plugin("cityeconomy", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	return Scoped(function(defer)
		KeepCity(defer, plugin)

		local character = KeepMoney(defer, bot)
		character:SetMoney(1000)
		plugin.stock = {}

		WithConfig({cityEconomyEnabled = true}, function()
			plugin.treasury = 15
			Expect(fail, "paid from a short treasury", ix.city.PayPlayer(bot, 20, "test"), 15)
			Expect(fail, "money after a short payment", character:GetMoney(), 1015)
			Expect(fail, "treasury debited", ix.city.GetTreasury(), 0)

			Expect(fail, "paid from an empty treasury", ix.city.PayPlayer(bot, 10, "test"), 0)
			Expect(fail, "money after no payment", character:GetMoney(), 1015)

			plugin.treasury = 100
			Expect(fail, "paid in full", ix.city.PayPlayer(bot, 30, "test"), 30)
			Expect(fail, "money after a full payment", character:GetMoney(), 1045)
			Expect(fail, "treasury after a full payment", ix.city.GetTreasury(), 70)

			Expect(fail, "a negative payment", ix.city.PayPlayer(bot, -5, "test"), 0)
			Expect(fail, "a payment to nobody", ix.city.PayPlayer(nil, 5, "test"), 0)
			Expect(fail, "treasury after refused payments", ix.city.GetTreasury(), 70)
		end)

		WithConfig({cityEconomyEnabled = false}, function()
			Expect(fail, "paid while disabled", ix.city.PayPlayer(bot, 30, "test"), 30)
			Expect(fail, "money while disabled", character:GetMoney(), 1075)
			Expect(fail, "treasury not debited while disabled", ix.city.GetTreasury(), 70)
		end)
	end)
end)

GWH.Check("cityeconomy: stock quantities move fractionally and unknown items are refused", function(fail)
	local plugin = Plugin("cityeconomy", fail)
	if (!plugin) then return end

	return Scoped(function(defer)
		KeepCity(defer, plugin)

		plugin.treasury = 0
		plugin.stock = {}

		Expect(fail, "add scrap", ix.city.AddStock("metal_scrap", 2.5), true)
		Expect(fail, "add more scrap", ix.city.AddStock("metal_scrap", 1.5), true)

		if (!Near(ix.city.GetStock("metal_scrap"), 4)) then fail("scrap is " .. ix.city.GetStock("metal_scrap") .. ", expected 4") end
		if (!Near(ix.city.TakeStock("metal_scrap", 1.25), 1.25)) then fail("taking 1.25 scrap did not give 1.25") end
		if (!Near(ix.city.GetStock("metal_scrap"), 2.75)) then fail("scrap left is " .. ix.city.GetStock("metal_scrap") .. ", expected 2.75") end
		if (!Near(ix.city.TakeStock("metal_scrap", 99), 2.75)) then fail("taking more scrap than there is overdrew") end

		Expect(fail, "scrap emptied", ix.city.GetStock("metal_scrap"), 0)
		Expect(fail, "an emptied stock entry is dropped", plugin.stock.metal_scrap, nil)

		Expect(fail, "add an unknown item", ix.city.AddStock("does_not_exist", 5), false)
		Expect(fail, "take an unknown item", ix.city.TakeStock("does_not_exist", 5), 0)
		Expect(fail, "stock of an unknown item", ix.city.GetStock("does_not_exist"), 0)
		Expect(fail, "an unknown item left no entry", plugin.stock.does_not_exist, nil)

		Expect(fail, "add a negative quantity", ix.city.AddStock("supplements", -1), false)
		Expect(fail, "add a string quantity", ix.city.AddStock("supplements", "3"), false)
		Expect(fail, "take a negative quantity", ix.city.TakeStock("supplements", -1), 0)
		Expect(fail, "stock with no item", ix.city.GetStock(nil), 0)

		Expect(fail, "add supplements", ix.city.AddStock("supplements", 3), true)
		Expect(fail, "supplements stocked", ix.city.GetStock("supplements"), 3)
	end)
end)

GWH.Check("cityeconomy: the treasury and stockpile survive saving and loading", function(fail)
	local plugin = Plugin("cityeconomy", fail)
	if (!plugin) then return end

	return Scoped(function(defer)
		KeepCity(defer, plugin)

		plugin.treasury = 777
		plugin.stock = {metal_scrap = 3.5, water = 7}
		plugin:SaveData()

		plugin.treasury = 0
		plugin.stock = {}
		plugin:LoadData()

		Expect(fail, "loaded treasury", ix.city.GetTreasury(), 777)

		if (!Near(ix.city.GetStock("metal_scrap"), 3.5)) then fail("loaded scrap is " .. ix.city.GetStock("metal_scrap")) end

		Expect(fail, "loaded water", ix.city.GetStock("water"), 7)

		-- a saved empty treasury is a real city, not a fresh one to seed again
		WithConfig({cityTreasurySeed = 5000}, function()
			plugin.treasury = 0
			plugin.stock = {}
			plugin:SaveData()
			plugin:LoadData()
			Expect(fail, "a saved empty treasury is not reseeded", ix.city.GetTreasury(), 0)
		end)
	end)
end)

GWH.Check("cityeconomy: salaries are withdrawn from the treasury", function(fail)
	local plugin = Plugin("cityeconomy", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	return Scoped(function(defer)
		KeepCity(defer, plugin)

		local faction = {pay = 40}
		plugin.stock = {}

		WithConfig({cityEconomyEnabled = true}, function()
			plugin.treasury = 0
			Expect(fail, "no salary from an empty treasury", hook.Run("CanPlayerEarnSalary", bot, faction), false)
			Expect(fail, "salary amount from an empty treasury", hook.Run("GetSalaryAmount", bot, faction), 0)
			Expect(fail, "treasury after an unpaid salary", ix.city.GetTreasury(), 0)

			plugin.treasury = 15
			Expect(fail, "a part salary may be earned", hook.Run("CanPlayerEarnSalary", bot, faction), nil)
			Expect(fail, "a part salary", hook.Run("GetSalaryAmount", bot, faction), 15)
			Expect(fail, "treasury after a part salary", ix.city.GetTreasury(), 0)

			plugin.treasury = 100
			Expect(fail, "a full salary", hook.Run("GetSalaryAmount", bot, faction), 40)
			Expect(fail, "treasury after a full salary", ix.city.GetTreasury(), 60)
		end)

		WithConfig({cityEconomyEnabled = false}, function()
			plugin.treasury = 100
			Expect(fail, "salary while disabled is Helix's", hook.Run("GetSalaryAmount", bot, faction), nil)
			Expect(fail, "earning while disabled is Helix's", hook.Run("CanPlayerEarnSalary", bot, faction), nil)
			Expect(fail, "treasury while disabled", ix.city.GetTreasury(), 100)
		end)
	end)
end)

GWH.Check("cityeconomy: opening a ration pays its tokens from the treasury", function(fail)
	local plugin = Plugin("cityeconomy", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	return Scoped(function(defer)
		KeepCity(defer, plugin)

		local character = KeepMoney(defer, bot)
		local inventory = Fresh(bot)

		defer(function()
			RemoveAll(inventory, "ration")
			RemoveAll(inventory, "supplements")
			RemoveAll(inventory, "water")
		end)

		plugin.stock = {}

		WithConfig({cityEconomyEnabled = true, rationTokens = 20}, function()
			character:SetMoney(1000)
			plugin.treasury = 12

			local ration = GiveItem(inventory, "ration")
			ix.item.PerformInventoryAction(bot, "Open", ration:GetID(), inventory:GetID())

			Expect(fail, "money from a ration against a short treasury", character:GetMoney(), 1012)
			Expect(fail, "treasury after the ration", ix.city.GetTreasury(), 0)
			Expect(fail, "supplements from the ration", inventory:GetItemCount("supplements"), 1)
			Expect(fail, "water from the ration", inventory:GetItemCount("water"), 1)
		end)

		WithConfig({cityEconomyEnabled = false, rationTokens = 20}, function()
			plugin.treasury = 5

			local ration = GiveItem(inventory, "ration")
			ix.item.PerformInventoryAction(bot, "Open", ration:GetID(), inventory:GetID())

			Expect(fail, "money from a ration while disabled", character:GetMoney(), 1032)
			Expect(fail, "treasury after a ration while disabled", ix.city.GetTreasury(), 5)
		end)
	end)
end)

GWH.Check("cityeconomy: /CityFunds shows the city to staff and tops it up", function(fail)
	local plugin = Plugin("cityeconomy", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	return Scoped(function(defer)
		KeepCity(defer, plugin)

		local group = bot:GetUserGroup()
		defer(function() bot:SetUserGroup(group) end)

		WithConfig({cityEconomyEnabled = true}, function()
			plugin.treasury = 100
			plugin.stock = {metal_scrap = 2.5}

			bot:SetUserGroup("user")
			S.Command(bot, "/CityFunds add 50")
			Expect(fail, "treasury after a user's /CityFunds", ix.city.GetTreasury(), 100)

			bot:SetUserGroup("superadmin")

			local seen = Capture(bot, function() S.Command(bot, "/CityFunds") end)

			if (!string.find(seen.texts, "City treasury: 100 tokens.", 1, true)) then fail("/CityFunds said: " .. seen.texts) end
			if (!string.find(seen.texts, "Stock metal_scrap: 2.5.", 1, true)) then fail("/CityFunds stock said: " .. seen.texts) end

			S.Command(bot, "/CityFunds add 50")
			Expect(fail, "treasury after /CityFunds add", ix.city.GetTreasury(), 150)

			S.Command(bot, "/CityFunds stock water 4")
			Expect(fail, "water after /CityFunds stock", ix.city.GetStock("water"), 4)

			S.Command(bot, "/CityFunds stock does_not_exist 5")
			Expect(fail, "an unknown item stocked by command", ix.city.GetStock("does_not_exist"), 0)
			Expect(fail, "treasury after refused commands", ix.city.GetTreasury(), 150)
		end)
	end)
end)
