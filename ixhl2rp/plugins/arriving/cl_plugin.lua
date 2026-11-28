local PLUGIN = PLUGIN

local layout = PLUGIN.layout

-- ------------------------------------------------------------------ joining

-- No intro.
function PLUGIN:LoadIntro()
	return true
end

-- Helix opens its character menu whenever a player has no character (joining, a kicked or deleted
-- character); instead the client asks the server to arrive, and the server decides who they are.
do
	local PANEL = {}

	function PANEL:Init()
		self:SetVisible(false)

		timer.Simple(0, function()
			if (IsValid(self)) then
				self:Remove()
			end
		end)

		local client = LocalPlayer()

		if (!IsValid(client) or !client:GetCharacter()) then
			PLUGIN:AskToArrive()
		end
	end

	vgui.Register("ixCharMenu", PANEL, "EditablePanel")
end

function PLUGIN:AskToArrive()
	if ((self.nextAsk or 0) > RealTime()) then
		return
	end

	self.nextAsk = RealTime() + 2.5

	net.Start("ixArrivingReady")
	net.SendToServer()
end

-- An admin kicking someone off their character: they come back as whoever the server chooses.
net.Receive("ixCharacterKick", function()
	local bCurrent = net.ReadBool()

	if (IsValid(ix.gui.menu)) then
		ix.gui.menu:Remove()
	end

	if (bCurrent) then
		timer.Simple(0.5, function()
			PLUGIN:AskToArrive()
		end)
	end
end)

-- The main menu has no "characters" button: you change who you are by leaving on a train.
function PLUGIN:OnArrivingMenuCreated(menu)
	if (!IsValid(menu) or !IsValid(menu.buttons)) then
		return
	end

	local label = L("characters"):lower()

	for _, child in ipairs(menu.buttons:GetChildren()) do
		local text = isfunction(child.GetText) and child:GetText():lower() or ""

		if (text == "characters" or text == label) then
			child:Remove()
		end
	end
end

function PLUGIN:InitializedPlugins()
	local menu = vgui.GetControlTable("ixMenu")

	if (menu and !menu.ixArrivingWrapped) then
		local init = menu.Init

		menu.Init = function(panel, ...)
			init(panel, ...)
			PLUGIN:OnArrivingMenuCreated(panel)
		end

		menu.ixArrivingWrapped = true
	end
end

-- Waking: the black of loading lifts slowly once the character is in.
function PLUGIN:CharacterLoaded(character)
	if (IsValid(ix.gui.loading)) then
		ix.gui.loading:Remove()
	end

	if (character and self:IsAboard(LocalPlayer())) then
		LocalPlayer():ScreenFade(SCREENFADE.IN, color_black, 3.5, 0.6)
	end
end

-- Someone with no name yet goes by how they look.
function PLUGIN:GetCharacterName(client, chatType)
	local character = IsValid(client) and client:GetCharacter()

	if (character and string.Trim(character:GetName() or "") == "") then
		local description = character:GetDescription() or ""

		description = description != "" and description or "Someone"

		return chatType and ("[" .. description .. "]") or description
	end
end

-- ------------------------------------------------------------------ the set's light

-- Where the train is, as the server has it.
function PLUGIN:GetTrainPlace()
	local place = GetNetVar("arrivingTrainPlace")

	return istable(place) and isvector(place.origin) and place or nil
end

-- Passing lights outside the windows while the train moves.
PLUGIN.passers = PLUGIN.passers or {}

local LAMP_COLOR = Vector(1, 0.72, 0.42)
local PASSER_COLORS = {Vector(1, 0.55, 0.2), Vector(0.75, 0.85, 1), Vector(1, 0.62, 0.3)}
local PLATFORM_COLOR = Vector(0.8, 0.9, 1)

-- The lights of the set this frame, in the world: the lamps (flickering a little with the ride), the
-- passing lights, and the platform's light by the open side door.
function PLUGIN:GetSetLights()
	if (self.lightsFrame == FrameNumber()) then
		return self.lights
	end

	local place = self:GetTrainPlace()
	local lights = {}

	if (place) then
		local now = CurTime()
		local state = GetNetVar("arrivingTrain", "riding")
		local flicker = state == "standing" and 1 or (0.92 + 0.08 * math.sin(now * 23) * math.sin(now * 7.3))

		for i, lamp in ipairs(layout.Lamps()) do
			local pos = self:ToWorld(place, lamp.pos)

			lights[#lights + 1] = {
				type = MATERIAL_LIGHT_POINT, pos = pos, color = LAMP_COLOR * (lamp.corridor and 1.2 or 1.6) * flicker,
				fiftyPercentDistance = 70, zeroPercentDistance = 220
			}
		end

		for _, passer in ipairs(self.passers) do
			lights[#lights + 1] = {
				type = MATERIAL_LIGHT_POINT, pos = self:ToWorld(place, passer.pos), color = passer.color * 2.4,
				fiftyPercentDistance = passer.distance * 0.7, zeroPercentDistance = passer.distance * 2
			}
		end

		if (state == "standing") then
			local stepMins, stepMaxs = layout.StepBox()
			local outside = (stepMins + stepMaxs) / 2

			outside.y = -layout.platform + 14
			outside.z = layout.high - 10

			lights[#lights + 1] = {
				type = MATERIAL_LIGHT_POINT, pos = self:ToWorld(place, outside), color = PLATFORM_COLOR * 1.1,
				fiftyPercentDistance = 110, zeroPercentDistance = 360
			}
		end
	end

	self.lights, self.lightsFrame = lights, FrameNumber()

	return lights
