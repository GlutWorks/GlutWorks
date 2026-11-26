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

-- The Helix intro is a long animation shown to a first-time player, which a play session
-- always is, and it sits on top of everything until dismissed. Turn it off and remove any
-- instance that was already created.
timer.Create("gw_harness_intro", 0.25, 0, function()
	if (!ix or !ix.option) then return end

	if (ix.option.Get("showIntro", true)) then
		ix.option.Set("showIntro", false)
	end

	for _, panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
		if (panel:GetName() == "ixIntro") then panel:Remove() end
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

				if (text == wanted) then
					exact = exact or child
				elseif (text != "" and string.find(text, wanted, 1, true)) then
					partial = partial or child
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

GWH.Op("look", function(request)
	local client = LocalPlayer()
	local angles

	if (request.ent) then
		local entity = Entity(request.ent)
		if (!IsValid(entity)) then error("no entity " .. tostring(request.ent), 0) end

		angles = (entity:WorldSpaceCenter() - client:EyePos()):Angle()
	elseif (request.pos) then
		angles = (Vector(request.pos[1], request.pos[2], request.pos[3]) - client:EyePos()):Angle()
	else
		angles = Angle(request.pitch or client:EyeAngles().p, request.yaw or client:EyeAngles().y, 0)
	end

	angles:Normalize()
	client:SetEyeAngles(angles)

	return {eyeAngles = angles}
end)
