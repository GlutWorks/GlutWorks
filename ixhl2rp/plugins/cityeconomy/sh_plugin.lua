local PLUGIN = PLUGIN

PLUGIN.name = "City Economy"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "The city treasury and stockpile (ix.city): faction salaries and ration tokens are paid from the treasury, and citizens deliver wanted goods at CWU terminals."

ix.config.Add("cityEconomyEnabled", true, "Whether faction salaries and ration tokens are paid from the city treasury. Off pays them in full without debiting it, as before.", nil, {
	category = "economy"
})

ix.config.Add("cityTreasurySeed", 5000, "Tokens in the city treasury the first time it is created, before any saved treasury exists.", nil, {
	data = {min = 0, max = 1000000},
	category = "economy"
})

ix.config.Add("cityExportLevy", 0.3, "Fraction of off-map export earnings the Combine keeps before the rest reaches the city treasury.", nil, {
	data = {min = 0, max = 0.95, decimals = 2},
	category = "economy"
})

-- How close a player must be to a CWU terminal to use it (the worldui reach and the server's check).
PLUGIN.reach = 128

-- Goods the city buys from citizens at a CWU terminal: item uniqueID -> how much stock it wants
-- (target) and what it pays per unit delivered (pay, tokens). Prices sit below the items' own
-- ITEM.price (4 for the scraps, 15 for gold ore): the city buys cheap, and a ration is 20 tokens.
PLUGIN.wanted = {
	metal_scrap = {target = 40, pay = 2},
	wooden_scrap = {target = 40, pay = 2},
	plastic_scrap = {target = 40, pay = 2},
	coal_ore = {target = 20, pay = 2},
	copper_ore = {target = 20, pay = 2},
	iron_ore = {target = 20, pay = 2},
	tin_ore = {target = 20, pay = 2},
	gold_ore = {target = 10, pay = 5},
	supplements = {target = 50, pay = 3},
	water = {target = 50, pay = 2}
}

-- What one unit of a good earns sold off-map (tokens, before the export levy). Each export price
-- beats its delivery pay by more than the default levy, so buying low and exporting surplus profits.
PLUGIN.exportPrices = {
	metal_scrap = 3,
	wooden_scrap = 3,
	plastic_scrap = 3,
	coal_ore = 3,
	copper_ore = 3,
	iron_ore = 3,
	tin_ore = 3,
	gold_ore = 8,
	supplements = 5,
	water = 3
}

-- Goods the city cannot make and buys into stock off-map: item uniqueID -> tokens per unit,
-- below the items' own ITEM.price (18, 40, 8).
PLUGIN.importPrices = {
	bandage = 12,
	health_vial = 30,
	pistolammo = 6
}

-- What a new city stockpile holds before any saved stock exists: item uniqueID -> quantity.
-- Shared so later economy work can read the seed it started from.
PLUGIN.seedStock = {
	supplements = 50,
	water = 50,
	metal_scrap = 20
}

ix.util.Include("sv_plugin.lua")
ix.util.Include("cl_plugin.lua")

ix.command.Add("CityFunds", {
	description = "Shows the city treasury and stockpile. Add with: /CityFunds add <tokens>, /CityFunds stock <item> <amount>.",
	privilege = "Manage City Funds",
	adminOnly = true,
	arguments = {
		bit.bor(ix.type.string, ix.type.optional),
		bit.bor(ix.type.string, ix.type.optional),
		bit.bor(ix.type.number, ix.type.optional)
	},
	OnRun = function(self, client, action, target, amount)
		if (!ix.city) then
			return "City funds are unavailable."
		end

		action = action and string.lower(action) or nil

		if (!action) then
			client:Notify("City treasury: " .. ix.city.GetTreasury() .. " tokens.")

			local ids = table.GetKeys(PLUGIN.stock or {})
			table.sort(ids)

			if (#ids == 0) then
				client:Notify("City stockpile is empty.")
			else
				for _, uniqueID in ipairs(ids) do
					client:Notify("Stock " .. uniqueID .. ": " .. tostring(PLUGIN.stock[uniqueID]) .. ".")
				end
			end

			return
		end

		if (action == "add") then
			local tokens = tonumber(target)

			if (!tokens or !ix.city.AddTreasury(tokens)) then
				return "Usage: /CityFunds add <tokens>"
			end

			return "City treasury: " .. ix.city.GetTreasury() .. " tokens."
		end

		if (action == "stock") then
			if (!target or !amount or !ix.city.AddStock(target, amount)) then
				return "Usage: /CityFunds stock <item> <amount> (the item must exist)"
			end

			return "Stock " .. target .. ": " .. tostring(ix.city.GetStock(target)) .. "."
		end

		return "Usage: /CityFunds, /CityFunds add <tokens>, or /CityFunds stock <item> <amount>"
	end
})
