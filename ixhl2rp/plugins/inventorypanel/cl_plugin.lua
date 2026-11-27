local PLUGIN = PLUGIN

-- Rows shown at once, seconds between rebuilds of an open panel, and the shortest time between two requests.
PLUGIN.maxRows = 8
PLUGIN.refreshInterval = 0.25
PLUGIN.requestInterval = 0.3
-- A storage panel closes a little nearer than the server's reach (sv_plugin.lua), so the client lets go first.
PLUGIN.storageReach = 120
-- Money that can be taken from or left in a storage at once, besides all of it: the largest four below what there is.
PLUGIN.moneyAmounts = {1, 5, 10, 25, 50, 100, 250, 500, 1000, 5000}

local COLOR_LINE = Color(175, 170, 152)

-- A private line in the chat, styled as Examine's.
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

local materials = {}

-- An icon16 (or any) material by path, made once.
local function ActionIcon(path)
	if (!isstring(path) or path == "") then
		return
	end

	if (materials[path] == nil) then
		local material = Material(path, "smooth")

		materials[path] = !material:IsError() and material or false
	end

	return materials[path] or nil
end

local itemIcons = {}

-- An item's inventory icon when one already exists: ikon's render for an exRender item, or the spawn icon the
-- engine has made for its model. Nothing is rendered for this; a missing one is looked for again now and then.
local function ItemIcon(item)
	local cached = itemIcons[item.uniqueID]

	if (cached and (cached.material or RealTime() < cached.retry)) then
		return cached.material or nil
	end

	local material

	if (item.exRender and ikon and ikon.GetIcon) then
		material = ikon:GetIcon(item.uniqueID) or nil
	else
		local model = item.GetModel and item:GetModel()

		if (isstring(model) and model != "") then
			local path = "spawnicons/" .. (model:lower():gsub("%.mdl$", "")) .. ".png"

			if (file.Exists("materials/" .. path, "GAME")) then
				material = Material(path, "smooth")
				material = !material:IsError() and material or nil
			end
		end
	end

	itemIcons[item.uniqueID] = {material = material, retry = RealTime() + 10}

	return material
end

local function IsStack(item)
	return ix.stack != nil and ix.stack.IsStackable(item)
end

