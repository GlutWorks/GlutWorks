local PLUGIN = PLUGIN

-- The city treasury (integer tokens, never negative) and stockpile
-- (item uniqueID -> quantity; quantities may be fractional, as ix.stack's are,
-- and a quantity that reaches zero is dropped). Server-only: nothing here is
-- networked or drawn. Saved through the plugin's own data, seeded from
-- cityTreasurySeed and PLUGIN.seedStock the first time it is loaded.
ix.city = ix.city or {}

PLUGIN.treasury = PLUGIN.treasury or 0
PLUGIN.stock = PLUGIN.stock or {}

local function IsAmount(amount)
	return isnumber(amount) and amount == amount and amount != math.huge and amount != -math.huge and amount >= 0
end

local function Enabled()
	return ix.config.Get("cityEconomyEnabled", true)
end

function PLUGIN:SaveCity()
	self:SetData({
		treasury = self.treasury or 0,
		stock = table.Copy(self.stock or {})
	})
end

function PLUGIN:QueueSave()
	if (!ix.shuttingDown) then
		timer.Create("ixCityEconomySave", 1, 1, function()
			self:SaveCity()
		end)
	end
end

function PLUGIN:SaveData()
	self:SaveCity()
end

function PLUGIN:LoadData()
	local data = self:GetData()

	if (!istable(data) or data.treasury == nil) then
		-- first load: seed a new city
		self.treasury = math.max(0, math.floor(ix.config.Get("cityTreasurySeed", 5000)))
		self.stock = {}

		for uniqueID, quantity in pairs(self.seedStock or {}) do
			if (isstring(uniqueID) and IsAmount(quantity) and quantity > 0) then
				self.stock[uniqueID] = quantity
			end
		end

		self:QueueSave()

		return
	end

	self.treasury = IsAmount(tonumber(data.treasury)) and math.floor(tonumber(data.treasury)) or 0
	self.stock = {}

	if (istable(data.stock)) then
		for uniqueID, quantity in pairs(data.stock) do
			quantity = tonumber(quantity)

			if (isstring(uniqueID) and IsAmount(quantity) and quantity > 0) then
				self.stock[uniqueID] = quantity
			end
		end
	end
end

--- Tokens in the treasury (integer, never negative).
function ix.city.GetTreasury()
	return PLUGIN.treasury or 0
end

--- Adds tokens to the treasury (floored, as tokens are integers).
-- Returns false when amount is not a finite, non-negative number.
function ix.city.AddTreasury(amount)
	if (!IsAmount(amount)) then
		return false
	end

	amount = math.floor(amount)
	PLUGIN.treasury = math.max(0, (PLUGIN.treasury or 0) + amount)

	if (amount > 0) then
		PLUGIN:QueueSave()
	end

	return true
end

--- Takes up to amount tokens from the treasury (floored), never overdrawing.
-- Returns the amount actually taken (0..amount).
function ix.city.TakeTreasury(amount)
	if (!IsAmount(amount)) then
		return 0
	end

	local taken = math.min(math.floor(amount), PLUGIN.treasury or 0)
	PLUGIN.treasury = (PLUGIN.treasury or 0) - taken

	if (taken > 0) then
		PLUGIN:QueueSave()
	end

	return taken
end

--- Quantity of an item in the stockpile; 0 when it is not stocked.
function ix.city.GetStock(uniqueID)
	if (!isstring(uniqueID)) then
		return 0
	end

	return (PLUGIN.stock or {})[uniqueID] or 0
end

--- Adds a quantity of an item to the stockpile (may be fractional).
-- Returns false when the item does not exist or amount is not a finite,
-- non-negative number.
function ix.city.AddStock(uniqueID, amount)
	if (!isstring(uniqueID) or !ix.item.list[uniqueID] or !IsAmount(amount)) then
		return false
	end

	if (amount > 0) then
		PLUGIN.stock = PLUGIN.stock or {}
		PLUGIN.stock[uniqueID] = (PLUGIN.stock[uniqueID] or 0) + amount
		PLUGIN:QueueSave()
	end

	return true
end

--- Takes up to amount of an item from the stockpile, never more than it holds.
-- Returns the amount actually taken (0 for an unknown item or a bad amount).
function ix.city.TakeStock(uniqueID, amount)
	if (!isstring(uniqueID) or !ix.item.list[uniqueID] or !IsAmount(amount)) then
		return 0
	end

	PLUGIN.stock = PLUGIN.stock or {}

	local taken = math.min(amount, PLUGIN.stock[uniqueID] or 0)
	local remaining = (PLUGIN.stock[uniqueID] or 0) - taken

	if (remaining <= 0) then
		PLUGIN.stock[uniqueID] = nil
	else
		PLUGIN.stock[uniqueID] = remaining
	end

	if (taken > 0) then
		PLUGIN:QueueSave()
	end

	return taken
end

--- Pays a player from the treasury: only what the treasury could give reaches
-- their character. While cityEconomyEnabled is off, pays in full without
-- debiting, as the faucets did before. `reason` names the faucet for callers
-- ("salary", "ration"); the money itself is logged by GiveMoney.
-- Returns the amount paid.
function ix.city.PayPlayer(client, amount, reason)
	if (!IsValid(client) or !IsAmount(amount)) then
		return 0
	end

	local character = client:GetCharacter()

	if (!character) then
		return 0
	end

	amount = math.floor(amount)

	if (amount <= 0) then
		return 0
	end

	if (!Enabled()) then
		character:GiveMoney(amount)

		return amount
	end

	local paid = ix.city.TakeTreasury(amount)

	if (paid > 0) then
		character:GiveMoney(paid)
	end

	return paid
end

-- An empty treasury earns no salary at all: returning false here keeps Helix's
-- salary timer from paying 0 and sending its "salary" notice for 0 tokens
-- (helix/gamemode/core/hooks/sv_hooks.lua). A part-paid salary still goes
-- through GetSalaryAmount below, and Helix's notice then names what was paid.
function PLUGIN:CanPlayerEarnSalary(client, faction)
	if (Enabled() and ix.city.GetTreasury() <= 0) then
		return false
	end
end

-- The salary is withdrawn from the treasury here; Helix then GiveMoneys the
-- amount returned. 0 is truthy in Lua, so `hook.Run(...) or faction.pay` in
-- Helix keeps a 0 instead of falling back to the full wage. Returning a value
-- is the point of this hook. While disabled, returns nothing and Helix pays
-- faction.pay as before.
function PLUGIN:GetSalaryAmount(client, faction)
	if (!Enabled()) then
		return
	end

	local pay = faction and faction.pay

	if (!IsAmount(pay)) then
		return 0
	end

	return ix.city.TakeTreasury(pay)
end
