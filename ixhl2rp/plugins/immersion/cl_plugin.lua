
local PLUGIN = PLUGIN

-- Everything the body feedback can be tuned with. Severities run from 0 (fine) to 1 (worst);
-- a {a, b} pair is the value at the mildest and at the worst severity. Amounts are fractions of
-- full effect unless said otherwise; volumes are 0-1.
PLUGIN.tuning = {
	health = {
		start = 0.6, -- health fraction where desaturation and the vignette begin
		desaturate = 0.8, -- colour removed at worst
		vignette = 1.4, -- vignette strength at worst (see vignette below)
		heartbeatBelow = 0.35, -- health fraction where the heartbeat starts
		heartbeatInterval = {1.15, 0.55}, -- seconds between beats
		heartbeatVolume = {0.12, 0.4},
		heartbeatPitch = {95, 108},
		beatVignette = 0.45, -- extra vignette on each beat at worst
		beatDecay = 7 -- how fast the beat's pulse fades, per second
	},
	damage = {
		full = 30, -- a hit of this much health gives the full pulse
		vignette = 0.9,
		blur = 4, -- blur amount (ix.util.DrawBlurAt scale) at a full pulse
		decay = 2.5 -- per second
	},
	stamina = {
		start = 40, -- stamina where the breathing starts
		breathVolume = {0.04, 0.22},
		exhaustedVolume = 0.32, -- while exhausted (the walk-only state)
		breathPitch = {96, 106},
		fade = 0.8 -- seconds to fade the breathing in or out
	},
	hunger = {
		growlInterval = {45, 12}, -- average seconds between stomach growls
		growlVolume = {0.12, 0.25},
		growlPitch = {70, 85},
		drift = {0.05, 0.3}, -- aim wander in degrees, either side of centre
		driftSpeed = 0.35, -- how fast the aim wanders (radians of the slowest wave per second)
		dimFrom = 0.5, -- severity where light-headed dimming starts (the last hunger step)
		dimInterval = {16, 7}, -- average seconds between dimming spells
		dimLength = 1.8, -- seconds
		dimDarken = 0.38, -- how much the screen dims at the height of a spell, at worst
		dimVignette = 0.6
	},
	thirst = {
		waveInterval = {28, 9}, -- average seconds between waves of blur and glare
		waveLength = {3.5, 6}, -- seconds
		blur = {1, 3.5}, -- blur amount at the height of a wave
		blurAlpha = {0.3, 0.85},
		glare = {0.5, 1.4} -- bloom multiplier at the height of a wave
	},
	vignette = {
		-- strength 1 is Helix's corner vignette at full; beyond that only the edge bands deepen
		edgeAlpha = 0.65, -- edge band opacity per unit of strength
		maxEdgeAlpha = 0.85, -- the edges never go fully black
		edgeSize = {0.12, 0.42} -- edge band size as a fraction of the screen, weakest to strongest
	},
	combined = {
		maxVignette = 2,
		maxDarken = 0.3,
		minColour = 0.15, -- never fully grey
		maxBlur = 4.5,
		maxBlurAlpha = 0.85, -- never fully blurred
		maxGlare = 1.5,
		smoothing = 1.5 -- how fast severities follow the body, per second
	},
	sounds = {
		heartbeat = "player/heartbeat1.wav",
		breath = "player/breathe1.wav",
		growl = {"npc/barnacle/barnacle_digesting1.wav", "npc/barnacle/barnacle_digesting2.wav"}
	}
}

local tuning = PLUGIN.tuning
local vignette = ix.util.GetMaterial("helix/gui/vignette.png")

local function Range(pair, fraction)
	return Lerp(math.Clamp(fraction, 0, 1), pair[1], pair[2])
end

local function Envelope(start, length, now)
	local fraction = (now - start) / length

	if (fraction <= 0 or fraction >= 1) then
		return 0
	end

	return math.sin(fraction * math.pi)
end

-- Kept on ix so a Lua refresh can stop the sounds the previous load started.
ix.immersionSounds = ix.immersionSounds or {}

local function StopSounds()
	for k, v in pairs(ix.immersionSounds) do
		v:Stop()
		ix.immersionSounds[k] = nil
	end
end

StopSounds()

local state = {}