-- What a row says about an item beside its name: the stack's quantity, whether it is worn or equipped, and how many
-- things a bag holds.
local function Detail(item)
	local parts = {}

	if (IsStack(item)) then
		parts[#parts + 1] = ix.stack.Format(item, ix.stack.GetQuantity(item))
	end

	if (item:GetData("equip")) then
		parts[#parts + 1] = L(item.outfitCategory and "invPanelWorn" or "invPanelEquippedShort")
	end

	if (item.isBag and item.GetInventory) then
		local inventory = item:GetInventory()

		if (inventory) then
			parts[#parts + 1] = L("invPanelHolds", table.Count(inventory:GetItems(true)))
		end
	end

	return #parts > 0 and table.concat(parts, ", ") or nil
end

local function SortItems(items)
	table.sort(items, function(a, b)
		local nameA, nameB = a:GetName(), b:GetName()

		if (nameA != nameB) then
			return nameA < nameB
		end

		return a:GetID() < b:GetID()
	end)

	return items
end

local function ItemRow(item, inventory, action)
	return {
		label = item:GetName(),
		detail = Detail(item),
		icon = ItemIcon(item),
		action = action or "item",
		itemID = item:GetID(),
		invID = inventory:GetID()
	}
end

local function Back()
	return {label = L("invPanelBack"), action = "back", icon = ActionIcon("icon16/arrow_left.png")}
end

local function Signature(title, rows)
	local parts = {tostring(title)}

	for i, row in ipairs(rows) do
		parts[i + 1] = tostring(row.label) .. "|" .. tostring(row.detail) .. "|" .. tostring(row.dim) .. "|" ..
			tostring(row.enabled) .. "|" .. tostring(row.heading)
	end

	return table.concat(parts, "\n")
end

-- The local character's inventory and the bags in it.
local function OwnInventories()
	local character = LocalPlayer():GetCharacter()
	local inventory = character and character:GetInventory()
	local list = {}

	if (!inventory) then
		return list
	end

	list[1] = inventory

	for _, id in ipairs(inventory:GetBags()) do
		if (ix.item.inventories[id]) then
			list[#list + 1] = ix.item.inventories[id]
		end
	end

	return list
end

-- The item and the inventory it is in, among the player's own and the one the session shows beside them.
local function Locate(session, itemID)
	local inventories = OwnInventories()

	local other = session.otherID and ix.item.inventories[session.otherID]

	-- the inventory shown beside the player's, and the bags in it
	if (other) then
		inventories[#inventories + 1] = other

		for _, id in ipairs(other:GetBags()) do
			if (ix.item.inventories[id]) then
				inventories[#inventories + 1] = ix.item.inventories[id]
			end
		end
	end

	for _, inventory in ipairs(inventories) do
		local item = inventory:GetItemByID(itemID, true)

		if (item) then
			return item, inventory
		end
	end
end

-- What the old inventory menu sent for an item action.
local function InventoryAction(action, itemID, invID, data)
	net.Start("ixInventoryAction")
		net.WriteString(action)
		net.WriteUInt(itemID, 32)
		net.WriteUInt(invID, 32)
		net.WriteTable(data or {})
	net.SendToServer()
end

-- Runs an item function (or one of its sub-options, `info`) as the old right-click menu did: its OnClick first, which
-- may keep it on the client, its sound, then the action to the server with the sub-option's data.
local function RunFunction(item, invID, key, info, data)
	item.player = LocalPlayer()

	local send = true

	if (info.OnClick) then
		send = info.OnClick(item)
	end

	if (info.sound) then
		surface.PlaySound(info.sound)
	end

	if (send != false) then
		InventoryAction(key, item:GetID(), invID, data)
	end

	item.player = nil
end

local function MultiOptions(item, info)
	local options = info.multiOptions

	if (isfunction(options)) then
		item.player = LocalPlayer()
		options = options(item, LocalPlayer())
		item.player = nil
	end

	return istable(options) and options or {}
end

--- The rows of the bag (Tab): a heading with how full it is and the money carried, then what is equipped, then
-- everything else by category, then Rearrange.
function PLUGIN:BuildBag()
	local character = LocalPlayer():GetCharacter()
	local inventory = character:GetInventory()
	local rows = {
		{label = L(self:GetFullness(inventory)), detail = ix.currency.Get(character:GetMoney()), heading = true}
	}

	local equipped, categories = {}, {}

	for _, item in pairs(inventory:GetItems(true)) do
		if (item:GetData("equip")) then
			equipped[#equipped + 1] = item
		else
			local category = L(item.category or "misc")

			categories[category] = categories[category] or {}
			table.insert(categories[category], item)
		end
	end

	if (#equipped > 0) then
		rows[#rows + 1] = {label = L("invPanelEquipped"), heading = true}

		for _, item in ipairs(SortItems(equipped)) do
			rows[#rows + 1] = ItemRow(item, inventory)
		end
	end

	-- a category of one thing gets no heading of its own: those go together at the end, so the list is not half
	-- headings
	local others = {}
	local bGrouped = #equipped > 0

	for category, items in SortedPairs(categories) do
		if (#items < 2) then
			table.Add(others, items)
			continue
		end

		bGrouped = true
		rows[#rows + 1] = {label = category, heading = true}

		for _, item in ipairs(SortItems(items)) do
			rows[#rows + 1] = ItemRow(item, inventory)
		end
	end

	if (#others > 0) then
		rows[#rows + 1] = {label = L(bGrouped and "invPanelOther" or "invPanelCarried"), heading = true}

		for _, item in ipairs(SortItems(others)) do
			rows[#rows + 1] = ItemRow(item, inventory)
		end
	end

	-- what is in each carried bag, under the bag's own name, with the same actions as anything else carried
	for _, bag in ipairs(SortItems(table.ClearKeys(inventory:GetItems(true)))) do
		local bagInventory = bag.isBag and bag.GetInventory and bag:GetInventory()
		local contents = bagInventory and SortItems(table.ClearKeys(bagInventory:GetItems(true)))

		if (contents and #contents > 0) then
			rows[#rows + 1] = {label = L("invPanelInBag", bag:GetName()), detail = L(self:GetFullness(bagInventory)),
				heading = true}

			for _, item in ipairs(contents) do
				rows[#rows + 1] = ItemRow(item, bagInventory)
			end
		end
	end

	if (#rows == 1) then
		rows[#rows + 1] = {label = L("invPanelNothing"), enabled = false}
	else
		rows[#rows + 1] = {label = L("invPanelTidy"), action = "tidy", icon = ActionIcon("icon16/arrow_refresh.png")}
	end

	-- the rest of the menu, for a player without the help key bound
	rows[#rows + 1] = {label = L("invPanelMenu"), action = "menu", icon = ActionIcon("icon16/application_view_list.png")}

	return rows, L("invPanelBag")
end

--- The rows of a storage, or a carried bag, beside the player's own: what is in it, then what the player carries;
-- choosing an item moves it to the other side. Money rows where the storage keeps money.
function PLUGIN:BuildPair(session)
	local character = LocalPlayer():GetCharacter()
	local own = character:GetInventory()
	local other = ix.item.inventories[session.otherID]
	local rows = {}

	if (!other) then
		return
	end

	if (session.kind == "carried") then
		rows[1] = Back()
	end

	rows[#rows + 1] = {
		label = L("invPanelInside"),
		detail = session.money != nil and ix.currency.Get(session.money) or L(self:GetFullness(other)),
		heading = true
	}

	local inside = SortItems(table.ClearKeys(other:GetItems(true)))

	for _, item in ipairs(inside) do
		local inner = item.isBag and item.GetInventory and item:GetInventory()

		-- a bag in it opens, as the old window let it be opened, to take things out of it
		rows[#rows + 1] = ItemRow(item, other, inner and "bagLevel" or (IsStack(item) and "amountLevel" or "move"))
		rows[#rows].targetID = own:GetID()
	end

	if (#inside == 0) then
		rows[#rows + 1] = {label = L("invPanelNothing"), enabled = false}
	end

	if ((session.money or 0) > 0) then
		rows[#rows + 1] = {label = L("invPanelTakeMoney"), detail = ix.currency.Get(session.money), action = "moneyLevel",
			mode = "take", icon = ActionIcon("icon16/money.png")}
	end

	rows[#rows + 1] = {
		label = L("invPanelYours", L(self:GetFullness(own))),
		detail = ix.currency.Get(character:GetMoney()),
		heading = true
	}

	local mine = 0

	for _, item in ipairs(SortItems(table.ClearKeys(own:GetItems(true)))) do
		-- a bag is never put inside itself
		if (session.kind == "carried" and item:GetID() == session.bagItemID) then
			continue
		end

		local row = ItemRow(item, own, IsStack(item) and "amountLevel" or "move")
		row.targetID = other:GetID()

		if (item:GetData("equip")) then
			row.dim = true
			row.action = "equipped"
		end

		rows[#rows + 1] = row
		mine = mine + 1
	end

	if (mine == 0) then
		rows[#rows + 1] = {label = L("invPanelNothing"), enabled = false}
	end

	if (session.money != nil and character:GetMoney() > 0) then
		rows[#rows + 1] = {label = L("invPanelLeaveMoney"), detail = ix.currency.Get(character:GetMoney()),
			action = "moneyLevel", mode = "give", icon = ActionIcon("icon16/money_add.png")}
	end

	return rows, session.name
end

--- An item's actions: what its old right-click menu offered, Combine with..., Examine and Drop.
function PLUGIN:BuildItem(session, level)
	local item, inventory = Locate(session, level.itemID)

	if (!item) then
		return
	end

	local rows = {Back()}
	local actions, drop = self:GetItemActions(item, LocalPlayer())

	for _, action in ipairs(actions) do
		local info = action.info
		local row = {
			label = L(info.name or action.key),
			icon = ActionIcon(info.icon or "icon16/brick.png"),
			action = "function",
			key = action.key,
			itemID = item:GetID(),
			invID = inventory:GetID()
		}

		if (item.isBag and action.key == "View") then
			row.action = "openBag"
		elseif (info.isMulti and #MultiOptions(item, info) > 0) then
			row.action = "multiLevel"
		end

		rows[#rows + 1] = row
	end

	local items = {}

	for _, own in ipairs(OwnInventories()) do
		for _, other in pairs(own:GetItems(true)) do
			items[#items + 1] = other
		end
	end

	if (#self:GetCombineTargets(item, items, LocalPlayer()) > 0) then
		rows[#rows + 1] = {label = L("invPanelCombine"), action = "combineLevel", itemID = item:GetID(),
			icon = ActionIcon("icon16/arrow_join.png")}
	end

	rows[#rows + 1] = {label = L("interactExamine"), action = "examine", itemID = item:GetID(),
		icon = ActionIcon("icon16/magnifier.png")}

	if (drop) then
		rows[#rows + 1] = {label = L(drop.info.name or "drop"), icon = ActionIcon(drop.info.icon or "icon16/world.png"),
			action = "function", key = "drop", itemID = item:GetID(), invID = inventory:GetID()}
	end

	local detail = Detail(item)

	return rows, detail and (item:GetName() .. " (" .. detail .. ")") or item:GetName()
end

-- The sub-options of an isMulti function (Split's amounts, for one).
function PLUGIN:BuildMulti(session, level)
	local item, inventory = Locate(session, level.itemID)
	local info = item and item.functions and item.functions[level.key]

	if (!info) then
		return
	end

	local rows = {Back()}

	for index, sub in ipairs(MultiOptions(item, info)) do
		rows[#rows + 1] = {label = L(sub.name or "subOption"), action = "sub", key = level.key, index = index,
			itemID = item:GetID(), invID = inventory:GetID()}
	end

	if (#rows == 1) then
		return
	end

	return rows, L(info.name or level.key)
end

-- What an item can be combined with, as dragging it onto them did.
function PLUGIN:BuildCombine(session, level)
	local item = Locate(session, level.itemID)

	if (!item) then
		return
	end

	local items = {}

	for _, own in ipairs(OwnInventories()) do
		for _, other in pairs(own:GetItems(true)) do
			items[#items + 1] = other
		end
	end

	local rows = {Back()}

	for _, target in ipairs(self:GetCombineTargets(item, items, LocalPlayer())) do
		rows[#rows + 1] = {label = target:GetName(), detail = Detail(target), icon = ItemIcon(target), action = "combine",
			itemID = item:GetID(), targetID = target:GetID()}
	end

	if (#rows == 1) then
		return
	end

	return rows, L("invPanelCombineWith", item:GetName())
end

-- A bag inside a storage: take all of it, or one thing out of it.
function PLUGIN:BuildInnerBag(session, level)
	local bag = Locate(session, level.itemID)
	local inner = bag and bag.isBag and bag:GetInventory()
	local own = LocalPlayer():GetCharacter():GetInventory()

	if (!inner) then
		return
	end

	local rows = {
		Back(),
		{label = L("invPanelTakeWhole", bag:GetName()), action = "move", itemID = bag:GetID(), targetID = own:GetID(),
			icon = ItemIcon(bag)},
		{label = L("invPanelInside"), detail = L(self:GetFullness(inner)), heading = true}
	}

	local contents = SortItems(table.ClearKeys(inner:GetItems(true)))

	for _, item in ipairs(contents) do
		rows[#rows + 1] = ItemRow(item, inner, IsStack(item) and "amountLevel" or "move")
		rows[#rows].targetID = own:GetID()
	end

	if (#contents == 0) then
		rows[#rows + 1] = {label = L("invPanelNothing"), enabled = false}
	end

	return rows, bag:GetName()
end

-- How much of a stack to move across: all of it, or one of Split's amounts.
function PLUGIN:BuildAmount(session, level)
	local item = Locate(session, level.itemID)

	if (!item or !IsStack(item)) then
		return
	end

	local rows = {
		Back(),
		{label = L("invPanelMoveAll", ix.stack.Format(item, ix.stack.GetQuantity(item))), action = "moveAmount",
			itemID = item:GetID(), targetID = level.targetID}
	}

	for _, amount in ipairs(ix.stack.GetSplitAmounts(item)) do
		rows[#rows + 1] = {label = L("invPanelMovePart", ix.stack.Format(item, amount)), action = "moveAmount",
			amount = amount, itemID = item:GetID(), targetID = level.targetID}
	end

	return rows, item:GetName()
end

-- Money to take from the storage or leave in it: all of it, or a preset amount.
function PLUGIN:BuildMoney(session, level)
	local available = level.mode == "take" and (session.money or 0) or LocalPlayer():GetCharacter():GetMoney()

	if (available <= 0) then
		return
	end

	local rows = {
		Back(),
		{label = L("invPanelMoneyAll", ix.currency.Get(available)), action = "money", mode = level.mode, amount = available}
	}

	local amounts = {}

	for _, amount in ipairs(self.moneyAmounts) do
		if (amount < available) then
			amounts[#amounts + 1] = amount
		end
	end

	for i = math.max(#amounts - 3, 1), #amounts do
		rows[#rows + 1] = {label = ix.currency.Get(amounts[i]), action = "money", mode = level.mode, amount = amounts[i]}
	end

	return rows, L(level.mode == "take" and "invPanelTakeMoney" or "invPanelLeaveMoney")
end

-- The rows and title of the session's current level, or nil when what it is about has gone.
function PLUGIN:BuildLevel(session)
	local level = session.levels[#session.levels]

	if (!LocalPlayer():GetCharacter()) then
		return
	end

	if (level.kind == "top") then
		if (session.kind == "bag") then
			return self:BuildBag()
		end

		return self:BuildPair(session)
	elseif (level.kind == "item") then
		return self:BuildItem(session, level)
	elseif (level.kind == "multi") then
		return self:BuildMulti(session, level)
	elseif (level.kind == "combine") then
		return self:BuildCombine(session, level)
	elseif (level.kind == "amount") then
		return self:BuildAmount(session, level)
	elseif (level.kind == "money") then
		return self:BuildMoney(session, level)
	elseif (level.kind == "innerBag") then
		return self:BuildInnerBag(session, level)
	end
end

--- Rebuilds the open panel: at once when the level changed (scrolled to the top), otherwise only when what it shows
-- changed. A level whose item has gone gives way to the one below it.
function PLUGIN:Rebuild(session, bLevelChanged)
	local panel = session.panel

	if (!panel:IsOpen()) then
		return
	end

	local rows, title = self:BuildLevel(session)

	while (!rows and #session.levels > 1) do
		table.remove(session.levels)
		bLevelChanged = true
		rows, title = self:BuildLevel(session)
	end

	session.refresh = RealTime() + self.refreshInterval

	if (!rows) then
		panel:Close()
		return
	end

	local signature = Signature(title, rows)

	panel.level = session.levels[#session.levels].kind

	if (bLevelChanged) then
		panel:SetLevel(rows, title)
	elseif (signature != session.signature) then
		panel.title = title
		panel:SetRows(rows)
	end

	session.signature = signature
end

function PLUGIN:Push(session, level)
	session.levels[#session.levels + 1] = level
	self:Rebuild(session, true)
end

-- Back a level; at the top of a carried bag, back to the bag. Returns whether it went anywhere.
function PLUGIN:Pop(session)
	if (#session.levels > 1) then
		table.remove(session.levels)
		self:Rebuild(session, true)

		return true
	end

	if (session.kind == "carried") then
		return self:OpenBag() != nil
	end

	return false
end

function PLUGIN:CanRequest()
	if (RealTime() < (self.nextRequest or 0)) then
		return false
	end

	self.nextRequest = RealTime() + self.requestInterval

	return true
end

-- Asks the server to move an item; false when it was not asked (too soon after the last request).
function PLUGIN:RequestMove(itemID, targetID, amount)
	if (!self:CanRequest()) then
		return false
	end

	net.Start("ixInventoryPanelMove")
		net.WriteUInt(itemID, 32)
		net.WriteUInt(targetID, 32)
		net.WriteBool(amount != nil)

		if (amount != nil) then
			net.WriteDouble(amount)
		end
	net.SendToServer()

	return true
end

function PLUGIN:Choose(session, row)
	local action = row.action

	if (action == "back") then
		self:Pop(session)
	elseif (action == "item") then
		self:Push(session, {kind = "item", itemID = row.itemID})
	elseif (action == "tidy") then
		if (self:CanRequest()) then
			net.Start("ixInventoryPanelTidy")
			net.SendToServer()
		end
	elseif (action == "multiLevel") then
		self:Push(session, {kind = "multi", itemID = row.itemID, key = row.key})
	elseif (action == "combineLevel") then
		self:Push(session, {kind = "combine", itemID = row.itemID})
	elseif (action == "amountLevel") then
		self:Push(session, {kind = "amount", itemID = row.itemID, targetID = row.targetID})
	elseif (action == "moneyLevel") then
		self:Push(session, {kind = "money", mode = row.mode})
	elseif (action == "move") then
		self:RequestMove(row.itemID, row.targetID)
	elseif (action == "moveAmount") then
		if (self:RequestMove(row.itemID, row.targetID, row.amount)) then
			self:Pop(session)
		end
	elseif (action == "bagLevel") then
		self:Push(session, {kind = "innerBag", itemID = row.itemID})
	elseif (action == "menu") then
		if (session.panel:IsOpen()) then
			session.panel:Close()
		end

		self:ToggleMenu()
	elseif (action == "equipped") then
		Sound("cancel")
		Say(L("invPanelTakeOffFirst"))
	elseif (action == "money") then
		if (self:CanRequest()) then
			net.Start(row.mode == "take" and "ixStorageMoneyTake" or "ixStorageMoneyGive")
				net.WriteUInt(session.otherID, 32)
				net.WriteUInt(math.max(math.floor(row.amount), 0), 32)
			net.SendToServer()
		end

		self:Pop(session)
	else
		local item = Locate(session, row.itemID)

		if (!item) then
			return
		end

		if (action == "function") then
			local info = item.functions[row.key]

			if (info) then
				RunFunction(item, row.invID, row.key, info)
			end
		elseif (action == "sub") then
			local info = item.functions[row.key]
			local sub = info and MultiOptions(item, info)[row.index]

			if (sub) then
				RunFunction(item, row.invID, row.key, sub, sub.data)
				self:Pop(session)
			end
		elseif (action == "combine") then
			local target, targetInventory = Locate(session, row.targetID)
			local info = target and target.functions and target.functions.combine

			if (info) then
				target.player = LocalPlayer()

				if (info.sound) then
					surface.PlaySound(info.sound)
				end

				InventoryAction("combine", target:GetID(), targetInventory:GetID(), {item:GetID()})
				target.player = nil
				self:Pop(session)
			end
		elseif (action == "examine") then
			local interaction = ix.plugin.list.interaction

			if (interaction and interaction.ExamineItem) then
				interaction:ExamineItem(item)
			end
		elseif (action == "openBag") then
			self:OpenCarried(item)
		end
	end

	-- whatever changed comes back from the server; look again soon
	if (self.session == session) then
		session.refresh = math.min(session.refresh or 0, RealTime() + 0.1)
	end
end

--- Opens a session's world panel and keeps it. `info` adds to what ix.worldui.Open gets.
function PLUGIN:OpenSession(session, info)
	session.levels = {{kind = "top"}}

	local rows, title = self:BuildLevel(session)

	if (!rows) then
		return
	end

	info.title = title
	info.rows = rows
	info.bKeepOpen = true
	info.maxRows = self.maxRows
	info.name = session.kind
	info.OnSelect = function(_, row)
		self:Choose(session, row)
	end
	info.OnBack = function()
		return self:Pop(session)
	end
	info.OnClose = function()
		if (self.session == session) then
			self.session = nil
		end

		-- the server is told however it closed, as the window did; not when the server itself closed it, or when
		-- it opened another storage in its place
		if (session.kind == "storage" and !session.bExpired and !session.bReplaced) then
			net.Start("ixStorageClose")
			net.SendToServer()
		end
	end

	local previous = self.session

	if (previous and info.bFromServer) then
		previous.bReplaced = true
	end

	session.panel = ix.worldui.Open(info)
	session.panel.level = "top"
	session.signature = Signature(title, rows)
	session.refresh = RealTime() + self.refreshInterval

	self.session = session

	return session
end

--- Whether the local player can handle their things now: with a character, alive, untied, on their feet, no menu.
function PLUGIN:CanUseBag(client)
	local interaction = ix.plugin.list.interaction

	if (interaction and interaction.CanInteract) then
		return interaction:CanInteract(client)
	end

	return client:Alive() and client:GetCharacter() != nil and !client:IsRestricted()
end

--- The bag, held in front of the player.
function PLUGIN:OpenBag()
	local client = LocalPlayer()

	if (!client:GetCharacter() or !client:GetCharacter():GetInventory() or !self:CanUseBag(client)) then
		return
	end

	return self:OpenSession({kind = "bag"}, {held = true})
end

--- A bag the player carries, opened beside their own inventory, held in front of them like the bag.
function PLUGIN:OpenCarried(item)
	local index = item:GetData("id")

	if (!index or !ix.item.inventories[index]) then
		return
	end

	return self:OpenSession({kind = "carried", otherID = index, bagItemID = item:GetID(), name = item:GetName()},
		{held = true})
end

--- A storage the server opened (a container, a corpse, a searched player), at the thing.
function PLUGIN:OpenStorage(id, entity, name, data)
	return self:OpenSession({
		kind = "storage",
		otherID = id,
		entity = entity,
		name = name != "" and name or L("invPanelStorage"),
		money = isnumber(data.money) and data.money or nil
	}, {anchor = entity, reach = self.storageReach, bFromServer = true})
end

function PLUGIN:GetSession()
	local session = self.session

	if (session and session.panel:IsOpen()) then
		return session
	end
end

function PLUGIN:Think()
	local session = self.session

	if (session and session.panel:IsOpen() and RealTime() >= (session.refresh or 0)) then
		self:Rebuild(session)
	end
end

-- Tab: the bag, instead of Helix's menu. Tab again (or right click, or Use off the panel) puts it away.
function PLUGIN:ToggleBag()
	local client = LocalPlayer()

	if (!IsValid(client) or !client:GetCharacter()) then
		return
	end

	local session = self:GetSession()

	if (session) then
		session.panel:Close()
	else
		self:OpenBag()
	end
end

-- The gamemode's own ScoreboardShow (helix/gamemode/core/hooks/cl_hooks.lua), which opens the menu, is replaced
-- rather than a plugin hook returning a value: that would stop the plugins that run after it (wepselect hides its
-- weapon list there).
function PLUGIN:WrapScoreboard()
	local gamemode = GAMEMODE or GM

	if (!gamemode or gamemode.ixInventoryPanelScoreboard) then
		return
	end

	gamemode.ixInventoryPanelScoreboard = gamemode.ScoreboardShow or true

	function gamemode:ScoreboardShow()
		PLUGIN:ToggleBag()
	end
end

-- The rest of Helix's menu, without its Inventory tab, on the help key (F1, gm_showhelp), which Helix leaves unused.
function PLUGIN:ToggleMenu()
	if (IsValid(ix.gui.menu) and !ix.gui.menu.bClosing) then
		ix.gui.menu:Remove()
	elseif (LocalPlayer():GetCharacter() and !(IsValid(ix.gui.characterMenu) and !ix.gui.characterMenu:IsClosing())) then
		vgui.Create("ixMenu")
	end
end

function PLUGIN:PlayerBindPress(client, bind, bPressed)
	if (bPressed and bind:find("gm_showhelp", 1, true)) then
		self:ToggleMenu()

		return true
	end
end

-- No Inventory tab in the menu: the bag is in the world.
function PLUGIN:CanPlayerViewInventory()
	return false
end

-- While the menu has the keyboard, the help key closes it as Tab does.
function PLUGIN:WrapMenu()
	local menu = vgui.GetControlTable("ixMenu")

	if (!menu or menu.ixInventoryPanelKeys) then
		return
	end

	local original, think = menu.OnKeyCodePressed, menu.Think

	menu.ixInventoryPanelKeys = true

	function menu:OnKeyCodePressed(key)
		local binding = input.LookupKeyBinding(key)

		if (isstring(binding) and binding:find("gm_showhelp", 1, true)) then
			self:Remove()
			return
		end

		return original(self, key)
	end

	-- a text field in the menu (the settings search) takes key presses before the menu does; the key itself is
	-- still watched, as Helix's own Think watches Tab
	function menu:Think(...)
		local binding = input.LookupBinding("gm_showhelp")
		local code = binding and input.GetKeyCode(binding)

		if (code and code > 0 and !self.bClosing) then
			local bDown = input.IsKeyDown(code)

			-- the press that opened the menu does not close it
			if (bDown and self.ixHelpKeyDown == false) then
				self:Remove()
			end

			self.ixHelpKeyDown = bDown
		end

		return think(self, ...)
	end
end

net.Receive("ixInventoryPanelResult", function()
	local bSuccess = net.ReadBool()
	local phrase = net.ReadString()
	local argument = net.ReadString()

	Sound(bSuccess and "complete" or "cancel")

	if (phrase != "" and (!bSuccess or phrase == "invPanelTidied")) then
		Say(L(phrase, argument))
	end
end)

-- Helix's storage receivers (helix/gamemode/core/libs/sh_storage.lua) are replaced: an opened storage shows the
-- world panel instead of ixStorageView, the server closing it closes the panel, and its money follows.
PLUGIN.receivers = {}

PLUGIN.receivers.ixstorageopen = function()
	if (IsValid(ix.gui.menu)) then
		net.Start("ixStorageClose")
		net.SendToServer()
		return
	end

	local id = net.ReadUInt(32)
	local entity = net.ReadEntity()
	local name = net.ReadString()
	local data = net.ReadTable()
	local inventory = ix.item.inventories[id]

	if (!IsValid(entity) or !inventory or !inventory.slots or !LocalPlayer():GetCharacter() or
		!PLUGIN:OpenStorage(id, entity, name, data)) then
		-- nothing could be shown: let go of it, as closing would
		net.Start("ixStorageClose")
		net.SendToServer()
	end
end

PLUGIN.receivers.ixstorageexpired = function()
	local id = net.ReadUInt(32)
	local session = PLUGIN:GetSession()

	if (session and session.kind == "storage" and session.otherID == id) then
		session.bExpired = true
		session.panel:Close()
	end

	if (IsValid(ix.gui.openedStorage)) then
		ix.gui.openedStorage:Remove()
	end

	-- as Helix does: the client forgets the storage's contents (never the player's own inventory)
	local character = LocalPlayer():GetCharacter()
	local own = character and character:GetInventory()

	if (id != 0 and !(own and own:GetID() == id)) then
		ix.item.inventories[id] = nil
	end
end

PLUGIN.receivers.ixstoragemoneyupdate = function()
	local id = net.ReadUInt(32)
	local amount = net.ReadUInt(32)
	local session = PLUGIN:GetSession()

	if (session and session.kind == "storage" and session.otherID == id) then
		session.money = amount
		PLUGIN:Rebuild(session)
	end
end

function PLUGIN:WrapReceivers()
	for name, callback in pairs(self.receivers) do
		net.Receivers[name] = callback
	end
end

-- /Menu (sv_plugin.lua)
net.Receive("ixInventoryPanelMenu", function()
	if (!(IsValid(ix.gui.menu) and !ix.gui.menu.bClosing)) then
		PLUGIN:ToggleMenu()
	end
end)

function PLUGIN:InitializedPlugins()
	self:WrapReceivers()
	self:WrapMenu()
	self:WrapScoreboard()
end

if (net.Receivers.ixstorageopen) then
	PLUGIN:WrapReceivers()
end

PLUGIN:WrapMenu()
PLUGIN:WrapScoreboard()