end

-- The set lights itself: the map's light (high in its open sky) never reaches in. Up to four of the set's
-- lights nearest what's drawn (a point, or a box from `mins` to `maxs`), and a dim warm ambient.
function PLUGIN:BeginSetLighting(mins, maxs)
	local lights = self:GetSetLights()
	local nearest = {}

	maxs = maxs or mins

	for _, light in ipairs(lights) do
		local pos = light.pos
		local closest = Vector(math.Clamp(pos.x, mins.x, maxs.x), math.Clamp(pos.y, mins.y, maxs.y), math.Clamp(pos.z, mins.z, maxs.z))
		local distance = pos:DistToSqr(closest)

		if (distance < light.zeroPercentDistance * light.zeroPercentDistance * 2.5) then
			nearest[#nearest + 1] = {light = light, distance = distance}
		end
	end

	table.sort(nearest, function(a, b)
		return a.distance < b.distance
	end)

	local chosen = {}

	for k = 1, math.min(4, #nearest) do
		chosen[k] = nearest[k].light
	end

	render.SuppressEngineLighting(true)
	render.SetModelLighting(BOX_FRONT, 0.05, 0.045, 0.04)
	render.SetModelLighting(BOX_BACK, 0.05, 0.045, 0.04)
	render.SetModelLighting(BOX_RIGHT, 0.05, 0.045, 0.04)
	render.SetModelLighting(BOX_LEFT, 0.05, 0.045, 0.04)
	render.SetModelLighting(BOX_TOP, 0.07, 0.062, 0.055)
	render.SetModelLighting(BOX_BOTTOM, 0.03, 0.027, 0.024)
	render.SetLocalModelLights(chosen)
end

function PLUGIN:EndSetLighting()
	render.SetLocalModelLights()
	render.SuppressEngineLighting(false)
end

-- People on the train are lit by it too.
function PLUGIN:PrePlayerDraw(client)
	-- at a mirror, the whole body faces the glass, not just the head
	local mirror = self:GetMirror(client)

	if (mirror) then
		local toward = mirror:GetPos() - client:GetPos()

		client:SetRenderAngles(Angle(0, toward:Angle().y, 0))
		client:SetPoseParameter("aim_yaw", 0)
		client:SetPoseParameter("head_yaw", 0)
		client:SetPoseParameter("move_yaw", 0)
		client:InvalidateBoneCache()
	end

	if (self:IsAboard(client) and self:GetTrainPlace()) then
		self:BeginSetLighting(client:WorldSpaceCenter())
		client.ixArrivingLit = true
	end
end

function PLUGIN:PostPlayerDraw(client)
	if (client.ixArrivingLit) then
		client.ixArrivingLit = nil
		self:EndSetLighting()
	end
end

function PLUGIN:PreDrawViewModel(viewModel, client)
	if (self:IsAboard(LocalPlayer()) and self:GetTrainPlace()) then
		self:BeginSetLighting(EyePos())
		self.viewModelLit = true
	end
end

function PLUGIN:PostDrawViewModel()
	if (self.viewModelLit) then
		self.viewModelLit = nil
		self:EndSetLighting()
	end
end

function PLUGIN:PreDrawPlayerHands()
	if (self:IsAboard(LocalPlayer()) and self:GetTrainPlace()) then
		self:BeginSetLighting(EyePos())
		self.handsLit = true
	end
end

function PLUGIN:PostDrawPlayerHands()
	if (self.handsLit) then
		self.handsLit = nil
		self:EndSetLighting()
	end
end

-- ------------------------------------------------------------------ the ride

local glow = Material("sprites/light_glow02_add")

-- How fast the world goes by outside (units a second), as the train rides, brakes and stands.
function PLUGIN:GetRideSpeed()
	local state = GetNetVar("arrivingTrain", "riding")

	if (state == "riding") then
		return 1300
	elseif (state == "braking") then
		local since = CurTime() - GetNetVar("arrivingTrainSince", CurTime())

		return 1300 * math.max(0, 1 - since / self.brakeTime) ^ 1.6
	end

	return 0
end

-- Sounds of the ride, for whoever is aboard.
function PLUGIN:UpdateRideSounds(bAboard, speed, state)
	local client = LocalPlayer()

	self.sounds = self.sounds or {}

	local function Loop(key, path, volume, pitch)
		local sound = self.sounds[key]

		if (volume <= 0.01) then
			if (sound and sound:IsPlaying()) then
				sound:Stop()
			end

			return
		end

		if (!sound) then
			sound = CreateSound(client, path)
			self.sounds[key] = sound
		end

		if (!sound:IsPlaying()) then
			sound:PlayEx(volume, pitch)
		else
			sound:ChangeVolume(volume, 0.2)
			sound:ChangePitch(pitch, 0.2)
		end
	end

	local moving = bAboard and math.Clamp(speed / 1300, 0, 1) or 0

	Loop("wheels", "ambient/machines/train_wheels_loop1.wav", moving * 0.55, 70 + moving * 30)
	Loop("rumble", "ambient/machines/train_rumble.wav", moving * 0.45, 80 + moving * 20)
	Loop("idle", "ambient/machines/train_idle.wav", (bAboard and state == "standing") and 0.35 or 0, 100)

	if (bAboard and state != self.lastRideState) then
		local place = self:GetTrainPlace()

		if (state == "braking") then
			client:EmitSound("ambient/machines/station_train_squeel.wav", 70, 100, 0.6)
		elseif (state == "standing" and self.lastRideState == "braking" and place) then
			local stepMins, stepMaxs = layout.StepBox()

			sound.Play("npc/overwatch/cityvoice/f_trainstation_assemble_spkr.wav",
				self:ToWorld(place, (stepMins + stepMaxs) / 2 - Vector(0, 40, 0)), 75, 100, 0.7)
		end
	end

	self.lastRideState = bAboard and state or nil
end

function PLUGIN:Think()
	local client = LocalPlayer()

	if (!IsValid(client)) then
		return
	end

	local bAboard = self:IsAboard(client) and self:GetTrainPlace() != nil
	local state = GetNetVar("arrivingTrain", "riding")
	local speed = bAboard and self:GetRideSpeed() or 0
	local delta = FrameTime()

	-- the lights going by, on either side and near or far (the far ones seem slower, as they would), each
	-- gone once well past the carriage's back end
	for k = #self.passers, 1, -1 do
		local passer = self.passers[k]

		passer.pos.x = passer.pos.x - speed * delta

		if (passer.pos.x < -layout.backdrop or speed <= 0) then
			table.remove(self.passers, k)
		end
	end

	if (bAboard and speed > 200 and (self.nextPasser or 0) < CurTime()) then
		local side = math.random(2) == 1 and 1 or -1
		local distance = math.Rand(110, layout.backdrop - 30)
		local v = side == 1 and (layout.cabinTo + distance) or -distance

		self.passers[#self.passers + 1] = {
			pos = Vector(layout.Long() + layout.backdrop, v, math.Rand(40, 150)),
			distance = distance,
			color = PASSER_COLORS[math.random(#PASSER_COLORS)]
		}
		self.nextPasser = CurTime() + math.Rand(0.5, 1.8) * (1300 / math.max(speed, 300))
	end

	self:UpdateRideSounds(bAboard, speed, state)
end

function PLUGIN:PostDrawTranslucentRenderables(bDepth, bSkybox)
	if (bSkybox or !self:IsAboard(LocalPlayer())) then
		return
	end

	local place = self:GetTrainPlace()

	if (!place) then
		return
	end

	render.SetMaterial(glow)

	for _, passer in ipairs(self.passers) do
		local color = passer.color

		local size = 60 + passer.distance * 0.35

		render.DrawSprite(self:ToWorld(place, passer.pos), size, size, Color(color.x * 255, color.y * 255, color.z * 255))
	end
end

-- ------------------------------------------------------------------ the view: the mirror, and the sway

PLUGIN.mirrorBlend = PLUGIN.mirrorBlend or 0
-- How high over someone's feet the mirror looks from: between their chest and their eyes, so the glass
-- frames them from the hips to over their head.
PLUGIN.lookedFrom = 58

-- The view from a mirror's glass, looking back at a player, level.
function PLUGIN:MirrorView(mirror, client)
	local scale = self:GetScale(client:GetCharacter())
	local facing = mirror:GetForward()
	local origin = mirror:GetPos() + facing * 3

	origin.z = client:GetPos().z + self.lookedFrom * scale

	local toward = client:GetPos() - origin

	toward.z = 0

	return origin, Angle(0, toward:Angle().y, 0)
end

function PLUGIN:CalcView(client, origin, angles, fov)
	local mirror = self:GetMirror(client)
	local target = mirror and 1 or 0

	self.mirrorBlend = math.Approach(self.mirrorBlend, target, FrameTime() / 0.55)

	if (mirror) then
		self.lastMirror = mirror
	end

	local bAboard = self:IsAboard(client) and self:GetTrainPlace() != nil

	if (self.mirrorBlend <= 0 and !bAboard) then
		return
	end

	local view = GAMEMODE:CalcView(client, origin, angles, fov) or {origin = origin, angles = angles, fov = fov}

	view.origin = view.origin or origin
	view.angles = view.angles or angles

	if (bAboard) then
		-- nothing past the set: the map is far below
		view.zfar = 1800

		local speed = self:GetRideSpeed() / 1300
		local now = CurTime()

		if (speed > 0) then
			view.angles = Angle(view.angles)
			view.angles.r = view.angles.r + (math.sin(now * 1.6) * 0.45 + math.sin(now * 0.47) * 0.3) * speed
			view.angles.p = view.angles.p + math.sin(now * 2.3) * 0.15 * speed
			view.origin = view.origin + Vector(0, 0, math.sin(now * 11) * 0.2 * speed)
		end

		if (GetNetVar("arrivingTrain") == "braking") then
			local since = now - GetNetVar("arrivingTrainSince", now)

			view.angles.p = view.angles.p + math.sin(math.min(since / self.brakeTime, 1) * math.pi) * 0.8
		end
	end

	local blend = math.ease.InOutSine(self.mirrorBlend)
	local shown = mirror or self.lastMirror

	if (blend > 0 and IsValid(shown)) then
		local mirrorOrigin, mirrorAngles = self:MirrorView(shown, client)

		view.origin = LerpVector(blend, view.origin, mirrorOrigin)
		view.angles = LerpAngle(blend, view.angles, mirrorAngles)
		view.fov = Lerp(blend, view.fov or fov, 62)
		view.drawviewer = true
	end

	return view
end

function PLUGIN:ShouldDrawLocalPlayer(client)
	if (self.mirrorBlend > 0.05) then
		return true
	end
end

function PLUGIN:CalcViewModelView(weapon, viewModel)
	if (self.mirrorBlend > 0) then
		return Vector(0, 0, -10000), angle_zero
	end
end

-- At the mirror, the movement keys choose: left and right a body, forward and back height, reload age,
-- use keeps it.
PLUGIN.mirrorBinds = {
	["+moveleft"] = 1, ["+moveright"] = 2, ["+forward"] = 3, ["+back"] = 4, ["+reload"] = 5, ["+use"] = 6
}

function PLUGIN:PlayerBindPress(client, bind, bPressed)
	if (!self:GetMirror(client)) then
		return
	end

	bind = bind:lower()

	local action

	for name, index in pairs(self.mirrorBinds) do
		if (bind:find(name, 1, true)) then
			action = index
			break
		end
	end

	if (action and bPressed) then
		net.Start("ixArrivingMirror")
			net.WriteUInt(action, 3)
		net.SendToServer()

		surface.PlaySound(action == 6 and "buttons/lightswitch2.wav" or "physics/cardboard/cardboard_box_impact_soft1.wav")

		return true
	end

	if (bind:find("+jump", 1, true) or bind:find("+duck", 1, true) or bind:find("+attack", 1, true)) then
		return true
	end
end

-- The one line at the mirror, as Fallout 4's mirror has: how others will see you, and the keys. (The
-- mirror replaced the character menu, the one screen this rule always allowed.)
function PLUGIN:HUDPaint()
	if (self.mirrorBlend < 0.95) then
		return
	end

	local client = LocalPlayer()
	local character = client:GetCharacter()

	if (!character) then
		return
	end

	local seen = self:Seen(client:GetModel(), character:GetData("stature", self.middleStature),
		character:GetData("age", self.middleAge))
	local function Key(bind, fallback)
		return (input.LookupBinding(bind) or fallback):upper()
	end
	local keys = string.format("%s %s  another body      %s %s  taller, shorter      %s  older, younger      %s  done",
		Key("+moveleft", "a"), Key("+moveright", "d"), Key("+forward", "w"), Key("+back", "s"),
		Key("+reload", "r"), Key("+use", "e"))
	local w, h = ScrW(), ScrH()

	draw.SimpleText(seen, "ixMediumLightFont", w / 2 + 1, h * 0.86 + 1, Color(0, 0, 0, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(seen, "ixMediumLightFont", w / 2, h * 0.86, Color(235, 228, 210), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(keys, "ixSmallFont", w / 2 + 1, h * 0.91 + 1, Color(0, 0, 0, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(keys, "ixSmallFont", w / 2, h * 0.91, Color(190, 185, 170, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
