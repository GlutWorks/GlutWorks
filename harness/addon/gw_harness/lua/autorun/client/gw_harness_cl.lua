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

GWH.Op("click", function(request, reply)
	local code = request.button == "right" and MOUSE_RIGHT or MOUSE_LEFT

	input.SetCursorPos(request.x, request.y)
	gui.InternalCursorMoved(0, 0)

	timer.Simple(0.1, function()
		gui.InternalMousePressed(code)

		timer.Simple(0.08, function()
			gui.InternalMouseReleased(code)

			timer.Simple(0.1, function()
				local hovered = vgui.GetHoveredPanel()
				reply({hovered = IsValid(hovered) and hovered:GetName() or nil})
			end)
		end)
	end)

	return GWH.ASYNC
end)

--- Types into the focused text entry (click it first). `enter` submits it.
GWH.Op("type", function(request)
	local panel = vgui.GetKeyboardFocus()

	if (!IsValid(panel) or !panel.SetText) then error("no text entry has keyboard focus", 0) end

	panel:SetText((request.replace and "" or panel:GetText()) .. request.text)
	if (panel.SetCaretPos) then panel:SetCaretPos(#panel:GetText()) end
	if (panel.OnTextChanged) then panel:OnTextChanged() end
	if (panel.OnValueChange) then panel:OnValueChange(panel:GetText()) end
	if (request.enter and panel.OnEnter) then panel:OnEnter(panel:GetText()) end

	return {text = panel:GetText()}
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
