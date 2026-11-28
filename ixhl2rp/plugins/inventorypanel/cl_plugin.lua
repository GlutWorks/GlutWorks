local PLUGIN = PLUGIN

-- Seconds between rebuilds of what an open case holds, and the shortest time between two requests.
PLUGIN.refreshInterval = 0.25
PLUGIN.requestInterval = 0.3
-- A storage's case closes a little nearer than the server's reach (sv_plugin.lua), so the client lets go first.
PLUGIN.storageReach = 120
-- Money that can be taken from or left in a storage at once, besides all of it: the largest four below what there is.
PLUGIN.moneyAmounts = {1, 5, 10, 25, 50, 100, 250, 500, 1000, 5000}
-- How each side of the case is lined (ix.worldcase.styles): yours, and the other side by what it is.
PLUGIN.caseStyles = {own = "lined", container = "wood", body = "cloth", bag = "metal"}

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

local function IsStack(item)
	return ix.stack != nil and ix.stack.IsStackable(item)
end

-- What the label at an item says under its name: the stack's quantity, whether it is worn or equipped, and how full a
-- bag is.
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
			parts[#parts + 1] = L(PLUGIN:GetFullness(inventory)):utf8lower()
		end
	end

	return #parts > 0 and table.concat(parts, ", ") or nil
end

-- What an inventory holds as the client knows it: {item, x, y} for each item, at its top left cell (the client keeps
-- an item only there; helix/gamemode/core/libs/sh_item.lua), in grid order.
local function ItemsOf(inventory)
	local list, seen = {}, {}

	for x, column in pairs(inventory and inventory.slots or {}) do
		for y, item in pairs(column) do
			if (istable(item) and item.id) then
				local entry = seen[item.id]

				if (!entry) then
					entry = {item = item, x = x, y = y}
					seen[item.id] = entry
					list[#list + 1] = entry
				else
					entry.x, entry.y = math.min(entry.x, x), math.min(entry.y, y)
				end
			end
		end
	end

	table.sort(list, function(a, b)
		if (a.y != b.y) then return a.y < b.y end
		if (a.x != b.x) then return a.x < b.x end

		return a.item.id < b.item.id
	end)

	return list
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

--- The local character's inventory.
function PLUGIN:GetOwnInventory()
	local character = LocalPlayer():GetCharacter()

	return character and character:GetInventory()
end

--- The inventory a grid of the session's case shows: "own", or "theirs" (the storage, the bag opened in its place,
-- or the carried bag).
function PLUGIN:GetGridInventory(session, gridID)
	if (gridID == "own") then
		return self:GetOwnInventory()
	end

	return ix.item.inventories[session.innerID or session.otherID or 0]
end

--- Whether an inventory is the local character's own or a bag in it (where an item's own functions run).
function PLUGIN:IsOwnInventory(inventory)
	local own = self:GetOwnInventory()

	return own != nil and inventory != nil and (own == inventory or table.HasValue(own:GetBags(), inventory:GetID()))
end

