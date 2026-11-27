local PLUGIN = PLUGIN

-- Rows shown at once, seconds between rebuilds while open, the shortest time between two trades asked for
-- (the server allows one every 0.33 s), and how long to wait for the server's answer to one.
PLUGIN.maxRows = 9
PLUGIN.refreshInterval = 0.25
PLUGIN.tradeInterval = 0.4
PLUGIN.answerTime = 1

PLUGIN.tradeSound = "ambient/levels/labs/coinslot1.wav"

-- The phrases Helix's vendor (helix/plugins/vendor/sh_plugin.lua, ixVendorTrade) and the stacking plugin send
-- as the answer to a trade: the ones for a trade that went through, and the refusals. No other notice is taken
-- for an answer, whenever it arrives.
PLUGIN.successNotices = {
	businessPurchase = true,
	businessSell = true
}

PLUGIN.refusalNotices = {
	vendorNoMoney = true,
	vendorNoStock = true,
	vendorMaxStock = true,
	vendorNoTrade = true,
	canNotAfford = true,
	tellAdmin = true,
	stackVendorTooLittle = true
}

local COLOR_LINE = Color(175, 170, 152)

-- A private line in the chat, styled as Examine's.
local function Say(text)
	local class = ix.chat.classes.examine

	chat.AddText(class and class.color or COLOR_LINE, text)
end

local function Refused()
	local interaction = ix.plugin.list.interaction

	if (interaction and interaction.PlayActionSound) then
		interaction:PlayActionSound("cancel")
	else
		surface.PlaySound("buttons/button10.wav")
	end
end

local function ItemName(uniqueID)
	local itemTable = ix.item.list[uniqueID]

	return itemTable and L(itemTable.name) or uniqueID
end

-- "Iron (1.0 kg)" for a stackable, whose trade moves ix.stack.GetTradeAmount; the plain name otherwise.
local function TradeLabel(uniqueID)
	local itemTable = ix.item.list[uniqueID]

	if (itemTable and ix.stack and ix.stack.IsStackable(itemTable)) then
		return ItemName(uniqueID) .. " (" .. ix.stack.Format(itemTable, ix.stack.GetTradeAmount(uniqueID)) .. ")"
	end

	return ItemName(uniqueID)
end

-- How much of an item the vendor would find to buy: what the character carries (not in bags), not equipped.
local function Held(inventory, uniqueID)
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

local function SortByLabel(rows)
	table.SortByMember(rows, "label", true)

	return rows
end

