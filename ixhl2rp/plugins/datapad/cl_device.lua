local pad = ix.datapad
local function raised(value)
	net.Start("ixPadRaised")
		net.WriteBool(value)
	net.SendToServer()
end

local function releaseStorage(id)
	net.Start("ixPadStorageClose")
		net.WriteUInt(id, 32)
	net.SendToServer()
end

function pad.Close(expired)
	local s = pad.screen
	if (!s) then return end
	pad.screen = nil
	if (s.storage and !expired) then releaseStorage(s.storage.id) end
	if (!s.witness) then raised(false) end
	if (IsValid(s.scan)) then s.scan:Remove() end
	if (IsValid(s.input)) then s.input:Remove() end
	surface.PlaySound("buttons/lightswitch2.wav")
end

function pad.Tab(s, tab)
	s.tab, s.mode, s.detailScroll = tab, nil, 0
	s.scroll = {}
end

local function allowed()
	return pad.Available(LocalPlayer()) and hook.Run("CanPlayerViewInventory") != false
end

function pad.Open()
	local client = LocalPlayer()
	local witness = pad.frisk and pad.frisk.witness
	if ((!allowed() and !witness) or !client:GetCharacter() or !client:GetCharacter():GetInventory()) then return end
	if (pad.screen) then return pad.screen end
	if (ix.worldui) then ix.worldui.Close() end
	local s = {tab = pad.frisk and !witness and "Frisk" or "Carry", scroll = {}, query = "", char = client:GetCharacter(),
		witness = witness, part = "chest", detailScroll = 0, started = RealTime(), hits = {}}
	pad.screen = s
	if (!witness) then raised(true) end
	surface.PlaySound("buttons/button14.wav")
	local panel = vgui.Create("DPanel")
	s.input = panel
	panel:SetSize(ScrW(), ScrH())
	panel:SetPaintBackground(false)
	panel:MakePopup()
	panel:SetCursor("arrow")
	panel.OnMousePressed = function(_, code)
		if (code == MOUSE_RIGHT) then
			if (s.mode) then s.mode = nil else pad.Close() end
		elseif (code == MOUSE_LEFT) then
			if (IsValid(s.entry)) then s.entry:OnEnter() end
			s.pressed = pad.HitAt(s)
			panel:MouseCapture(true)
		end
	end
	panel.OnMouseReleased = function(_, code)
		if (code != MOUSE_LEFT) then return end
		panel:MouseCapture(false)
		local hit, pressed = pad.HitAt(s), s.pressed
		s.pressed = nil
		if (!pressed or !hit) then return end
		if (pressed.item and hit.drop and !s.witness) then
			pad.SendMove(pressed.item.id, hit.drop)
		elseif (hit.id == pressed.id and hit.click) then
			hit.click()
		end
	end
	panel.OnMouseWheeled = function(_, delta)
		local col = s.hoverColumn or "own"
		s.scroll[col] = math.max(0, (s.scroll[col] or 0) - delta * 2)
		return true
	end
	panel.OnKeyCodePressed = function(_, key)
		if (key == KEY_ESCAPE or key == KEY_TAB) then pad.Close()
		elseif (key == KEY_F) then pad.Search(s)
		elseif (key == KEY_M and !s.witness and s.tab == "Carry") then s.mode = s.mode != "move" and "move" or nil
		elseif (key == KEY_T and s.storage and !s.witness) then pad.Transfer(s, input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT))
		elseif (key == KEY_B and !s.witness and !pad.frisk) then pad.Tab(s, s.tab == "Body" and "Carry" or "Body")
		end
	end
	return s
end

function pad.Search(s)
	if (s.tab != "Carry" or IsValid(s.entry)) then return end
	local entry = s.input:Add("DTextEntry")
	s.entry = entry
	entry:SetPos(0, 0)
	entry:SetSize(1, 1)
	entry:SetAlpha(0)
	entry:MakePopup()
	entry:SetText(s.query)
	entry:RequestFocus()
	entry:SelectAllText(true)
	entry.OnChange = function()
		s.query, s.scroll, s.refresh = entry:GetValue():sub(1, 80), {}, nil
	end
	entry.OnEnter = function() entry:Remove() s.input:RequestFocus() end
	entry.OnKeyCodeTyped = function(_, key)
		if (key == KEY_ESCAPE or key == KEY_TAB) then entry:OnEnter() return true end
	end
