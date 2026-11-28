
-- The CWU terminal panel: a world panel beside the terminal (ix.worldui), never a window.
-- "Deliver" rows for the wanted goods the player carries; Combine units also get the city's
-- off-map trade (export surplus, import one unit) and "Draw ration". Choosing a row only asks
-- the server (ixCityDeliver/ixCityExport/ixCityImport/ixCityDraw), which checks everything
-- again and answers with one private line (ixCityResult) and the new city state (ixCityState).

local PLUGIN = PLUGIN

PLUGIN.panelRefresh = 0.5
PLUGIN.panelRows = 9
PLUGIN.tradeInterval = 0.4

local COLOR_LINE = Color(175, 170, 152)

-- A private line in the chat, styled as Examine's (ixcraft's panel says its lines the same way).
local function Say(text)
	local class = ix.chat.classes.examine

	chat.AddText(class and class.color or COLOR_LINE, text)
end

local function Sound(kind)
	local interaction = ix.plugin.list.interaction

	if (interaction and interaction.PlayActionSound) then
		interaction:PlayActionSound(kind)
	else
		surface.PlaySound(kind == "cancel" and "buttons/button10.wav" or "buttons/button14.wav")
	end
end

local function ItemName(uniqueID)
	local itemTable = ix.item.list[uniqueID]

	return itemTable and L(itemTable.name) or uniqueID
end

-- "Iron (1.0 kg)" for a stackable, whose delivery moves ix.stack.GetTradeAmount; the plain name otherwise.
local function TradeLabel(uniqueID)
	local itemTable = ix.item.list[uniqueID]

	if (itemTable and ix.stack and ix.stack.IsStackable(itemTable)) then
		return ItemName(uniqueID) .. " (" .. ix.stack.Format(itemTable, ix.stack.GetTradeAmount(uniqueID)) .. ")"
	end

	return ItemName(uniqueID)
end

local function Held(inventory, uniqueID)
	if (!inventory) then
		return 0
	end

	if (ix.stack and ix.stack.IsStackable(uniqueID)) then
		return ix.stack.Count(inventory, uniqueID)
	end

	local count = 0

	for item in inventory:Iter() do
		if (item.uniqueID == uniqueID and item:GetData("equip", false) == false) then
			count = count + 1
		end
	end

	return count
end

local function SortedKeys(map)
	local keys = table.GetKeys(map)

	table.sort(keys, function(a, b)
		return ItemName(a) < ItemName(b)
	end)

	return keys
end