--- The grids of a session's case: theirs on the left when there is another side, yours on the right with the
-- money pocket.
function PLUGIN:GetGrids(session)
	local own = self:GetOwnInventory()
	local grids = {}
	local other = session.otherID and self:GetGridInventory(session, "theirs")

	if (other) then
		local style = self.caseStyles.container

		if (session.kind == "carried" or session.innerID) then
			style = self.caseStyles.bag
		elseif (IsValid(session.entity) and (session.entity:IsPlayer() or session.entity:IsRagdoll())) then
			style = self.caseStyles.body
		end

		grids[1] = {id = "theirs", w = other.w, h = other.h, style = style, pocket = session.money != nil and !session.innerID,
			title = session.innerID and session.innerName or session.name}
	end

	grids[#grids + 1] = {id = "own", w = own.w, h = own.h, style = self.caseStyles.own, pocket = true}

	return grids
end

--- What the case shows: an object for each item where it lies, and the money in the pockets.
function PLUGIN:BuildObjects(session)
	local objects = {}

	for _, gridID in ipairs({"theirs", "own"}) do
		local inventory = (gridID == "own" or session.otherID) and self:GetGridInventory(session, gridID)

		if (inventory) then
			for _, entry in ipairs(ItemsOf(inventory)) do
				local item = entry.item

				objects[#objects + 1] = {
					key = item.id,
					grid = gridID,
					x = entry.x,
					y = entry.y,
					w = item.width or 1,
					h = item.height or 1,
					model = item:GetModel(),
					skin = item:GetSkin(),
					material = item:GetMaterial(),
					bodygroups = istable(item.bodygroups) and item.bodygroups or nil,
					label = item:GetName(),
					detail = Detail(item),
					amount = IsStack(item) and ix.stack.Format(item, ix.stack.GetQuantity(item)) or nil,
					invID = inventory:GetID()
				}
			end
		end
	end

	local money = LocalPlayer():GetCharacter():GetMoney()

	if (money > 0) then
		objects[#objects + 1] = {key = "money:own", grid = "own", pocket = true, model = ix.currency.model,
			label = ix.currency.Get(money), money = money}
	end

	if (!session.innerID and (session.money or 0) > 0) then
		objects[#objects + 1] = {key = "money:theirs", grid = "theirs", pocket = true, model = ix.currency.model,
			label = ix.currency.Get(session.money), money = session.money}
	end

	return objects
end

local function Signature(objects)
	local parts = {}

	for i, object in ipairs(objects) do
		parts[i] = table.concat({tostring(object.key), object.grid, tostring(object.x), tostring(object.y),
			tostring(object.model), tostring(object.skin), tostring(object.material),
			istable(object.bodygroups) and util.TableToJSON(object.bodygroups) or "", tostring(object.label),
			tostring(object.detail)}, "|")
	end

	return table.concat(parts, "\n")
end

--- Shows what the session's inventories hold now, when it changed (or at once with `bForce`).
function PLUGIN:Refresh(session, bForce)
	local case = session.case

	session.refresh = RealTime() + self.refreshInterval

	if (!case or !case:IsOpen() or !LocalPlayer():GetCharacter()) then
		return
	end

	-- an opened bag that is no longer where it was opened from (dropped, put away, taken by someone, or its
	-- inventory forgotten) is shown no more: a carried bag's case goes back to the bag, a bag opened inside a
	-- storage back to the storage's own grid
	if (session.kind == "carried" and !self:IsBagStillThere(session.bagItemID, session.otherID, self:GetOwnInventory())) then
		self:OpenBag()
		return
	end

	if (session.innerID and !self:IsBagStillThere(session.innerItemID, session.innerID,
		ix.item.inventories[session.otherID or 0])) then
		session.innerID, session.innerName, session.innerItemID = nil, nil, nil
		case:SetGrids(self:GetGrids(session))
		bForce = true
	end

	local objects = self:BuildObjects(session)
	local signature = Signature(objects)

	if (bForce or signature != session.signature) then
		session.signature = signature
		case:SetObjects(objects)
	end
end

-- The item an object of the case is, and the inventory it is in.
function PLUGIN:GetObjectItem(object)
	local item = isnumber(object.key) and ix.item.instances[object.key]
	local inventory = object.invID and ix.item.inventories[object.invID]

	if (item and inventory) then
		return item, inventory
	end
end

--- Whether the bag item `itemID`, whose inventory is `bagInventoryID`, still lies in `inventory`'s own grid and
-- its inventory is still known.
function PLUGIN:IsBagStillThere(itemID, bagInventoryID, inventory)
	local item = itemID and ix.item.instances[itemID]

	if (!item or !ix.item.inventories[bagInventoryID or 0] or !inventory or item:GetData("id") != bagInventoryID) then
		return false
	end

	for _, entry in ipairs(ItemsOf(inventory)) do
		if (entry.item.id == itemID) then
			return true
		end
	end

	return false
end

-- Whether a request may go now; one too soon after the last is not sent, and the player hears it refused (the
-- carried thing goes back), never nothing at all.
function PLUGIN:CanRequest()
	if (RealTime() < (self.nextRequest or 0)) then
		Sound("cancel")
		return false
	end

	self.nextRequest = RealTime() + self.requestInterval

	return true
end

-- Asks the server to move an item: into another inventory (any free cell, or the cell `x`, `y`), or to the cell
-- `x`, `y` of its own; false when it was not asked (too soon after the last request).
function PLUGIN:RequestMove(itemID, targetID, amount, x, y)
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

		net.WriteBool(x != nil)

		if (x != nil) then
			net.WriteUInt(x, 8)
			net.WriteUInt(y, 8)
		end
	net.SendToServer()

	return true
end

-- Asks the server to combine an item with the one it was put down onto.
function PLUGIN:RequestCombine(itemID, targetID)
	if (!self:CanRequest()) then
		return false
	end

	net.Start("ixInventoryPanelCombine")
		net.WriteUInt(itemID, 32)
		net.WriteUInt(targetID, 32)
	net.SendToServer()

	return true
end

function PLUGIN:RequestMoney(session, mode, amount)
	if (!self:CanRequest()) then
		return false
	end

	net.Start(mode == "take" and "ixStorageMoneyTake" or "ixStorageMoneyGive")
		net.WriteUInt(session.otherID, 32)
		net.WriteUInt(math.max(math.floor(amount), 0), 32)
	net.SendToServer()

	return true
end

--- Whether money can be moved between the player and the other side: a storage that keeps money is open (not a bag
-- opened inside it).
function PLUGIN:CanMoveMoney(session)
	return session.kind == "storage" and session.money != nil and !session.innerID
end

--- Where a tap or a move sends an item from its grid: the other side, when the case has one.
function PLUGIN:GetOtherSide(session, object)
	if (!session.otherID) then
		return
	end

	return self:GetGridInventory(session, object.grid == "own" and "theirs" or "own")
end

--- A tap of Use on a thing in the case. With another side open it moves across (to any free cell; a stack merges
-- into stacks there; money is only counted); otherwise it is the item's obvious action (PLUGIN:GetTapAction; a carried
-- bag's View opens it beside your own), or its options when it has none.
function PLUGIN:Tap(session, object)
	local character = LocalPlayer():GetCharacter()

	-- a tap on money only says how much it is: it moves by an amount chosen on purpose (held Use, or carried across)
	if (object.money) then
		if (object.grid == "theirs") then
			Say(L("invPanelMoneyThere", ix.currency.Get(session.money or 0)))
		else
			Say(L("invPanelYouCarry", ix.currency.Get(character:GetMoney())))
		end

		return
	end

	local item, inventory = self:GetObjectItem(object)

	if (!item) then
		return
	end

	local other = self:GetOtherSide(session, object)

	if (other) then
		-- the open bag itself: closes it
		if (session.kind == "carried" and item:GetID() == session.bagItemID) then
			self:Back(session)
			return
		end

		if (item:GetData("equip")) then
			Sound("cancel")
			Say(L("invPanelTakeOffFirst"))
			return
		end

		self:RequestMove(item:GetID(), other:GetID())
		return
	end

	local action = self:GetTapAction(item, LocalPlayer())

	if (!action) then
		self:OpenOptions(session, object)
		return
	end

	if (item.isBag and action.key == "View") then
		self:OpenCarried(item)
	else
		RunFunction(item, inventory:GetID(), action.key, action.info)
	end
end

--- The rows of an object's options at a level ({kind = "top" | "multi" | "amount"}), and their title.
function PLUGIN:BuildOptions(session, object, level)
	local character = LocalPlayer():GetCharacter()

	-- money: a few amounts, and all of it last, chosen on purpose
	if (object.money) then
		if (!self:CanMoveMoney(session)) then
			return
		end

		local mode = object.grid == "theirs" and "take" or "give"
		local available = mode == "take" and (session.money or 0) or character:GetMoney()

		if (available <= 0) then
			return
		end

		local rows = {}
		local amounts = {}

		for _, amount in ipairs(self.moneyAmounts) do
			if (amount < available) then
				amounts[#amounts + 1] = amount
			end
		end

		for i = math.max(#amounts - 3, 1), #amounts do
			rows[#rows + 1] = {label = ix.currency.Get(amounts[i]), action = "money", mode = mode, amount = amounts[i]}
		end

		rows[#rows + 1] = {label = L("invPanelMoneyAll", ix.currency.Get(available)), action = "money", mode = mode,
			amount = available}

		return rows, L(mode == "take" and "invPanelTakeMoney" or "invPanelLeaveMoney")
	end

	local item, inventory = self:GetObjectItem(object)

	if (!item) then
		return
	end

	local detail = Detail(item)
	local title = detail and (item:GetName() .. " (" .. detail .. ")") or item:GetName()
	local back = {label = L("invPanelBack"), action = "back"}

	if (level.kind == "multi") then
		local info = item.functions and item.functions[level.key]
		local rows = {back}

		for index, sub in ipairs(info and MultiOptions(item, info) or {}) do
			rows[#rows + 1] = {label = L(sub.name or "subOption"), action = "sub", key = level.key, index = index}
		end

		return #rows > 1 and rows or nil, info and L(info.name or level.key) or title
	elseif (level.kind == "amount") then
		local rows = {back}

		for _, amount in ipairs(IsStack(item) and ix.stack.GetSplitAmounts(item) or {}) do
			rows[#rows + 1] = {label = L(object.grid == "own" and "invPanelPutAmount" or "invPanelTakeAmount",
				ix.stack.Format(item, amount)), action = "moveAmount", amount = amount, targetID = level.targetID}
		end

		return #rows > 1 and rows or nil, title
	end

	local rows = {}
	local other = self:GetOtherSide(session, object)
	local bOwn = self:IsOwnInventory(inventory)

	-- across to the other side: all of it, or part of a stack
	if (other and !item:GetData("equip") and !(session.kind == "carried" and item:GetID() == session.bagItemID)) then
		local bPutting = object.grid == "own"
		local name = bPutting and (session.innerID and session.innerName or session.name) or nil

		rows[#rows + 1] = {label = bPutting and L("invPanelPutIn", name or L("invPanelStorage")) or L("invPanelTake"),
			action = "move", targetID = other:GetID()}

		if (IsStack(item) and #ix.stack.GetSplitAmounts(item) > 0) then
			rows[#rows + 1] = {label = L(bPutting and "invPanelPutSome" or "invPanelTakeSome"), action = "amountLevel",
				targetID = other:GetID()}
		end
	end

	local drop

	if (bOwn) then
		local actions

		actions, drop = self:GetItemActions(item, LocalPlayer())

		for _, action in ipairs(actions) do
			local info = action.info
			local row = {label = L(info.name or action.key), action = "function", key = action.key}

			if (item.isBag and action.key == "View") then
				row.action = "openBag"
			elseif (info.isMulti and #MultiOptions(item, info) > 0) then
				row.action = "multiLevel"
			end

			rows[#rows + 1] = row
		end
	elseif (item.isBag and item:GetData("id") and ix.item.inventories[item:GetData("id")]) then
		-- a bag in a storage opens in place of the storage, as the old window let it be opened
		rows[#rows + 1] = {label = L("invPanelOpenBag"), action = "openInner"}
	end

	rows[#rows + 1] = {label = L("interactExamine"), action = "examine"}

	if (drop) then
		rows[#rows + 1] = {label = L(drop.info.name or "drop"), action = "function", key = "drop"}
	end

	return rows, title
end

--- Holding Use on a thing in the case: its options on a panel beside it, which follows it (or at `place` of the case,
-- where money carried across was let go).
function PLUGIN:OpenOptions(session, object, place)
	local case = session.case
	local level = {kind = "top"}
	local rows, title = self:BuildOptions(session, object, level)

	if (!rows) then
		if (object.money) then
			Say(L("invPanelYouCarry", ix.currency.Get(LocalPlayer():GetCharacter():GetMoney())))
		end

		return
	end

	local panel

	panel = ix.worldui.Open({
		position = case:GetAimPos(place or object) or case.center,
		title = title,
		rows = rows,
		bKeepOpen = true,
		maxRows = 8,
		name = "options",
		OnSelect = function(_, row)
			self:ChooseOption(session, object, panel, row)
		end,
		OnBack = function()
			return self:PopOption(session, object, panel)
		end
	})

	panel.level = "top"
	panel.optionLevels = {level}
	case:FollowObject(panel, object, place)

	return panel
end

function PLUGIN:PushOption(session, object, panel, level)
	local rows, title = self:BuildOptions(session, object, level)

	if (!rows) then
		return
	end

	panel.optionLevels[#panel.optionLevels + 1] = level
	panel.level = level.kind
	panel:SetLevel(rows, title)
end

function PLUGIN:PopOption(session, object, panel)
	if (#panel.optionLevels <= 1) then
		return false
	end

	table.remove(panel.optionLevels)

	local level = panel.optionLevels[#panel.optionLevels]
	local rows, title = self:BuildOptions(session, object, level)

	if (!rows) then
		panel:Close()
		return true
	end

	panel.level = level.kind
	panel:SetLevel(rows, title)

	return true
end

function PLUGIN:ChooseOption(session, object, panel, row)
	local action = row.action

	if (action == "back") then
		self:PopOption(session, object, panel)
		return
	elseif (action == "multiLevel") then
		self:PushOption(session, object, panel, {kind = "multi", key = row.key})
		return
	elseif (action == "amountLevel") then
		self:PushOption(session, object, panel, {kind = "amount", targetID = row.targetID})
		return
	end

	panel:Close()

	if (action == "money") then
		self:RequestMoney(session, row.mode, row.amount)
		return
	end

	local item, inventory = self:GetObjectItem(object)

	if (!item) then
		return
	end

	if (action == "function") then
		local info = item.functions[row.key]

		if (info) then
			RunFunction(item, inventory:GetID(), row.key, info)
		end
	elseif (action == "sub") then
		local info = item.functions[row.key]
		local sub = info and MultiOptions(item, info)[row.index]

		if (sub) then
			RunFunction(item, inventory:GetID(), row.key, sub, sub.data)
		end
	elseif (action == "move") then
		self:RequestMove(item:GetID(), row.targetID)
	elseif (action == "moveAmount") then
		self:RequestMove(item:GetID(), row.targetID, row.amount)
	elseif (action == "examine") then
		local interaction = ix.plugin.list.interaction

		if (interaction and interaction.ExamineItem) then
			interaction:ExamineItem(item)
		end
	elseif (action == "openBag") then
		self:OpenCarried(item)
	elseif (action == "openInner") then
		self:OpenInner(session, item)
	end

	session.refresh = math.min(session.refresh or 0, RealTime() + 0.1)
end

-- Whether a w x h thing could lie at x, y of a grid of the case, by what the case shows there (`object` itself aside).
local function FitsShown(case, gridID, object, x, y)
	local grid = case.gridByID[gridID]

	if (!grid or x < 1 or y < 1 or x + object.w - 1 > grid.w or y + object.h - 1 > grid.h) then
		return false
	end

	for x2 = x, x + object.w - 1 do
		for y2 = y, y + object.h - 1 do
			local other = grid.cells[x2] and grid.cells[x2][y2]

			if (other and other != object) then
				return false
			end
		end
	end

	return true
end

--- What letting go of a carried thing at a place would do, for the case (ix.worldcase Evaluate): "move" to free
-- cells, "combine" onto another item that takes it (the old drag onto), "drop" off the case, "back" where it was, or
-- nil where it cannot go; and a few words for its label.
function PLUGIN:EvaluatePlace(session, object, place)
	-- money carried to the other side asks how much (OnRelease opens the amounts); anywhere else it goes back
	if (object.money) then
		if (self:CanMoveMoney(session) and place.grid and place.grid != object.grid and (place.x or place.pocket)) then
			return "money", L("invPanelHereMoney")
		end

		return nil, L("invPanelHereNot")
	end

	local item, inventory = self:GetObjectItem(object)

	if (!item) then
		return
	end

	if (place.off) then
		local _, drop = self:GetItemActions(item, LocalPlayer())

		if (drop and self:IsOwnInventory(inventory)) then
			return "drop", L("invPanelHereDrop")
		end

		return nil, L("invPanelHereNot")
	end

	if (!place.grid or !place.x) then
		return nil, L("invPanelHereNot")
	end

	if (place.over) then
		local target = !place.over.money and self:GetObjectItem(place.over)

		local refusal = target and self:GetCombineRefusal(item, target)

		if (target and !refusal and #self:GetCombineTargets(item, {target}, LocalPlayer()) > 0) then
			return "combine", L("invPanelHereCombine", target:GetName())
		end

		return nil, refusal and L(refusal):gsub("%.$", ""):utf8lower() or L("invPanelHereNot")
	end

	if (place.grid == object.grid and place.x == object.x and place.y == object.y) then
		return "back"
	end

	if (!FitsShown(session.case, place.grid, object, place.x, place.y)) then
		return nil, L("invPanelHereNoRoom")
	end

	if (place.grid != object.grid) then
		local target = self:GetGridInventory(session, place.grid)

		-- as the server's transfer rules: nothing equipped leaves, no bag goes into a bag (or into itself)
		if (!target or item:GetData("equip") or (item.isBag and (target.vars and target.vars.isBag or
			item:GetData("id") == target:GetID()))) then
			return nil, L("invPanelHereNot")
		end
	end

	return "move", L("invPanelHereMove")
end

--- Letting go of a carried thing (ix.worldcase OnRelease); false when nothing was asked of the server.
function PLUGIN:ReleaseAt(session, object, place, result)
	-- nothing is asked yet: the money goes back and its amounts open beside it
	if (result == "money") then
		self:OpenOptions(session, object, place.pocket and {grid = place.grid, pocket = true} or
			{grid = place.grid, x = place.cx or place.x, y = place.cy or place.y})

		return false
	end

	local item, inventory = self:GetObjectItem(object)

	if (!item or result == "back") then
		return result == "back"
	end

	if (result == "move") then
		return self:RequestMove(item:GetID(), self:GetGridInventory(session, place.grid):GetID(), nil, place.x, place.y)
	elseif (result == "combine") then
		return self:RequestCombine(item:GetID(), place.over.key)
	elseif (result == "drop") then
		local info = item.functions.drop

		if (info) then
			RunFunction(item, inventory:GetID(), "drop", info)
			return true
		end
	end

	return false
end

--- Back from the other side: a carried bag back to the bag, a bag opened inside a storage back to the storage.
-- Returns whether it went anywhere.
function PLUGIN:Back(session)
	if (session.kind == "carried") then
		return self:OpenBag() != nil
	end

	if (session.innerID) then
		session.innerID, session.innerName, session.innerItemID = nil, nil, nil
		session.case:SetGrids(self:GetGrids(session))
		self:Refresh(session, true)

		return true
	end

	return false
end

--- A bag inside a storage, shown in place of the storage's own grid.
function PLUGIN:OpenInner(session, item)
	local index = item:GetData("id")

	if (!index or !ix.item.inventories[index]) then
		return
	end

	session.innerID, session.innerName, session.innerItemID = index, item:GetName(), item:GetID()
	session.case:SetGrids(self:GetGrids(session))
	self:Refresh(session, true)
end

--- Opens a session's case and keeps it. `info` adds to what ix.worldcase.Open gets.
function PLUGIN:OpenSession(session, info)
	if (!self:GetOwnInventory()) then
		return
	end

	if (session.otherID and !self:GetGridInventory(session, "theirs")) then
		return
	end

	info.name = session.kind
	info.grids = self:GetGrids(session)
	info.OnTap = function(_, object)
		self:Tap(session, object)
	end
	info.OnHold = function(_, object)
		return self:OpenOptions(session, object)
	end
	info.CanCarry = function(_, object)
		if (object.money) then
			return self:CanMoveMoney(session)
		end

		return self:GetObjectItem(object) != nil
	end
	info.Evaluate = function(_, object, place)
		return self:EvaluatePlace(session, object, place)
	end
	info.OnRelease = function(_, object, place, result)
		local bAsked = self:ReleaseAt(session, object, place, result)

		session.refresh = math.min(session.refresh or 0, RealTime() + 0.1)

		return bAsked
	end
	info.OnBack = function()
		return self:Back(session)
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

	session.case = ix.worldcase.Open(info)
	self.session = session
	self:Refresh(session, true)

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

	if (!client:GetCharacter() or !self:GetOwnInventory() or !self:CanUseBag(client)) then
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

--- A storage the server opened (a container, a corpse, a searched player), held toward the thing.
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

	if (session and session.case and session.case:IsOpen()) then
		return session
	end
end

function PLUGIN:Think()
	local session = self:GetSession()

	if (session and RealTime() >= (session.refresh or 0)) then
		self:Refresh(session)
	end
end

--- The open case as data, for tools (the harness's `state`): each grid with its inventory, size and things (id,
-- name, amount, top left cell, size, worn or equipped, and whether it is drawn as a plain block), the money in each
-- pocket, what is aimed at and what is carried.
function PLUGIN:DescribeCase()
	local session = self:GetSession()

	if (!session) then
		return
	end

	local case = session.case
	local out = {
		name = session.kind,
		held = case.bHeld or nil,
		anchor = IsValid(case.anchor) and (case.anchor:GetClass() .. "#" .. case.anchor:EntIndex()) or nil,
		grids = {}
	}

	for _, grid in ipairs(case.grids) do
		local inventory = self:GetGridInventory(session, grid.id)
		local entry = {id = grid.id, title = grid.title, inventory = inventory and inventory:GetID(), w = grid.w,
			h = grid.h, items = {}}

		for _, object in ipairs(case:GetObjects()) do
			if (object.grid == grid.id) then
				if (object.money) then
					entry.money = object.money
				else
					local item = self:GetObjectItem(object)

					entry.items[#entry.items + 1] = {
						id = object.key, name = object.label, amount = object.amount, x = object.x, y = object.y,
						w = object.w, h = object.h, block = object.block or nil,
						worn = item and item:GetData("equip") and item.outfitCategory and true or nil,
						equipped = item and item:GetData("equip") and !item.outfitCategory and true or nil
					}
				end
			end
		end

		out.grids[#out.grids + 1] = entry
	end

	local aimed, place = case:GetAimed()

	if (aimed) then
		out.aimed = {id = aimed.key, name = aimed.label, grid = aimed.grid, x = aimed.x, y = aimed.y}
	elseif (place) then
		out.aimed = place.cx and {grid = place.grid, x = place.cx, y = place.cy} or
			(place.off and "off the case" or (place.edge and "the case's edge") or nil)
	end

	local carried, target, result, hint = case:GetCarry()

	if (carried) then
		local to

		if (target and target.over) then
			to = {onto = target.over.label, grid = target.grid}
		elseif (target and target.x) then
			to = {grid = target.grid, x = target.x, y = target.y}
		elseif (target) then
			to = target.off and "off the case" or "the case's edge"
		end

		out.carrying = {id = carried.key, name = carried.label, to = to, result = result or "refused", hint = hint}
	end

	return out
end

-- Tab: the bag, instead of Helix's menu. Tab again (or right click, or Use off the case) puts it away.
function PLUGIN:ToggleBag()
	local client = LocalPlayer()

	if (!IsValid(client) or !client:GetCharacter()) then
		return
	end

	local session = self:GetSession()

	if (session) then
		session.case:Close()
	else
		self:OpenBag()
	end
end

-- The gamemode's own ScoreboardShow (helix/gamemode/core/hooks/cl_hooks.lua), which opens the menu, is replaced
-- rather than a plugin hook returning a value: that would stop the plugins that run after it (wepselect hides its
-- weapon list there).
-- Compared by function, not by a flag: a Lua refresh of the gamemode defines its ScoreboardShow again.
local function ScoreboardShow()
	PLUGIN:ToggleBag()
end

function PLUGIN:WrapScoreboard()
	-- GM while the gamemode loads or reloads (registering it afterwards copies GM over GAMEMODE), GAMEMODE after
	local gamemode = GM or GAMEMODE

	if (!gamemode or gamemode.ScoreboardShow == ScoreboardShow) then
		return
	end

	gamemode.ixInventoryPanelScoreboard = gamemode.ScoreboardShow or true
	gamemode.ScoreboardShow = ScoreboardShow
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

	if (!bSuccess and phrase != "") then
		Say(L(phrase, argument))
	end

	local session = PLUGIN:GetSession()

	if (session) then
		session.refresh = 0
	end
end)

-- Helix's storage receivers (helix/gamemode/core/libs/sh_storage.lua) are replaced: an opened storage shows the
-- case instead of ixStorageView, the server closing it closes the case, and its money follows.
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
		session.case:Close()
	end

	if (IsValid(ix.gui.openedStorage)) then
		ix.gui.openedStorage:Remove()
	end

	-- as Helix does: the client forgets the storage's contents (never the player's own inventory)
	local own = PLUGIN:GetOwnInventory()

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
		PLUGIN:Refresh(session)
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