end

function pad.SendMove(id, key)
	net.Start("ixPadMove")
		net.WriteUInt(id, 32)
		net.WriteString(key)
	net.SendToServer()
end

function pad.Transfer(s, all)
	local groups = s.external and s.away or s.own
	local _, item = pad.Locate(groups or {}, s.selected)
	if (!item or !s.storage) then return end
	local key = s.external and "auto" or "storage"
	if (!all) then pad.SendMove(item.id, key) return end
	local queue = {}
	for _, place in ipairs(groups) do
		for _, other in ipairs(place.items) do
			if (item.uniqueID == other.uniqueID) then queue[#queue + 1] = other.id end
		end
	end
	s.batch = queue
	local storageID = s.storage.id
	for n, id in ipairs(queue) do
		timer.Simple((n - 1) * 0.12, function()
			if (pad.screen == s and s.batch == queue and s.storage and s.storage.id == storageID) then pad.SendMove(id, key) end
		end)
	end
end

function pad.Menu()
	pad.Close()
	vgui.Create("ixMenu")
end

function PLUGIN:ScoreboardShow()
	if (pad.screen) then pad.Close() return true end
	if ((!IsValid(ix.gui.characterMenu) or !ix.gui.characterMenu:IsVisible()) and pad.Open()) then return true end
end

concommand.Add("ix_datapad", function()
	if (pad.screen) then pad.Close() elseif (!IsValid(ix.gui.menu)) then pad.Open() end
end)

function PLUGIN:InitializedPlugins()
	hook.Add("CreateMenuButtons", "ixInventory", function(tabs)
		if (!allowed() and !(pad.frisk and pad.frisk.witness)) then return end
		tabs.inv = {Create = function(_, panel)
			local button = panel:Add("ixMenuButton")
			button:Dock(TOP)
			button:SetText("Raise datapad")
			button:SizeToContents()
			button.DoClick = function()
				ix.gui.menu:Remove()
				pad.Open()
			end
		end}
	end)

	net.Receive("ixStorageOpen", function()
		local id, ent, name, data = net.ReadUInt(32), net.ReadEntity(), net.ReadString(), net.ReadTable()
		if (!IsValid(ent) or !ix.item.inventories[id] or !allowed() or IsValid(ix.gui.menu)) then
			releaseStorage(id)
			return
		end
		local s = pad.Open()
		if (!s) then releaseStorage(id) return end
		s.storage = {
			id = id,
			ent = ent,
			name = name,
			money = data.money,
			friskMode = data.friskMode,
			foundIDs = data.foundIDs
		}
		s.selected, s.external, s.refresh = nil, false, nil
		pad.Tab(s, "Carry")
	end)
	net.Receive("ixStorageExpired", function()
		local id = net.ReadUInt(32)
		local s = pad.screen
		if (s and s.storage and s.storage.id == id) then pad.Close(true) end
		local char = LocalPlayer():GetCharacter()
		if (id != 0 and (!char or !char:GetInventory() or id != char:GetInventory():GetID())) then ix.item.inventories[id] = nil end
	end)
	net.Receive("ixStorageMoneyUpdate", function()
		local id, amount = net.ReadUInt(32), net.ReadUInt(32)
		local s = pad.screen
		if (s and s.storage and s.storage.id == id) then s.storage.money = amount end
	end)
end

function PLUGIN:PopulateInteractionOptions(entity, client, options)
	if (!IsValid(entity) or !entity:IsPlayer() or entity == client or !entity:Alive() or !entity:IsRestricted()) then
		return
	end
	if (!pad.Available(client)) then return end
	options["Search (Quick)"] = function()
		net.Start("ixPadFriskStart")
			net.WriteEntity(entity)
			net.WriteString("hasty")
		net.SendToServer()
		return false
	end
	options["Search (Thorough)"] = function()
		net.Start("ixPadFriskStart")
			net.WriteEntity(entity)
			net.WriteString("thorough")
		net.SendToServer()
		return false
	end
end

function pad.Money(s, take)
	local storage = s.storage
	Derma_StringRequest(take and "Take money" or "Store money", "Amount", "", function(text)
		local amount = math.floor(tonumber(text) or 0)
		if (pad.screen != s or s.storage != storage or amount <= 0) then return end
		net.Start(take and "ixStorageMoneyTake" or "ixStorageMoneyGive")
			net.WriteUInt(storage.id, 32)
			net.WriteUInt(math.min(amount, 4294967295), 32)
		net.SendToServer()
	end)
end

net.Receive("ixPadReceipt", function()
	pad.receipt = {name = net.ReadString(), place = net.ReadString(), char = LocalPlayer():GetCharacter()}
end)

net.Receive("ixPadFrisk", function()
	local target, witness, region = net.ReadEntity(), net.ReadBool(), net.ReadString()
	local duration, found, body = net.ReadFloat(), net.ReadTable(), net.ReadTable()
	local mode, label, bHidden, bStart = net.ReadString(), net.ReadString(), net.ReadBool(), net.ReadBool()
	if (region == "") then
		pad.frisk = nil
		if (pad.screen and (pad.screen.witness or pad.screen.tab == "Frisk")) then pad.Close(true) end
		return
	end
	local f = pad.frisk
	if (!f or f.target != target or bStart) then
		f = {target = target, witness = witness, mode = mode, found = {}, foundIDs = {}, done = {}}
		pad.frisk = f
	end
	if (f.region) then f.done[f.region] = true end
	f.region, f.body, f.start, f.duration = region, body, CurTime(), duration
	f.mode = mode != "" and mode or f.mode or "thorough"
	f.label = label != "" and label or region
	f.hidden = bHidden
	table.Add(f.found, found)
	for _, row in ipairs(found) do f.foundIDs[row.id] = true end
	if (!witness) then
		local s = pad.Open()
		if (s and region != "complete") then s.tab = "Frisk" end
	end
end)

local function filterFoundGroups(groups, foundIDs, wetness)
	local filtered = {}
	for _, place in ipairs(groups) do
		if ((place.concealment or 0) >= pad.HIDDEN_THRESHOLD) then
			continue
		end
		local visible = {}
		local used, kg = 0, 0
		for _, item in ipairs(place.items) do
			if (foundIDs[item.id]) then
				visible[#visible + 1] = item
				used = used + pad.Size(item)
				kg = kg + pad.Weight(item, wetness)
			end
		end
		local copy = {}
		for k, v in pairs(place) do
			copy[k] = v
		end
		copy.items, copy.used, copy.kg = visible, used, kg
		filtered[#filtered + 1] = copy
	end
	return filtered
end

function PLUGIN:Think()
	local s = pad.screen
	if (!s) then return end
	local client = LocalPlayer()
	if (client:GetCharacter() != s.char or !client:Alive() or (!s.witness and !allowed()) or
		(IsValid(ix.gui.characterMenu) and ix.gui.characterMenu:IsVisible()) or gui.IsGameUIVisible()) then
		pad.Close()
		return
	end
	if ((s.refresh or 0) > RealTime()) then return end
	s.refresh = RealTime() + 0.18
	s.body = pad.ReadBody(client)
	s.own = pad.Layout(s.char:GetInventory(), s.body and s.body.wetness)
	local inv = s.storage and ix.item.inventories[s.storage.id]
	local awayWet = s.storage and s.storage.ent:IsPlayer() and pad.frisk and pad.frisk.body and pad.frisk.body.wetness or nil
	s.away = inv and (s.storage.ent:IsPlayer() and pad.Layout(inv, awayWet) or pad.StorageGroups(inv, s.storage.name)) or {}
	if (s.storage and s.storage.foundIDs) then
		s.away = filterFoundGroups(s.away, s.storage.foundIDs, awayWet)
	end
	local function matches(place, item)
		return s.query == "" or (item:GetName() .. " " .. place.name):lower():find(s.query:lower(), 1, true)
	end
	local function selectFrom(groups, external)
		for _, place in ipairs(groups) do
			for _, item in ipairs(place.items) do
				if (matches(place, item)) then
					s.selected, s.external = item.id, external
					return true
				end
			end
		end
	end
	local groups = s.external and s.away or s.own
	local place, item = pad.Locate(groups, s.selected)
	if (!item or !matches(place, item)) then
		s.selected, s.mode = nil, nil
		if (!selectFrom(groups, s.external)) then selectFrom(s.external and s.own or s.away, !s.external) end
	end
end