--- The rows of a terminal's panel, from the city state the server last sent (PLUGIN.state) and
-- what the player carries. Shared by the panel and anything that wants to know what it shows.
function PLUGIN:BuildRows()
	local client = LocalPlayer()
	local character = client:GetCharacter()
	local inventory = character and character:GetInventory()
	local state = self.state or {treasury = 0, stock = {}}
	local rows = {}

	rows[#rows + 1] = {label = "Deliver", heading = true}

	local deliveries = 0

	for _, uniqueID in ipairs(SortedKeys(self.wanted)) do
		local wanted = self.wanted[uniqueID]

		if (!ix.item.list[uniqueID] or Held(inventory, uniqueID) <= 0) then
			continue
		end

		local stock = state.stock[uniqueID] or 0

		deliveries = deliveries + 1
		rows[#rows + 1] = {
			label = TradeLabel(uniqueID),
			detail = "city holds " .. stock .. " of " .. wanted.target .. ", pays " .. wanted.pay,
			dim = stock >= wanted.target,
			action = "deliver",
			uniqueID = uniqueID
		}
	end

	if (deliveries == 0) then
		rows[#rows + 1] = {label = "Nothing the city wants", enabled = false}
	end

	if (client:IsCombine()) then
		rows[#rows + 1] = {label = "City trade", heading = true}
		rows[#rows + 1] = {
			label = "Export surplus",
			detail = "treasury " .. state.treasury,
			action = "export"
		}
		rows[#rows + 1] = {
			label = "Draw ration",
			detail = "supplements " .. (state.stock.supplements or 0) .. ", water " .. (state.stock.water or 0),
			dim = (state.stock.supplements or 0) < 1 or (state.stock.water or 0) < 1,
			action = "draw"
		}
		rows[#rows + 1] = {label = "Import", heading = true}

		for _, uniqueID in ipairs(SortedKeys(self.importPrices)) do
			if (!ix.item.list[uniqueID]) then
				continue
			end

			local cost = self.importPrices[uniqueID]

			rows[#rows + 1] = {
				label = ItemName(uniqueID),
				detail = "costs " .. cost .. ", city holds " .. (state.stock[uniqueID] or 0),
				dim = state.treasury < cost,
				action = "import",
				uniqueID = uniqueID
			}
		end
	end

	return rows
end

local function Signature(rows)
	local parts = {}

	for i, row in ipairs(rows) do
		parts[i] = tostring(row.label) .. "|" .. tostring(row.detail) .. "|" .. tostring(row.dim)
	end

	return table.concat(parts, "\n")
end

--- Asks the server for the row's trade at the panel's terminal.
function PLUGIN:Choose(row)
	local panel = self:GetPanel()

	if (!panel or !IsValid(panel.cityTerminal) or (self.nextTrade or 0) > RealTime()) then
		return
	end

	self.nextTrade = RealTime() + self.tradeInterval

	if (row.action == "deliver" and row.uniqueID) then
		net.Start("ixCityDeliver")
			net.WriteEntity(panel.cityTerminal)
			net.WriteString(row.uniqueID)
		net.SendToServer()
	elseif (row.action == "export") then
		net.Start("ixCityExport")
			net.WriteEntity(panel.cityTerminal)
		net.SendToServer()
	elseif (row.action == "import" and row.uniqueID) then
		net.Start("ixCityImport")
			net.WriteEntity(panel.cityTerminal)
			net.WriteString(row.uniqueID)
		net.SendToServer()
	elseif (row.action == "draw") then
		net.Start("ixCityDraw")
			net.WriteEntity(panel.cityTerminal)
		net.SendToServer()
	end
end

--- The open terminal panel, if any.
function PLUGIN:GetPanel()
	local panel = self.panel

	if (panel and panel:IsOpen()) then
		return panel
	end
end

--- Opens the panel beside a terminal. It stays open while the player chooses, follows the city
-- state and the inventory, and closes on leaving reach (ix.worldui reach, PLUGIN.reach).
function PLUGIN:OpenPanel(terminal)
	if (!IsValid(terminal) or !ix.worldui) then
		return
	end

	local rows = self:BuildRows()
	local panel = ix.worldui.Open({
		anchor = terminal,
		title = "CWU Terminal",
		rows = rows,
		bKeepOpen = true,
		maxRows = self.panelRows,
		reach = self.reach,
		OnSelect = function(_, row)
			self:Choose(row)
		end
	})

	panel.cityTerminal = terminal
	panel.citySignature = Signature(rows)
	panel.cityRefresh = RealTime() + self.panelRefresh

	self.panel = panel

	return panel
end

function PLUGIN:RefreshPanel(bNow)
	local panel = self:GetPanel()

	if (!panel or (!bNow and RealTime() < panel.cityRefresh) or !IsValid(panel.cityTerminal)) then
		return
	end

	panel.cityRefresh = RealTime() + self.panelRefresh

	local rows = self:BuildRows()
	local signature = Signature(rows)

	if (signature != panel.citySignature) then
		panel.citySignature = signature
		panel:SetRows(rows)
	end
end

--- The rows of a trade cache's panel: what the trader buys that the player carries, then
-- what the trader sells. From PLUGIN.traderState (the pool) and the player's pockets.
function PLUGIN:BuildTraderRows()
	local client = LocalPlayer()
	local character = client:GetCharacter()
	local inventory = character and character:GetInventory()
	local funds = self.traderState or 0
	local rows = {}

	rows[#rows + 1] = {label = "Sell to trader", heading = true}

	local sales = 0

	for _, uniqueID in ipairs(SortedKeys(self.traderBuy)) do
		if (!ix.item.list[uniqueID] or Held(inventory, uniqueID) <= 0) then
			continue
		end

		local price = self.traderBuy[uniqueID]

		sales = sales + 1
		rows[#rows + 1] = {
			label = TradeLabel(uniqueID),
			detail = "trader pays " .. price .. ", pool " .. funds,
			dim = funds < price,
			action = "traderSell",
			uniqueID = uniqueID
		}
	end

	if (sales == 0) then
		rows[#rows + 1] = {label = "Nothing the trader wants", enabled = false}
	end

	rows[#rows + 1] = {label = "Buy from trader", heading = true}

	for _, uniqueID in ipairs(SortedKeys(self.traderSell)) do
		if (!ix.item.list[uniqueID]) then
			continue
		end

		local price = self.traderSell[uniqueID]

		rows[#rows + 1] = {
			label = TradeLabel(uniqueID),
			detail = "costs " .. price,
			dim = character != nil and !character:HasMoney(price),
			action = "traderBuy",
			uniqueID = uniqueID
		}
	end

	return rows
end

function PLUGIN:GetTraderPanel()
	local panel = self.traderPanel

	if (panel and panel:IsOpen()) then
		return panel
	end
end

function PLUGIN:ChooseTrader(row)
	local panel = self:GetTraderPanel()

	if (!panel or !IsValid(panel.traderCache) or (self.nextTrade or 0) > RealTime() or !row.uniqueID) then
		return
	end

	self.nextTrade = RealTime() + self.tradeInterval

	net.Start(row.action == "traderSell" and "ixTraderSell" or "ixTraderBuy")
		net.WriteEntity(panel.traderCache)
		net.WriteString(row.uniqueID)
	net.SendToServer()
end

--- Opens the panel beside a trade cache, as a terminal's panel opens (reach PLUGIN.reach).
function PLUGIN:OpenTraderPanel(cache)
	if (!IsValid(cache) or !ix.worldui) then
		return
	end

	local rows = self:BuildTraderRows()
	local panel = ix.worldui.Open({
		anchor = cache,
		title = "Trade Cache",
		rows = rows,
		bKeepOpen = true,
		maxRows = self.panelRows,
		reach = self.reach,
		OnSelect = function(_, row)
			self:ChooseTrader(row)
		end
	})

	panel.traderCache = cache
	panel.traderSignature = Signature(rows)
	panel.traderRefresh = RealTime() + self.panelRefresh

	self.traderPanel = panel

	return panel
end

function PLUGIN:RefreshTraderPanel(bNow)
	local panel = self:GetTraderPanel()

	if (!panel or (!bNow and RealTime() < panel.traderRefresh) or !IsValid(panel.traderCache)) then
		return
	end

	panel.traderRefresh = RealTime() + self.panelRefresh

	local rows = self:BuildTraderRows()
	local signature = Signature(rows)

	if (signature != panel.traderSignature) then
		panel.traderSignature = signature
		panel:SetRows(rows)
	end
end

function PLUGIN:Think()
	if (self.panel) then
		self:RefreshPanel()
	end

	if (self.traderPanel) then
		self:RefreshTraderPanel()
	end
end

local function ReadState()
	local terminal = net.ReadEntity()
	local treasury = net.ReadUInt(32)
	local stock = net.ReadTable()

	PLUGIN.state = {treasury = treasury, stock = istable(stock) and stock or {}}

	return terminal
end

net.Receive("ixCityOpen", function()
	PLUGIN:OpenPanel(ReadState())
end)

net.Receive("ixCityState", function()
	ReadState()
	PLUGIN:RefreshPanel(true)
end)

-- What the server said about a trade asked for from the panel, as a craft answers.
net.Receive("ixCityResult", function()
	local bSuccess = net.ReadBool()
	local text = net.ReadString()

	Sound(bSuccess and "complete" or "cancel")

	if (text != "") then
		Say(text)
	end
end)

local function ReadTraderState()
	local cache = net.ReadEntity()

	PLUGIN.traderState = net.ReadUInt(32)

	return cache
end

net.Receive("ixTraderOpen", function()
	PLUGIN:OpenTraderPanel(ReadTraderState())
end)

net.Receive("ixTraderState", function()
	ReadTraderState()
	PLUGIN:RefreshTraderPanel(true)
end)

net.Receive("ixTraderResult", function()
	local bSuccess = net.ReadBool()
	local text = net.ReadString()

	Sound(bSuccess and "complete" or "cancel")

	if (text != "") then
		Say(text)
	end
end)
