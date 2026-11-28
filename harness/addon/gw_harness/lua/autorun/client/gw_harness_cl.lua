-- GlutWorks test harness, client side: lets `harness/gw play ...` observe and drive the
-- local player. Sent by the sandboxed server; a live server never mounts this addon.

if (!CLIENT) then return end

include("gw_harness/rpc.lua")

local held = {buttons = 0, forward = 0, side = 0, up = 0, untilTime = 0}
local notices = {}

hook.Add("OnLuaError", "gw_harness", function(err, realm, stack)
	GWH.errors[#GWH.errors + 1] = {error = tostring(err), realm = tostring(realm), stack = stack}
end)

local function Remember(kind, text)
	notices[#notices + 1] = {kind = kind, text = tostring(text), time = math.Round(CurTime(), 1)}
	if (#notices > 30) then table.remove(notices, 1) end
end

hook.Add("InitPostEntity", "gw_harness", function()
	if (ix and ix.util and ix.util.Notify) then
		local notify = ix.util.Notify

		function ix.util.Notify(message, ...)
			Remember("notice", message)
			return notify(message, ...)
		end
	end
end)

-- Helix chat classes print with chat.AddText (private lines such as /Feel and Examine never pass
-- through ChatText or OnPlayerChat), so the text of every chat line is kept from there. The chatbox
-- plugin replaces chat.AddText whenever it loads, including on a Lua refresh, so the wrapper is put
-- back whenever it is gone.
local function ChatWrapper(...)
	local parts = {}

	for _, v in ipairs({...}) do
		if (isstring(v)) then
			parts[#parts + 1] = v
		elseif (isentity(v) and IsValid(v) and v:IsPlayer()) then
			parts[#parts + 1] = v:Name()
		end
	end

	if (#parts > 0) then Remember("chat", table.concat(parts)) end

	return GWH.chatAddText(...)
end

-- Every wrapper this file has made, across Lua refreshes: one of them is never taken as the function
-- to pass lines on to, which would call itself forever.
GWH.chatWrappers = GWH.chatWrappers or setmetatable({}, {__mode = "k"})
GWH.chatWrappers[ChatWrapper] = true

timer.Create("gw_harness_chat", 0.5, 0, function()
	if (chat.AddText != ChatWrapper) then
		if (!GWH.chatWrappers[chat.AddText]) then
			GWH.chatAddText = chat.AddText
		end

		chat.AddText = ChatWrapper
	end
end)

-- The Helix intro is a long animation shown to a first-time player, which a play session
-- always is, and it sits on top of everything until dismissed. Stop it being created, turn
-- the option off, and remove any instance that already exists. The panel overrides Remove
-- to play a closing animation unless forced, and that animation leaves it on screen.
hook.Add("LoadIntro", "gw_harness", function() return true end)

timer.Create("gw_harness_intro", 0.25, 0, function()
	if (!ix or !ix.option) then return end

	if (ix.option.Get("showIntro", true)) then
		ix.option.Set("showIntro", false)
	end

	for _, panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
		if (panel:GetName() == "ixIntro") then panel:Remove(true) end
	end
end)

hook.Add("ChatText", "gw_harness", function(_, _, text) Remember("chat", text) end)
hook.Add("OnPlayerChat", "gw_harness", function(speaker, text)
	Remember("chat", (IsValid(speaker) and speaker:Name() or "console") .. ": " .. text)
end)

hook.Add("CreateMove", "gw_harness", function(cmd)
	if (CurTime() > held.untilTime) then return end

	cmd:SetButtons(bit.bor(cmd:GetButtons(), held.buttons))
	if (held.forward != 0) then cmd:SetForwardMove(held.forward * 10000) end
	if (held.side != 0) then cmd:SetSideMove(held.side * 10000) end
	if (held.up != 0) then cmd:SetUpMove(held.up * 10000) end
end)

local function Inventory(character)
	local out = {}
	local inventory = character:GetInventory()

	if (!inventory) then return out end

	for _, item in pairs(inventory:GetItems()) do
		out[#out + 1] = {id = item.id, item = item.uniqueID, name = item:GetName(), x = item.gridX, y = item.gridY, data = item.data}
	end

	return out
end

-- The open world panel (ix.worldui): what it is beside, its title and rows, and the aimed row.
local function WorldPanel()
	local panel = ix and ix.worldui and ix.worldui.GetOpen()

	if (!panel) then return nil end

	local index = panel:GetAimed()
	local rows = {}

	for i, row in ipairs(panel:GetRows()) do
		rows[i] = {
			label = row.label,
			detail = row.detail,
			enabled = row.enabled != false and !row.heading,
			-- greyed (cannot be done now) but still chosen to learn why
			dim = row.dim or nil,
			heading = row.heading or nil,
			aimed = index == i or nil
		}
	end

	return {
		anchor = IsValid(panel.anchor) and (panel.anchor:GetClass() .. "#" .. panel.anchor:EntIndex()) or nil,
		title = panel.title,
		rows = rows
	}
end

--- Everything a tester needs to know about where the player is and what they hold.
GWH.Op("state", function(request)
	local client = LocalPlayer()

	if (!IsValid(client)) then return {connected = false} end

	local character = client.GetCharacter and client:GetCharacter()
	local trace = client:GetEyeTrace()
	local nearby = {}

	for _, entity in ipairs(ents.FindInSphere(client:GetPos(), request.radius or 600)) do
		local class = entity:GetClass()

		if (entity != client and !entity:IsWeapon() and !string.StartWith(class, "class C") and class != "viewmodel"
		and class != "gmod_hands" and #nearby < 40) then
			local row = {
				ent = entity:EntIndex(),
				class = class,
				distance = math.Round(entity:GetPos():Distance(client:GetPos())),
				pos = entity:GetPos()
			}

			if (class == "ix_item" and entity.GetItemTable and entity:GetItemTable()) then
				row.item = entity:GetItemTable().uniqueID
			end

			nearby[#nearby + 1] = row
		end
	end

	table.SortByMember(nearby, "distance", true)

	local weapon = client:GetActiveWeapon()
	local interaction = ix and ix.plugin and ix.plugin.list.interaction
	local focus = interaction and interaction:GetFocus()

	return {
		connected = true,
		map = game.GetMap(),
		time = math.Round(CurTime(), 1),
		screen = {ScrW(), ScrH()},
		alive = client:Alive(),
		health = client:Health(),
		armor = client:Armor(),
		pos = client:GetPos(),
		eyeAngles = client:EyeAngles(),
		weapon = IsValid(weapon) and weapon:GetClass() or nil,
		lookingAt = IsValid(trace.Entity) and {
			ent = trace.Entity:EntIndex(),
			class = trace.Entity:GetClass(),
			distance = math.Round(trace.HitPos:Distance(client:EyePos()))
		} or nil,
		character = character and {
			id = character:GetID(),
			name = character:GetName(),
			faction = ix.faction.indices[character:GetFaction()] and ix.faction.indices[character:GetFaction()].name,
			money = character:GetMoney(),
			vars = request.vars and character.vars or nil,
			inventory = Inventory(character)
		} or nil,
		-- the usable thing under the aim (outlined), and the world panel of options if one is open
		focus = IsValid(focus) and {ent = focus:EntIndex(), class = focus:GetClass()} or nil,
		worldPanel = WorldPanel(),
		cursorVisible = vgui.CursorVisible(),
		characterMenuOpen = ix and ix.gui and IsValid(ix.gui.characterMenu) and ix.gui.characterMenu:IsVisible() or false,
		menuOpen = ix and ix.gui and IsValid(ix.gui.menu) or false,
		nearby = nearby,
		recent = notices,
		luaErrors = #GWH.errors
	}
end)

--- Flat list of visible Derma panels with screen rectangles, for deciding where to click.
GWH.Op("panels", function(request)
	local out = {}
	local limit = request.limit or 250

	local function Walk(panel, depth)
		if (#out >= limit or depth > 14) then return end

		for _, child in ipairs(panel:GetChildren()) do
			if (child:IsVisible()) then
				local x, y = child:LocalToScreen(0, 0)
				local w, h = child:GetSize()
				local text = child.GetText and child:GetText() or nil

				if (w > 2 and h > 2 and x < ScrW() and y < ScrH() and x + w > 0 and y + h > 0) then
					if ((text and text != "") or child.DoClick or child:GetClassName() == "TextEntry" or depth < 2) then
						out[#out + 1] = {
							depth = depth,
							class = child:GetName() != "Panel" and child:GetName() or child:GetClassName(),
							text = (text and text != "") and string.sub(text, 1, 80) or nil,
							rect = {x, y, w, h},
							center = {math.floor(x + w / 2), math.floor(y + h / 2)},
							clickable = child.DoClick != nil or nil,
							focused = vgui.GetKeyboardFocus() == child or nil
						}
					end

					Walk(child, depth + 1)
				end
			end
		end
	end

	Walk(vgui.GetWorldPanel(), 0)

	return out
end)

-- Engine-level mouse simulation does not update Derma's hover state reliably, so clicks
-- are delivered straight to the panel: find the deepest visible, mouse-enabled panel at
-- the point and run the same handlers a real press and release would.
local function PanelAt(x, y)
	local found

	local function Walk(panel)
		local children = panel:GetChildren()

		table.sort(children, function(a, b) return a:GetZPos() < b:GetZPos() end)

		for _, child in ipairs(children) do
			if (child:IsVisible() and child:IsMouseInputEnabled()) then
				local px, py = child:LocalToScreen(0, 0)
				local w, h = child:GetSize()

				if (x >= px and x < px + w and y >= py and y < py + h) then
					found = child
					Walk(child)
				end
			end
		end
	end

	Walk(vgui.GetWorldPanel())

	return found
end

local function Press(panel, code, reply)
	input.SetCursorPos(panel:LocalToScreen(panel:GetWide() / 2, panel:GetTall() / 2))
	panel.Hovered = true

	if (panel.OnCursorEntered) then panel:OnCursorEntered() end
	if (panel.OnMousePressed) then panel:OnMousePressed(code) end

	timer.Simple(0.08, function()
		if (IsValid(panel)) then
			panel.Hovered = true
			if (panel.OnMouseReleased) then panel:OnMouseReleased(code) end
			panel.Hovered = false
			if (panel.OnCursorExited) then panel:OnCursorExited() end
		end

		timer.Simple(0.15, function()
			reply({
				pressed = IsValid(panel) and (panel:GetName() != "Panel" and panel:GetName() or panel:GetClassName()) or "removed",
				text = IsValid(panel) and panel.GetText and panel:GetText() or nil
			})
		end)
	end)

	return GWH.ASYNC
end

GWH.Op("click", function(request, reply)
	local panel = PanelAt(request.x, request.y)

	if (!IsValid(panel)) then error("no clickable panel at " .. request.x .. "," .. request.y, 0) end

	-- A text entry only takes keyboard focus from an engine-level click, and it keeps the
	-- focus only if nothing tells it the cursor left, so it gets that instead.
	if (panel:GetClassName() == "TextEntry") then
		input.SetCursorPos(request.x, request.y)
		gui.InternalCursorMoved(0, 0)

		timer.Simple(0.1, function()
			gui.InternalMousePressed(MOUSE_LEFT)

			timer.Simple(0.08, function()
				gui.InternalMouseReleased(MOUSE_LEFT)
				if (IsValid(panel)) then panel:RequestFocus() end

				timer.Simple(0.15, function()
					reply({pressed = "TextEntry", focused = vgui.GetKeyboardFocus() == panel})
				end)
			end)
		end)

		return GWH.ASYNC
	end

	return Press(panel, request.button == "right" and MOUSE_RIGHT or MOUSE_LEFT, reply)
end)

--- Clicks the visible panel whose text matches (case-insensitive, exact first, then contains).
GWH.Op("press", function(request, reply)
	local wanted = string.lower(request.text)
	local exact, partial

	local function Walk(panel)
		for _, child in ipairs(panel:GetChildren()) do
			if (child:IsVisible()) then
				local text = child.GetText and string.lower(child:GetText() or "") or ""
				local x, y = child:LocalToScreen(0, 0)
				local w, h = child:GetSize()

				-- Helix keeps the pages of a multi-step menu alive beside the screen, each with
				-- its own identically labelled buttons, so only a panel on screen counts.
				if (x < ScrW() and y < ScrH() and x + w > 0 and y + h > 0) then
					if (text == wanted) then
						exact = exact or child
					elseif (text != "" and string.find(text, wanted, 1, true)) then
						partial = partial or child
					end
				end

				Walk(child)
			end
		end
	end

	Walk(vgui.GetWorldPanel())

	local panel = exact or partial

	if (!IsValid(panel)) then error("no visible panel with text '" .. request.text .. "'", 0) end

	return Press(panel, request.button == "right" and MOUSE_RIGHT or MOUSE_LEFT, reply)
end)

GWH.Op("key", function(request, reply)
	local code = _G[request.key]

	if (!isnumber(code)) then error("unknown key " .. tostring(request.key) .. " (use KEY_* enums)", 0) end

	gui.InternalKeyCodePressed(code)

	timer.Simple(request.seconds or 0.1, function()
		gui.InternalKeyCodeReleased(code)
		reply(true)
	end)

	return GWH.ASYNC
end)

GWH.Op("con", function(request)
	LocalPlayer():ConCommand(request.command)

	return true
end)

--- Holds movement and buttons for `seconds`, replying when done.
GWH.Op("move", function(request, reply)
	local buttons = 0

	for _, name in ipairs(request.buttons or {}) do
		if (!isnumber(_G[name])) then error("unknown button " .. tostring(name) .. " (use IN_* enums)", 0) end
		buttons = bit.bor(buttons, _G[name])
	end

	local seconds = math.Clamp(request.seconds or 1, 0.05, 30)

	held = {
		buttons = buttons,
		forward = request.forward or 0,
		side = request.side or 0,
		up = request.up or 0,
		untilTime = CurTime() + seconds
	}

	timer.Simple(seconds + 0.1, function()
		reply({pos = LocalPlayer():GetPos()})
	end)

	return GWH.ASYNC
end)

-- Turns the view as the mouse would: the eyes, and in Helix's third person the camera, which the
-- mouse turns on its own while the player stands still.
local function SetView(client, angles)
	client:SetEyeAngles(angles)

	if (client.CanOverrideView and client:CanOverrideView() and client.camAng) then
		client.camAng = Angle(angles.p, angles.y, 0)
	end
end

GWH.Op("look", function(request)
	local client = LocalPlayer()
	-- from the camera in third person, so the thing ends up where the player is looking
	local origin = (ix and ix.worldui) and ix.worldui.GetView(client) or client:EyePos()
	local angles

	if (request.ent) then
		local entity = Entity(request.ent)
		if (!IsValid(entity)) then error("no entity " .. tostring(request.ent), 0) end

		angles = (entity:WorldSpaceCenter() - origin):Angle()
	elseif (request.pos) then
		angles = (Vector(request.pos[1], request.pos[2], request.pos[3]) - origin):Angle()
	else
		angles = Angle(request.pitch or client:EyeAngles().p, request.yaw or client:EyeAngles().y, 0)
	end

	angles:Normalize()
	SetView(client, angles)

	return {eyeAngles = angles}
end)

--- Chooses a row of the open world panel the way a player does: turns the view onto the row,
-- waits for the panel to see it aimed at, then confirms it through panel:Select(), the code a
-- left click or releasing a held Use runs. Matches the label case-insensitively, exact first.
GWH.Op("choose", function(request, reply)
	local panel = ix and ix.worldui and ix.worldui.GetOpen()

	if (!panel) then error("no world panel is open (hold e on something, or tap e on a station)", 0) end

	local wanted = string.lower(request.text)
	local exact, partial

	for i, row in ipairs(panel:GetRows()) do
		local label = string.lower(tostring(row.label or ""))

		if (!row.heading) then
			if (label == wanted) then
				exact = exact or i
			elseif (string.find(label, wanted, 1, true)) then
				partial = partial or i
			end
		end
	end

	local index = exact or partial

	if (!index) then error("the world panel has no row '" .. request.text .. "'", 0) end

	local client = LocalPlayer()

	-- in third person turning the camera also moves it, so the aim is set again until it settles
	local function Turn(attempt)
		local angles = (panel:GetRowPos(index) - ix.worldui.GetView(client)):Angle()

		angles:Normalize()
		SetView(client, angles)

		timer.Simple(0.15, function()
			if (!panel:IsOpen()) then
				return reply({chosen = false, error = "the panel closed while turning to the row"})
			end

			local aimed = panel:GetAimed()

			if (aimed != index) then
				if (attempt < 4) then return Turn(attempt + 1) end

				return reply({chosen = false, error = "row " .. index .. " is not aimed at (aimed: " .. tostring(aimed) .. ")"})
			end

			reply({chosen = panel:Select(), label = panel:GetRows()[index].label})
		end)
	end

	Turn(1)

	return GWH.ASYNC
end)