local function ResetState()
	state = {
		health = 0, stamina = 0, hunger = 0, thirst = 0, drift = 0,
		damage = 0, beat = 0, nextBeat = 0,
		nextGrowl = 0, dimStart = -100, nextDim = 0,
		waveStart = -100, waveLength = 1, nextWave = 0,
		lastHealth = nil, character = nil,
		driftOffset = Angle(0, 0, 0)
	}
end

ResetState()

--- The live body feedback state (smoothed severities, pulse timers). For inspection and tests.
function PLUGIN:GetBodyState()
	return state
end

--- Whether the body can be felt now: alive with a character, in the world and not in the
-- character menu, observing or noclipping.
function PLUGIN:CanFeelBody(client)
	if (!IsValid(client) or !client:GetCharacter() or !client:Alive()) then
		return false
	end

	if (IsValid(ix.gui.characterMenu) and !ix.gui.characterMenu:IsClosing()) then
		return false
	end

	if (client:GetMoveType() == MOVETYPE_NOCLIP or client:GetObserverMode() != OBS_MODE_NONE) then
		return false
	end

	return client:GetViewEntity() == client
end

local function NeedSeverity(levels, amount)
	local survival = ix.plugin.Get("survivaladditions")

	if (!survival or !ix.config.Get("hungerthirstEnabled", false)) then
		return 0
	end

	return survival:GetNeedSeverity(survival[levels], amount)
end

-- What each condition's severity should be now, before smoothing.
local function Targets(client)
	local character = client:GetCharacter()
	local fraction = client:Health() / math.max(client:GetMaxHealth(), 1)
	local stamina = client:GetLocalVar("stm", 100)
	local breath = 0

	if (client:GetNetVar("brth", false)) then
		breath = 1
	elseif (stamina < tuning.stamina.start) then
		breath = 0.85 * (tuning.stamina.start - stamina) / tuning.stamina.start
	end

	return {
		health = math.Clamp((tuning.health.start - fraction) / tuning.health.start, 0, 1),
		heartbeat = math.Clamp((tuning.health.heartbeatBelow - fraction) / tuning.health.heartbeatBelow, 0, 1),
		stamina = breath,
		hunger = NeedSeverity("hungerLevels", character:GetHunger()),
		thirst = NeedSeverity("thirstLevels", character:GetThirst())
	}
end

local function PlayOnce(path, volume, pitch)
	-- sound level 0 plays without distance falloff, so it is heard the same in third person
	LocalPlayer():EmitSound(path, 0, pitch, volume, CHAN_STATIC)
end

local function UpdateBreath(client, severity, bExhausted)
	local breath = ix.immersionSounds.breath

	if (severity <= 0.01) then
		if (breath and breath:IsPlaying()) then
			if (breath:GetVolume() <= 0.001) then
				breath:Stop()
			else
				breath:ChangeVolume(0, tuning.stamina.fade)
			end
		end

		return
	end

	local volume = bExhausted and tuning.stamina.exhaustedVolume or Range(tuning.stamina.breathVolume, severity)
	local pitch = Range(tuning.stamina.breathPitch, severity)

	if (!breath) then
		breath = CreateSound(client, tuning.sounds.breath)
		ix.immersionSounds.breath = breath
	end

	if (!breath:IsPlaying()) then
		breath:PlayEx(0, pitch)
	end

	breath:ChangeVolume(volume, tuning.stamina.fade)
	breath:ChangePitch(pitch, tuning.stamina.fade)
end

local function Wander(time)
	return math.sin(time) * 0.6 + math.sin(time * 1.73 + 1.3) * 0.4
end

-- Moves the aim by the change of a bounded wander since the last frame, so it never adds up.
local function UpdateDrift(client, now)
	local amount = state.drift
	local offset

	if (amount <= 0.001 or ix.option.Get("reduceMotionEffects", false) or client:InVehicle() or
		IsValid(Entity(client:GetLocalVar("ragdoll", 0)))) then
		offset = Angle(0, 0, 0)
	else
		local time = now * tuning.hunger.driftSpeed
		local degrees = Range(tuning.hunger.drift, amount)

		offset = Angle(Wander(time + 11) * degrees, Wander(time * 0.83) * degrees, 0)
	end

	local delta = offset - state.driftOffset
	state.driftOffset = offset

	if (delta.p == 0 and delta.y == 0) then
		return
	end

	-- third person aims from its own camera angles; first person from the eye angles
	if (client.CanOverrideView and client:CanOverrideView() and client.camAng) then
		client.camAng.p = math.Clamp(client.camAng.p + delta.p, -85, 85)
		client.camAng.y = client.camAng.y + delta.y
	else
		local angles = client:EyeAngles()
		angles.p = math.Clamp(angles.p + delta.p, -89, 89)
		angles.y = angles.y + delta.y
		angles.r = 0

		client:SetEyeAngles(angles)
	end
