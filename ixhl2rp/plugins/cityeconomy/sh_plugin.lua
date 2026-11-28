local PLUGIN = PLUGIN

PLUGIN.name = "City Economy"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "The city treasury and stockpile (ix.city): faction salaries and ration tokens are paid from the treasury."

ix.config.Add("cityEconomyEnabled", true, "Whether faction salaries and ration tokens are paid from the city treasury. Off pays them in full without debiting it, as before.", nil, {
	category = "economy"
})

ix.config.Add("cityTreasurySeed", 5000, "Tokens in the city treasury the first time it is created, before any saved treasury exists.", nil, {
	data = {min = 0, max = 1000000},
	category = "economy"
})

-- What a new city stockpile holds before any saved stock exists: item uniqueID -> quantity.
-- Shared so later economy work can read the seed it started from.
PLUGIN.seedStock = {
	supplements = 50,
	water = 50,
	metal_scrap = 20
}

ix.util.Include("sv_plugin.lua")

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