--- The rows of a vendor's panel: both purses, what they sell, what they buy of yours. Shared by the panel and
-- anything that wants to know what it shows (the harness reads it).
function PLUGIN:BuildRows(vendor)
	local character = LocalPlayer():GetCharacter()
	local inventory = character and character:GetInventory()
	local items = vendor.items or {}
	local rows = {}

	if (!inventory) then
		return rows
	end

	local money = vendor.ixPanelMoney

	rows[#rows + 1] = {
		label = L("vendorPanelYou", ix.currency.Get(character:GetMoney())),
		detail = money and L("vendorPanelThey", ix.currency.Get(money)) or nil,
		heading = true
	}

	local selling, buying = {}, {}

	for uniqueID, data in pairs(items) do
		local mode = data[VENDOR_MODE]

		if (!mode or !ix.item.list[uniqueID]) then
			continue
		end

		if (mode != VENDOR_BUYONLY) then
			local price = vendor:GetPrice(uniqueID)
			local stock = vendor:GetStock(uniqueID)
			local detail = ix.currency.Get(price)

			if (stock) then
				detail = detail .. ", " .. (stock > 0 and L("vendorPanelStock", stock) or L("vendorPanelSoldOut"))
			end

			selling[#selling + 1] = {
				label = L("vendorPanelBuyRow", TradeLabel(uniqueID)),
				detail = detail,
				dim = !character:HasMoney(price) or (stock != nil and stock < 1),
				uniqueID = uniqueID,
				bSelling = false
			}
		end

		if (mode != VENDOR_SELLONLY and Held(inventory, uniqueID) > 0) then
			local price = vendor:GetPrice(uniqueID, true)
			local stock, max = vendor:GetStock(uniqueID)

			buying[#buying + 1] = {
				label = L("vendorPanelSellRow", TradeLabel(uniqueID)),
				detail = ix.currency.Get(price),
				dim = (money != nil and money < price) or (stock != nil and stock >= max),
				uniqueID = uniqueID,
				bSelling = true
			}
		end
	end

	rows[#rows + 1] = {label = L("vendorPanelSelling"), heading = true}

	if (#selling == 0) then
		rows[#rows + 1] = {label = L("vendorPanelNothingSold"), enabled = false}
	end

	table.Add(rows, SortByLabel(selling))

	rows[#rows + 1] = {label = L("vendorPanelBuying"), heading = true}

	if (#buying == 0) then
		rows[#rows + 1] = {label = L("vendorPanelNothingBought"), enabled = false}
	end

	table.Add(rows, SortByLabel(buying))

	return rows
end

local function Signature(rows)
	local parts = {}

	for i, row in ipairs(rows) do
		parts[i] = tostring(row.label) .. "|" .. tostring(row.detail) .. "|" .. tostring(row.dim)
	end

	return table.concat(parts, "\n")
end

-- What a trade changes for the player, to tell whether one the server answered silently went through.
local function Holdings()
	local character = LocalPlayer():GetCharacter()

	if (!character) then
		return ""
	end

	local parts = {tostring(character:GetMoney())}

	for item in character:GetInventory():Iter() do
		parts[#parts + 1] = item:GetID() .. "=" .. tostring(item:GetData("quantity", 1))
	end

	table.sort(parts)

	return table.concat(parts, ",")
end

--- Asks the server for one trade, as the window's buttons did.
function PLUGIN:Trade(row)
	if (!row.uniqueID or RealTime() < (self.nextTrade or 0)) then
		return
	end

	self.nextTrade = RealTime() + self.tradeInterval
	self.pending = {time = RealTime(), holdings = Holdings()}

	net.Start("ixVendorTrade")
		net.WriteString(row.uniqueID)
		net.WriteBool(row.bSelling)
	net.SendToServer()
end

function PLUGIN:GetPanel()
	local panel = self.panel

	if (panel and panel:IsOpen()) then
		return panel
	end
end

function PLUGIN:OpenPanel(vendor)
	local rows = self:BuildRows(vendor)

	self.bOpening = true

	local panel = ix.worldui.Open({
		anchor = vendor,
		title = vendor:GetDisplayName(),
		rows = rows,
		bKeepOpen = true,
		maxRows = self.maxRows,
		OnSelect = function(_, row)
			self:Trade(row)
		end,
		OnClose = function(_, reason)
			self.pending = nil

			-- a new panel for a vendor that has just opened again: the server already has this player there
			if (reason == ix.worldui.reasons.replaced and self.bOpening) then
				return
			end

			net.Start("ixVendorClose")
			net.SendToServer()
		end
	})

	self.bOpening = nil

	panel.vendor = vendor
	panel.vendorSignature = Signature(rows)
	panel.vendorRefresh = RealTime() + self.refreshInterval

	self.panel = panel

	return panel
end

function PLUGIN:RefreshPanel(bNow)
	local panel = self:GetPanel()

	if (!panel or (!bNow and RealTime() < panel.vendorRefresh) or !IsValid(panel.vendor)) then
		return
	end

	panel.vendorRefresh = RealTime() + self.refreshInterval

	local rows = self:BuildRows(panel.vendor)
	local signature = Signature(rows)
	local title = panel.vendor:GetDisplayName()

	if (signature != panel.vendorSignature or title != panel.title) then
		panel.vendorSignature = signature
		panel.title = title
		panel:SetRows(rows)
	end
end

function PLUGIN:Think()
	if (!self.panel) then
		return
	end

	self:RefreshPanel()

	-- the server refused without a word (or answered with something other than a notice)
	local pending = self.pending

	if (pending and RealTime() - pending.time > self.answerTime) then
		self.pending = nil

		if (Holdings() == pending.holdings) then
			Refused()
		end
	end
end

-- While a trade waits for its answer, the vendor's own answers (successNotices, refusalNotices) become a private
-- line and a sound; any other notice is left alone. "Not able to trade" (also sent when Use is refused) is always
-- one.
function PLUGIN:HandleNotice(message, ...)
	local pending = self.pending
	local bAnswer = self.successNotices[message] or self.refusalNotices[message]

	if (message == "vendorNoTrade" or (bAnswer and pending and RealTime() - pending.time <= self.answerTime)) then
		self.pending = nil

		if (self.successNotices[message]) then
			surface.PlaySound(self.tradeSound)
		else
			Refused()
		end

		Say(L(message, ...))

		return true
	end
end

-- Helix's client receivers for the vendor (helix/plugins/vendor/sh_plugin.lua) are wrapped: opening shows the
-- world panel instead of the window, and money and stock updates go to the panel's vendor. The editor still
-- opens Helix's window (ixVendorEditor, untouched), and while that window is up the originals run.
function PLUGIN:WrapReceivers()
	local receivers = net.Receivers
	local original = self.originalReceivers or {}

	for _, name in ipairs({"ixvendoropen", "ixvendormoney", "ixvendorstock", "ixvendoredit"}) do
		if (receivers[name] and receivers[name] != self.receivers[name]) then
			original[name] = receivers[name]
		end
	end

	self.originalReceivers = original

	for name, callback in pairs(self.receivers) do
		receivers[name] = callback
	end

	if (!self.originalNotify and ix.util.NotifyLocalized) then
		self.originalNotify = ix.util.NotifyLocalized
	end

	local notify = self.originalNotify

	function ix.util.NotifyLocalized(message, ...)
		if (PLUGIN:HandleNotice(message, ...)) then
			return
		end

		return notify(message, ...)
	end
end

PLUGIN.receivers = {}

PLUGIN.receivers.ixvendoropen = function()
	local vendor = net.ReadEntity()

	if (!IsValid(vendor)) then
		return
	end

	vendor.money = net.ReadUInt(16)
	vendor.items = net.ReadTable()
	vendor.scale = net.ReadFloat()

	PLUGIN:OpenPanel(vendor)
end

PLUGIN.receivers.ixvendormoney = function(length)
	if (IsValid(ix.gui.vendor)) then
		return PLUGIN.originalReceivers.ixvendormoney(length)
	end

	-- Helix's 16 bits cannot carry 65,536 or more, nor "keeps no money"; ixVendorPanelMoney (sv_plugin.lua)
	-- follows every change with the real amount, so this one is read and set aside.
	net.ReadUInt(16)
end

-- An edit from the vendor editor (staff), which Helix sends to everyone trading with the vendor but applies only
-- to its own window: the same changes, applied to the open panel's vendor.
PLUGIN.receivers.ixvendoredit = function(length)
	if (IsValid(ix.gui.vendor)) then
		return PLUGIN.originalReceivers.ixvendoredit(length)
	end

	local key = net.ReadString()
	local data = net.ReadType()
	local panel = PLUGIN:GetPanel()
	local vendor = panel and panel.vendor

	if (!IsValid(vendor) or !vendor.items) then
		return
	end

	local items = vendor.items

	if (key == "mode" and istable(data)) then
		items[data[1]] = items[data[1]] or {}
		items[data[1]][VENDOR_MODE] = data[2]
	elseif (key == "price" and istable(data)) then
		items[data[1]] = items[data[1]] or {}
		items[data[1]][VENDOR_PRICE] = tonumber(data[2])
	elseif (key == "stockDisable" and isstring(data)) then
		if (items[data]) then
			items[data][VENDOR_MAXSTOCK] = nil
		end
	elseif (key == "stockMax" and istable(data)) then
		items[data[1]] = items[data[1]] or {}
		items[data[1]][VENDOR_MAXSTOCK] = data[2]
		items[data[1]][VENDOR_STOCK] = data[3]
	elseif (key == "stock" and istable(data)) then
		items[data[1]] = items[data[1]] or {}
		items[data[1]][VENDOR_MAXSTOCK] = items[data[1]][VENDOR_MAXSTOCK] or data[2]
		items[data[1]][VENDOR_STOCK] = data[2]
	elseif (key == "scale") then
		vendor.scale = tonumber(data) or vendor.scale
	end

	PLUGIN:RefreshPanel(true)
end

PLUGIN.receivers.ixvendorstock = function(length)
	if (IsValid(ix.gui.vendor)) then
		return PLUGIN.originalReceivers.ixvendorstock(length)
	end

	local panel = PLUGIN:GetPanel()
	local uniqueID = net.ReadString()
	local amount = net.ReadUInt(16)

	if (panel and IsValid(panel.vendor) and panel.vendor.items) then
		panel.vendor.items[uniqueID] = panel.vendor.items[uniqueID] or {}
		panel.vendor.items[uniqueID][VENDOR_STOCK] = amount
		PLUGIN:RefreshPanel(true)
	end
end

-- Whether the vendor keeps money, and how much (sv_plugin.lua): right after it opens, and whenever it changes.
net.Receive("ixVendorPanelMoney", function()
	local vendor = net.ReadEntity()
	local bTracks = net.ReadBool()
	local money = net.ReadUInt(32)

	if (IsValid(vendor)) then
		vendor.money = bTracks and money or nil
		vendor.ixPanelMoney = vendor.money
		PLUGIN:RefreshPanel(true)
	end
end)

function PLUGIN:InitializedPlugins()
	self:WrapReceivers()
end

if (ix.util.NotifyLocalized and net.Receivers.ixvendoropen) then
	PLUGIN:WrapReceivers()
end