end

function PLUGIN:Think()
	local client = LocalPlayer()

	if (!self:CanFeelBody(client)) then
		if (state.character or next(ix.immersionSounds)) then
			StopSounds()
			ResetState()
		end

		return
	end

	local character = client:GetCharacter()

	if (state.character != character:GetID()) then
		StopSounds()
		ResetState()
		state.character = character:GetID()
	end

	local now = RealTime()
	local frameTime = RealFrameTime()
	local targets = Targets(client)
	local rate = frameTime * tuning.combined.smoothing

	state.health = math.Approach(state.health, targets.health, rate)
	state.stamina = math.Approach(state.stamina, targets.stamina, rate * 2)
	state.hunger = math.Approach(state.hunger, targets.hunger, rate)
	state.thirst = math.Approach(state.thirst, targets.thirst, rate)
	state.drift = math.Approach(state.drift, targets.hunger, frameTime * 0.25)

	-- a hit: a short pulse proportional to the damage
	local health = client:Health()

	if (state.lastHealth and health < state.lastHealth) then
		state.damage = math.min(state.damage + (state.lastHealth - health) / tuning.damage.full, 1)
	end

	state.lastHealth = health
	state.damage = math.max(state.damage - frameTime * tuning.damage.decay, 0)

	-- heartbeat
	state.beat = math.max(state.beat - frameTime * tuning.health.beatDecay, 0)
	state.heartbeat = targets.heartbeat

	if (targets.heartbeat > 0 and now >= state.nextBeat) then
		local severity = targets.heartbeat

		PlayOnce(tuning.sounds.heartbeat, Range(tuning.health.heartbeatVolume, severity),
			Range(tuning.health.heartbeatPitch, severity))

		state.beat = 1
		state.nextBeat = now + Range(tuning.health.heartbeatInterval, severity)
	elseif (targets.heartbeat <= 0) then
		state.nextBeat = 0
	end

	-- breathing
	UpdateBreath(client, state.stamina, client:GetNetVar("brth", false))

	-- hunger: growls at irregular intervals, and light-headed spells at the last step
	local hunger = targets.hunger

	if (hunger > 0) then
		if (state.nextGrowl == 0) then
			state.nextGrowl = now + Range(tuning.hunger.growlInterval, hunger) * math.Rand(0.3, 1)
		elseif (now >= state.nextGrowl) then
			local sounds = tuning.sounds.growl

			PlayOnce(sounds[math.random(#sounds)], Range(tuning.hunger.growlVolume, hunger),
				math.Rand(tuning.hunger.growlPitch[1], tuning.hunger.growlPitch[2]))

			state.nextGrowl = now + Range(tuning.hunger.growlInterval, hunger) * math.Rand(0.6, 1.4)
		end
	else
		state.nextGrowl = 0
	end

	if (hunger >= tuning.hunger.dimFrom) then
		local severity = (hunger - tuning.hunger.dimFrom) / (1 - tuning.hunger.dimFrom)

		if (state.nextDim == 0) then
			state.nextDim = now + Range(tuning.hunger.dimInterval, severity) * math.Rand(0.3, 1)
		elseif (now >= state.nextDim) then
			state.dimStart = now
			state.nextDim = now + tuning.hunger.dimLength + Range(tuning.hunger.dimInterval, severity) * math.Rand(0.6, 1.4)
		end
	else
		state.nextDim = 0
	end

	-- thirst: waves of blur and glare
	local thirst = targets.thirst

	if (thirst > 0) then
		if (state.nextWave == 0) then
			state.nextWave = now + Range(tuning.thirst.waveInterval, thirst) * math.Rand(0.2, 0.8)
		elseif (now >= state.nextWave) then
			state.waveStart = now
			state.waveLength = Range(tuning.thirst.waveLength, thirst) * math.Rand(0.8, 1.2)
			state.nextWave = now + state.waveLength + Range(tuning.thirst.waveInterval, thirst) * math.Rand(0.6, 1.4)
		end
	else
		state.nextWave = 0
	end

	UpdateDrift(client, now)
end

local colorModify = {
	["$pp_colour_addr"] = 0,
	["$pp_colour_addg"] = 0,
	["$pp_colour_addb"] = 0,
	["$pp_colour_brightness"] = 0,
	["$pp_colour_contrast"] = 1,
	["$pp_colour_colour"] = 1,
	["$pp_colour_mulr"] = 0,
	["$pp_colour_mulg"] = 0,
	["$pp_colour_mulb"] = 0
}

local gradients = {
	left = ix.util.GetMaterial("vgui/gradient-l"),
	right = ix.util.GetMaterial("vgui/gradient-r"),
	up = ix.util.GetMaterial("vgui/gradient-u"),
	down = ix.util.GetMaterial("vgui/gradient-d")
}

-- Darkens the edges: Helix's soft corner vignette, then dark bands closing in from each edge.
-- `strength` runs from 0 to tuning.combined.maxVignette; the bands grow with it.
local function DrawVignette(strength, width, height)
	local fraction = math.min(strength / tuning.combined.maxVignette, 1)

	if (!vignette:IsError()) then
		surface.SetMaterial(vignette)
		surface.SetDrawColor(0, 0, 0, 255 * math.min(strength, 1))
		surface.DrawTexturedRect(0, 0, width, height)
	end

	local alpha = 255 * math.min(strength * tuning.vignette.edgeAlpha, tuning.vignette.maxEdgeAlpha)
	local band = Lerp(fraction, tuning.vignette.edgeSize[1], tuning.vignette.edgeSize[2])

	-- a wide soft layer and a tighter one on top, so the edges fall off smoothly into dark
	for _, layer in ipairs({{band, 0.7}, {band * 0.5, 1}}) do
		local sideWidth, edgeHeight = width * layer[1], height * layer[1]

		surface.SetDrawColor(0, 0, 0, alpha * layer[2])
		surface.SetMaterial(gradients.left)
		surface.DrawTexturedRect(0, 0, sideWidth, height)
		surface.SetMaterial(gradients.right)
		surface.DrawTexturedRect(width - sideWidth, 0, sideWidth, height)
		surface.SetMaterial(gradients.up)
		surface.DrawTexturedRect(0, 0, width, edgeHeight)
		surface.SetMaterial(gradients.down)
		surface.DrawTexturedRect(0, height - edgeHeight, width, edgeHeight)
	end
end

--- The combined screen effects for the current state, already clamped.
function PLUGIN:GetScreenEffects()
	local now = RealTime()
	local combined = tuning.combined
	local hungerDim = 0

	if (state.hunger >= tuning.hunger.dimFrom) then
		hungerDim = Envelope(state.dimStart, tuning.hunger.dimLength, now) *
			(state.hunger - tuning.hunger.dimFrom * 0.5) / (1 - tuning.hunger.dimFrom * 0.5)
	end

	local wave = state.thirst > 0 and Envelope(state.waveStart, state.waveLength, now) or 0
	local bWaves = !ix.option.Get("reduceMotionEffects", false)

	local effects = {
		colour = 1 - state.health * tuning.health.desaturate,
		darken = hungerDim * tuning.hunger.dimDarken,
		vignette = state.health * tuning.health.vignette +
			state.beat * (state.heartbeat or 0) * tuning.health.beatVignette +
			state.damage * tuning.damage.vignette +
			hungerDim * tuning.hunger.dimVignette,
		blur = state.damage * tuning.damage.blur,
		blurAlpha = state.damage,
		glare = wave * Range(tuning.thirst.glare, state.thirst)
	}

	if (bWaves and wave > 0) then
		effects.blur = effects.blur + wave * Range(tuning.thirst.blur, state.thirst)
		effects.blurAlpha = math.max(effects.blurAlpha, wave * Range(tuning.thirst.blurAlpha, state.thirst))
	end

	effects.colour = math.max(effects.colour, combined.minColour)
	effects.darken = math.min(effects.darken, combined.maxDarken)
	effects.vignette = math.min(effects.vignette, combined.maxVignette)
	effects.blur = math.min(effects.blur, combined.maxBlur)
	effects.blurAlpha = math.min(effects.blurAlpha, combined.maxBlurAlpha)
	effects.glare = math.min(effects.glare, combined.maxGlare)

	return effects
end

function PLUGIN:RenderScreenspaceEffects()
	if (!state.character) then
		return
	end

	local effects = self:GetScreenEffects()

	if (effects.colour < 0.999 or effects.darken > 0.001) then
		colorModify["$pp_colour_colour"] = effects.colour
		-- mostly a scale rather than a subtraction, so dark rooms keep their detail
		colorModify["$pp_colour_brightness"] = -effects.darken * 0.2
		colorModify["$pp_colour_contrast"] = 1 - effects.darken

		DrawColorModify(colorModify)
	end

	if (effects.glare > 0.01) then
		DrawBloom(0.55, effects.glare, 9, 9, 2, 1, 1, 1, 1)
	end

	local bBlur, bVignette = effects.blurAlpha > 0.01 and effects.blur > 0.05, effects.vignette > 0.01

	if (!bBlur and !bVignette) then
		return
	end

	local width, height = ScrW(), ScrH()

	cam.Start2D()
		if (bBlur) then
			ix.util.DrawBlurAt(0, 0, width, height, effects.blur, 0.2, 255 * effects.blurAlpha)
		end

		if (bVignette) then
			DrawVignette(effects.vignette, width, height)
		end
	cam.End2D()
end

function PLUGIN:CharacterLoaded()
	StopSounds()
	ResetState()
end

function PLUGIN:ShutDown()
	StopSounds()
end

-- Holding Walk and pressing Reload checks the magazine instead of reloading: the reload bind is
-- swallowed. Use + Reload is left alone, since TFA switches fire mode and safety with it.
function PLUGIN:PlayerBindPress(client, bind, bPressed)
	if (!bPressed or !bind:find("+reload", 1, true) or !client:KeyDown(IN_WALK)) then
		return
	end

	if (!client:GetCharacter() or !client:Alive() or !self:HasMagazine(client:GetActiveWeapon())) then
		return
	end

	net.Start("ixCheckMagazine")
	net.SendToServer()

	return true
end

-- The always-on HUD. Each hook only answers while it is hidden, so the rest of the chain
-- (the Combine scanner's crosshair rule, other plugins) runs as before otherwise.

function PLUGIN:ShouldHideBars()
	if (self:IsHUDHidden(LocalPlayer())) then
		return true
	end
end

function PLUGIN:CanDrawAmmoHUD(weapon)
	if (self:IsHUDHidden(LocalPlayer())) then
		return false
	end
end

function PLUGIN:ShouldDrawCrosshair(client, weapon)
	if (self:IsHUDHidden(client)) then
		return false
	end
end

function PLUGIN:HUDShouldDraw(element)
	if (element == "CHudDamageIndicator" and self:IsHUDHidden(LocalPlayer())) then
		return false
	end
end

-- TFA Base: true blocks both its crosshair and the engine's.
function PLUGIN:TFA_DrawCrosshair(weapon, x, y)
	if (self:IsHUDHidden(LocalPlayer())) then
		return true
	end
end

-- TFA Base: false skips the ammo readout (and its fallback fire mode text).
function PLUGIN:TFA_DrawHUDAmmo(weapon, x, y, alpha)
	if (self:IsHUDHidden(LocalPlayer())) then
		return false
	end
end

-- TFA Base: true skips the key binding hints shown when a weapon is drawn.
function PLUGIN:TFA_PreDrawKeyBindHint(weapon, x, y, alpha)
	if (self:IsHUDHidden(LocalPlayer())) then
		return true
	end
end

-- TFA's hit markers are queued by these messages and drawn from a HUDPaint hook that has no
-- way to be told not to. While the HUD is hidden the messages are dropped, so nothing queues.
local function WrapHitmarkers()
	ix.immersionHitmarkers = ix.immersionHitmarkers or {}

	local wrapped = ix.immersionHitmarkers

	for _, name in ipairs({"tfahitmarker", "tfahitmarker3d"}) do
		local receiver = net.Receivers[name]

		if (receiver and receiver != wrapped[name]) then
			local original = receiver

			wrapped[name] = function(...)
				local client = LocalPlayer()

				if (ix.config.Get("immersionHideHUD", true) and IsValid(client) and client:GetCharacter()) then
					return
				end

				return original(...)
			end

			net.Receivers[name] = wrapped[name]
		end
	end
end

WrapHitmarkers()

function PLUGIN:InitPostEntity()
	WrapHitmarkers()
end
