local PLUGIN = PLUGIN

-- The city treasury (integer tokens, never negative) and stockpile
-- (item uniqueID -> quantity; quantities may be fractional, as ix.stack's are,
-- and a quantity that reaches zero is dropped). Server-only: nothing here is
-- networked or drawn. Saved through the plugin's own data, seeded from
-- cityTreasurySeed and PLUGIN.seedStock the first time it is loaded.
ix.city = ix.city or {}

PLUGIN.treasury = PLUGIN.treasury or 0
PLUGIN.stock = PLUGIN.stock or {}
PLUGIN.traderFunds = PLUGIN.traderFunds or 0

local function IsAmount(amount)
	return isnumber(amount) and amount == amount and amount != math.huge and amount != -math.huge and amount >= 0
end

local function Enabled()
	return ix.config.Get("cityEconomyEnabled", true)
end

-- Where the CWU terminals on the map stand, for saving. The terminals keep no state of their
-- own, so a position and angles each is the whole record.
function PLUGIN:GetTerminalRecords()
	local records = {}

	for _, entity in ipairs(ents.FindByClass("ix_cwu_terminal")) do
		if (IsValid(entity) and !entity:IsMarkedForDeletion()) then
			records[#records + 1] = {pos = entity:GetPos(), ang = entity:GetAngles()}
		end
	end

	return records
end

-- Puts the saved CWU terminals back. A record whose terminal is already standing there (this
-- is a reload, not a first load) is skipped, so loading twice never duplicates one.
function PLUGIN:LoadTerminals(records)
	if (!istable(records)) then
		return
	end

	self.bLoadingTerminals = true

	for _, record in ipairs(records) do
		if (!istable(record) or !isvector(record.pos)) then
			continue
		end

		local bStanding = false

		for _, entity in ipairs(ents.FindByClass("ix_cwu_terminal")) do
			if (IsValid(entity) and !entity:IsMarkedForDeletion() and entity:GetPos():DistToSqr(record.pos) <= 4) then
				bStanding = true
				break
			end
		end

		if (!bStanding) then
			local entity = ents.Create("ix_cwu_terminal")

			if (IsValid(entity)) then
				entity:SetPos(record.pos)
				entity:SetAngles(isangle(record.ang) and record.ang or angle_zero)
				entity:Spawn()
				entity:Activate()
			end
		end
	end

	self.bLoadingTerminals = nil
end

-- Where the trade caches on the map stand, for saving (the CWU terminals' twin). The caches
-- keep no state of their own, so a position and angles each is the whole record.
function PLUGIN:GetCacheRecords()
	local records = {}

	for _, entity in ipairs(ents.FindByClass("ix_trade_cache")) do
		if (IsValid(entity) and !entity:IsMarkedForDeletion()) then
			records[#records + 1] = {pos = entity:GetPos(), ang = entity:GetAngles()}
		end
	end

	return records
end

-- Puts the saved trade caches back, skipping any already standing there (a reload).
function PLUGIN:LoadCaches(records)
	if (!istable(records)) then
		return
	end

	self.bLoadingCaches = true

	for _, record in ipairs(records) do
		if (!istable(record) or !isvector(record.pos)) then
			continue
		end

		local bStanding = false

		for _, entity in ipairs(ents.FindByClass("ix_trade_cache")) do
			if (IsValid(entity) and !entity:IsMarkedForDeletion() and entity:GetPos():DistToSqr(record.pos) <= 4) then
				bStanding = true
				break
			end
		end

		if (!bStanding) then
			local entity = ents.Create("ix_trade_cache")

			if (IsValid(entity)) then
				entity:SetPos(record.pos)
				entity:SetAngles(isangle(record.ang) and record.ang or angle_zero)
				entity:Spawn()
				entity:Activate()
			end
		end
	end

	self.bLoadingCaches = nil
end

function PLUGIN:SaveCity()
	self:SetData({
		treasury = self.treasury or 0,
		stock = table.Copy(self.stock or {}),
		terminals = self:GetTerminalRecords(),
		traderFunds = self.traderFunds or 0,
		caches = self:GetCacheRecords()
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

		self.traderFunds = math.max(0, math.floor(ix.config.Get("traderFundsSeed", 2000)))
		self:LoadTerminals(istable(data) and data.terminals or nil)
		self:LoadCaches(istable(data) and data.caches or nil)
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

	-- data saved before the CWU terminals existed has no terminals key at all
	self:LoadTerminals(data.terminals)

	-- data saved before the trader existed has no pool: seed it as a fresh city would
	if (data.traderFunds == nil) then
		self.traderFunds = math.max(0, math.floor(ix.config.Get("traderFundsSeed", 2000)))
	else
		self.traderFunds = IsAmount(tonumber(data.traderFunds)) and math.floor(tonumber(data.traderFunds)) or 0
	end

	self:LoadCaches(data.caches)
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

util.AddNetworkString("ixCityOpen")
util.AddNetworkString("ixCityState")
util.AddNetworkString("ixCityDeliver")
util.AddNetworkString("ixCityExport")
util.AddNetworkString("ixCityImport")
util.AddNetworkString("ixCityDraw")
util.AddNetworkString("ixCityResult")

-- Seconds between two terminal requests from one player (ixCraftRecipe's idiom).
PLUGIN.requestInterval = 0.33

local function ItemName(uniqueID)
	local itemTable = ix.item.list[uniqueID]

	return itemTable and itemTable.name or uniqueID
end

local function Levy()
	local levy = tonumber(ix.config.Get("cityExportLevy", 0.3)) or 0.3

	if (!IsAmount(levy)) then
		return 0.3
	end

	return math.Clamp(levy, 0, 0.95)
end

--- Whether the player may use this terminal now: alive, in character, free to act, and within
-- reach of it (PLUGIN.reach, measured as a station measures it).
function PLUGIN:CanUseTerminal(client, terminal)
	if (!IsValid(client) or !client:IsPlayer() or !IsValid(terminal) or terminal:GetClass() != "ix_cwu_terminal") then
		return false
	end

	if (!client:Alive() or !client:GetCharacter() or client:IsRestricted() or IsValid(client.ixRagdoll)) then
		return false
	end

	local reach = self.reach or 128

	return client:GetShootPos():DistToSqr(terminal:NearestPoint(client:GetShootPos())) <= reach * reach
end

local function RateLimited(client)
	if ((client.ixNextCityTrade or 0) > CurTime()) then
		return true
	end

	client.ixNextCityTrade = CurTime() + PLUGIN.requestInterval
end

-- The treasury and stockpile the open panel shows. Sent when a terminal opens and after every
-- answer, so the rows follow the trade.
function PLUGIN:SendState(client, terminal, message)
	net.Start(message or "ixCityState")
		net.WriteEntity(terminal)
		net.WriteUInt(math.Clamp(ix.city.GetTreasury(), 0, 4294967295), 32)
		net.WriteTable(table.Copy(self.stock or {}))
	net.Send(client)
end

--- Opens a terminal for a player: the client puts the world panel beside it.
function PLUGIN:OpenTerminal(client, terminal)
	client.ixCityTerminal = terminal
	self:SendState(client, terminal, "ixCityOpen")
end

-- One private line and its sound, as a craft answers (ixCraftResult): the client says it.
local function Answer(client, bSuccess, text)
	net.Start("ixCityResult")
		net.WriteBool(bSuccess)
		net.WriteString(text or "")
	net.Send(client)
end

--- One delivery at a terminal: one trade unit of a wanted good for its pay, from the treasury.
-- Nothing is taken when the city already holds its target or cannot pay. Returns success, text.
function PLUGIN:Deliver(client, terminal, uniqueID)
	local wanted = isstring(uniqueID) and self.wanted[uniqueID]
	local character = client:GetCharacter()
	local inventory = character and character:GetInventory()

	if (!wanted or !inventory or !ix.item.list[uniqueID] or !IsAmount(wanted.pay) or !IsAmount(wanted.target)) then
		return false, "The city is not buying that."
	end

	local unit = ix.stack and ix.stack.IsStackable(uniqueID) and ix.stack.GetTradeAmount(uniqueID) or 1

	if (!IsAmount(unit) or unit <= 0 or ix.stack.Count(inventory, uniqueID) < unit) then
		return false, "You do not have that to deliver."
	end

	if (ix.city.GetStock(uniqueID) >= wanted.target) then
		return false, "The city has enough " .. ItemName(uniqueID) .. "."
	end

	local amount = wanted.pay * unit

	-- all or nothing, as an import is: a treasury that can only part-pay buys nothing
	if (!IsAmount(amount) or amount < 1 or (Enabled() and ix.city.GetTreasury() < math.floor(amount))) then
		return false, "The city treasury cannot pay for that."
	end

	if (!ix.stack.Take(inventory, uniqueID, unit)) then
		return false, "You do not have that to deliver."
	end

	ix.city.AddStock(uniqueID, unit)

	local paid = ix.city.PayPlayer(client, amount, "delivery")

	return true, "Delivered " .. ItemName(uniqueID) .. " for " .. paid .. " tokens."
end

--- Sells every exportable good's stock above its wanted target off-map (goods with no target
-- keep nothing back); the Combine keeps the cityExportLevy fraction of the earnings. Combine
-- only. Returns success, text.
function PLUGIN:ExportSurplus(client)
	if (!client:IsCombine()) then
		return false, "Only Combine units may run city trade."
	end

	local gain, sold = 0, 0

	for uniqueID, price in pairs(self.exportPrices) do
		if (!ix.item.list[uniqueID] or !IsAmount(price)) then
			continue
		end

		local wanted = self.wanted[uniqueID]
		local reserve = wanted and IsAmount(wanted.target) and wanted.target or 0
		local surplus = ix.city.GetStock(uniqueID) - reserve

		if (surplus > 0) then
			local taken = ix.city.TakeStock(uniqueID, surplus)

			gain = gain + math.floor(taken * price * (1 - Levy()))
			sold = sold + taken
		end
	end

	if (sold <= 0) then
		return false, "There is no surplus to export."
	end

	ix.city.AddTreasury(gain)

	return true, "Exported the surplus for " .. gain .. " tokens."
end

--- Buys one unit of an importable good into stock. All or nothing: an underfunded treasury is
-- refused whole and keeps every token. Combine only. Returns success, text.
function PLUGIN:Import(client, uniqueID)
	if (!client:IsCombine()) then
		return false, "Only Combine units may run city trade."
	end

	local cost = isstring(uniqueID) and self.importPrices[uniqueID]

	if (!cost or !ix.item.list[uniqueID] or !IsAmount(cost) or cost < 1) then
		return false, "The city cannot import that."
	end

	cost = math.floor(cost)

	if (ix.city.GetTreasury() < cost or ix.city.TakeTreasury(cost) != cost) then
		return false, "The city treasury cannot pay for that."
	end

	if (!ix.city.AddStock(uniqueID, 1)) then
		ix.city.AddTreasury(cost)

		return false, "The city cannot import that."
	end

	return true, "Imported " .. ItemName(uniqueID) .. " for " .. cost .. " tokens."
end

--- A department ration drawn from stock: one supplements and one water, both or neither.
-- Combine only. Returns success, text.
function PLUGIN:DrawRation(client)
	if (!client:IsCombine()) then
		return false, "Only Combine units may draw a ration."
	end

	-- both are checked before either is taken: stock may be fractional, and TakeStock would
	-- happily take 0.5 of a good and leave the draw owing the stockpile the difference
	if (ix.city.GetStock("supplements") < 1) then
		return false, "The city has no supplements to issue."
	end

	if (ix.city.GetStock("water") < 1) then
		return false, "The city has no water to issue."
	end

	local supplements = ix.city.TakeStock("supplements", 1)

	if (supplements < 1) then
		ix.city.AddStock("supplements", supplements)

		return false, "The city has no supplements to issue."
	end

	local water = ix.city.TakeStock("water", 1)

	if (water < 1) then
		ix.city.AddStock("supplements", supplements)
		ix.city.AddStock("water", water)

		return false, "The city has no water to issue."
	end

	ix.stack.GiveOrDrop(client, "supplements", 1)
	ix.stack.GiveOrDrop(client, "water", 1)

	return true, "Ration drawn."
end

-- Every receiver re-validates: rate, the player, the terminal and its reach. The panel is only
-- a list of rows; it decides nothing.
local function TerminalRequest(client, bReadsItem)
	if (RateLimited(client)) then
		return
	end

	local terminal = net.ReadEntity()
	local uniqueID = bReadsItem and net.ReadString() or nil

	if (!PLUGIN:CanUseTerminal(client, terminal)) then
		return
	end

	return terminal, uniqueID
end

net.Receive("ixCityDeliver", function(length, client)
	local terminal, uniqueID = TerminalRequest(client, true)

	if (!terminal) then
		return
	end

	local bSuccess, text = PLUGIN:Deliver(client, terminal, uniqueID)

	Answer(client, bSuccess, text)
	PLUGIN:SendState(client, terminal)
end)

net.Receive("ixCityExport", function(length, client)
	local terminal = TerminalRequest(client)

	if (!terminal) then
		return
	end

	local bSuccess, text = PLUGIN:ExportSurplus(client)

	Answer(client, bSuccess, text)
	PLUGIN:SendState(client, terminal)
end)

net.Receive("ixCityImport", function(length, client)
	local terminal, uniqueID = TerminalRequest(client, true)

	if (!terminal) then
		return
	end

	local bSuccess, text = PLUGIN:Import(client, uniqueID)

	Answer(client, bSuccess, text)
	PLUGIN:SendState(client, terminal)
end)

net.Receive("ixCityDraw", function(length, client)
	local terminal = TerminalRequest(client)

	if (!terminal) then
		return
	end

	local bSuccess, text = PLUGIN:DrawRation(client)

	Answer(client, bSuccess, text)
	PLUGIN:SendState(client, terminal)
end)

-- The off-map trader (trade cache): any player may sell PLUGIN.traderBuy goods into the
-- trader's own token pool (PLUGIN.traderFunds, never negative; sold goods leave the map and
-- never enter city stock) and buy PLUGIN.traderSell goods with their own tokens, which the
-- pool gains. Mirrors the CWU terminal receivers above with its own net names.
util.AddNetworkString("ixTraderOpen")
util.AddNetworkString("ixTraderState")
util.AddNetworkString("ixTraderSell")
util.AddNetworkString("ixTraderBuy")
util.AddNetworkString("ixTraderResult")

--- Tokens in the trader's pool (integer, never negative).
function PLUGIN:GetTraderFunds()
	return self.traderFunds or 0
end

--- Whether the player may use this cache now: alive, in character, free to act, within reach.
function PLUGIN:CanUseCache(client, cache)
	if (!IsValid(client) or !client:IsPlayer() or !IsValid(cache) or cache:GetClass() != "ix_trade_cache") then
		return false
	end

	if (!client:Alive() or !client:GetCharacter() or client:IsRestricted() or IsValid(client.ixRagdoll)) then
		return false
	end

	local reach = self.reach or 128

	return client:GetShootPos():DistToSqr(cache:NearestPoint(client:GetShootPos())) <= reach * reach
end

function PLUGIN:SendTraderState(client, cache, message)
	net.Start(message or "ixTraderState")
		net.WriteEntity(cache)
		net.WriteUInt(math.Clamp(self:GetTraderFunds(), 0, 4294967295), 32)
	net.Send(client)
end

--- Opens a cache for a player: the client puts the world panel beside it.
function PLUGIN:OpenCache(client, cache)
	client.ixTraderCache = cache
	self:SendTraderState(client, cache, "ixTraderOpen")
end

local function TraderAnswer(client, bSuccess, text)
	net.Start("ixTraderResult")
		net.WriteBool(bSuccess)
		net.WriteString(text or "")
	net.Send(client)
end

local function TraderUnit(uniqueID)
	return ix.stack and ix.stack.IsStackable(uniqueID) and ix.stack.GetTradeAmount(uniqueID) or 1
end

--- One sale to the trader: one trade unit for its traderBuy price, paid from the pool.
-- All or nothing: a pool that cannot pay in full buys nothing. Returns success, text.
function PLUGIN:SellToTrader(client, cache, uniqueID)
	local price = isstring(uniqueID) and self.traderBuy[uniqueID]
	local character = client:GetCharacter()
	local inventory = character and character:GetInventory()

	if (!price or !inventory or !ix.item.list[uniqueID] or !IsAmount(price)) then
		return false, "The trader is not buying that."
	end

	local unit = TraderUnit(uniqueID)

	if (!IsAmount(unit) or unit <= 0 or ix.stack.Count(inventory, uniqueID) < unit) then
		return false, "You do not have that to sell."
	end

	local amount = math.floor(price * unit)

	if (!IsAmount(amount) or amount < 1 or self:GetTraderFunds() < amount) then
		return false, "The trader cannot pay for that."
	end

	if (!ix.stack.Take(inventory, uniqueID, unit)) then
		return false, "You do not have that to sell."
	end

	self.traderFunds = self:GetTraderFunds() - amount
	character:GiveMoney(amount)
	self:QueueSave()

	return true, "Sold " .. ItemName(uniqueID) .. " for " .. amount .. " tokens."
end

--- One purchase from the trader: one trade unit at its traderSell price, paid by the player
-- into the pool (money taken only once the sale is known good). Returns success, text.
function PLUGIN:BuyFromTrader(client, cache, uniqueID)
	local price = isstring(uniqueID) and self.traderSell[uniqueID]
	local character = client:GetCharacter()

	if (!price or !character or !ix.item.list[uniqueID] or !IsAmount(price)) then
		return false, "The trader is not selling that."
	end

	local unit = TraderUnit(uniqueID)

	if (!IsAmount(unit) or unit <= 0) then
		return false, "The trader is not selling that."
	end

	local amount = math.floor(price * unit)

	if (!IsAmount(amount) or amount < 1 or !character:HasMoney(amount)) then
		return false, "You cannot pay for that."
	end

	character:TakeMoney(amount)
	self.traderFunds = self:GetTraderFunds() + amount
	ix.stack.GiveOrDrop(client, uniqueID, unit)
	self:QueueSave()

	return true, "Bought " .. ItemName(uniqueID) .. " for " .. amount .. " tokens."
end

local function TraderRequest(client)
	if ((client.ixNextTraderTrade or 0) > CurTime()) then
		return
	end

	client.ixNextTraderTrade = CurTime() + PLUGIN.requestInterval

	local cache = net.ReadEntity()
	local uniqueID = net.ReadString()

	if (!PLUGIN:CanUseCache(client, cache)) then
		return
	end

	return cache, uniqueID
end

net.Receive("ixTraderSell", function(length, client)
	local cache, uniqueID = TraderRequest(client)

	if (!cache) then
		return
	end

	local bSuccess, text = PLUGIN:SellToTrader(client, cache, uniqueID)

	TraderAnswer(client, bSuccess, text)
	PLUGIN:SendTraderState(client, cache)
end)

net.Receive("ixTraderBuy", function(length, client)
	local cache, uniqueID = TraderRequest(client)

	if (!cache) then
		return
	end

	local bSuccess, text = PLUGIN:BuyFromTrader(client, cache, uniqueID)

	TraderAnswer(client, bSuccess, text)
	PLUGIN:SendTraderState(client, cache)
end)
