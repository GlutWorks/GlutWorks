local PLUGIN = PLUGIN

-- What the body shows. Nothing here is a bar, icon or number: the screen drains toward blue with frost at the
-- edges in the cold and warms with glare in the heat, the aim shivers, breath shows in cold air on everyone,
-- and a soaked body drips for others to see.
PLUGIN.visual = {
	-- severities run 0..1 from these temperatures to ±100
	coldFrom = 15,
	heatFrom = 20,
	smoothing = 0.35, -- per second
	cold = {
		desaturate = 0.5,
		blue = 0.035, -- $pp_colour_addb at worst
		dim = 0.04,
		frostColour = Color(205, 228, 255),
		frostAlpha = 210,
		frostReach = 0.55 -- how far beyond the screen the frost starts, as a share of the screen at the mildest
	},
	heat = {
		red = 0.045,
		green = 0.015,
		saturate = 0.12,
		glare = 0.9, -- bloom multiplier at worst
		edgeColour = Color(255, 150, 70),
		edgeAlpha = 70
	},
	shiver = {
		from = 50, -- temperature magnitude where shivering starts ("cold")
		degrees = {0.08, 0.45},
		speed = 9
	},
	breath = {
		range = 1400,
		interval = {3.2, 4.2},
		hardInterval = {1.4, 1.9}, -- while moving fast or out of breath
		airCache = 2, -- seconds a player's air temperature is kept
		material = "particle/particle_smokegrenade",
		puffs = 4,
		alpha = {45, 85}, -- start alpha from just below breathBelow to 15 °C colder
		size = {1.5, 2.5}, -- start size, units
		endSize = {9, 14},
		life = {1.6, 2.4}
	},
	drips = {
		range = 900,
		interval = {0.12, 0.3},
		material = "particle/particle_smokegrenade"
	}
}

local visual = PLUGIN.visual
local vignette = ix.util.GetMaterial("helix/gui/vignette.png")

-- Handles are kept on ix.exposure so a Lua refresh can finish what the previous load started.
local function Cleanup()
	if (ix.exposure.emitter) then
		ix.exposure.emitter:Finish()
		ix.exposure.emitter = nil
	end
end

Cleanup()

local state = {}

local function ResetState()
	state = {cold = 0, heat = 0, shiver = 0, shiverOffset = Angle(0, 0, 0), character = nil}
end

ResetState()

--- The live smoothed severities, for inspection.
function PLUGIN:GetBodyState()
	return state
end

local function Emitter()
	if (!ix.exposure.emitter) then
		ix.exposure.emitter = ParticleEmitter(vector_origin)
	end

	return ix.exposure.emitter
end

local function IsSealedTeam(client)
	local faction = ix.faction.indices[client:Team()]

	return faction != nil and faction.bClimateSealed == true
end

local function Wander(time)
	return math.sin(time) * 0.5 + math.sin(time * 1.37 + 2.1) * 0.3 + math.sin(time * 2.71 + 0.4) * 0.2
end

-- Moves the aim by the change of a bounded jitter since the last frame, so it never adds up and nothing has to
-- return from CalcView.
local function UpdateShiver(client, now)
	local offset

	if (state.shiver <= 0.001 or ix.option.Get("reduceMotionEffects", false) or client:InVehicle() or
		IsValid(Entity(client:GetLocalVar("ragdoll", 0)))) then
		offset = Angle(0, 0, 0)
	else
		local degrees = Lerp(state.shiver, visual.shiver.degrees[1], visual.shiver.degrees[2])
		local time = now * visual.shiver.speed

		offset = Angle(Wander(time + 5) * degrees, Wander(time * 1.21) * degrees, 0)
	end

	local delta = offset - state.shiverOffset
	state.shiverOffset = offset

	if (delta.p == 0 and delta.y == 0) then
		return
	end

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

local function MouthPosition(client)
	local index = client:LookupAttachment("mouth")
	local attachment = index and index > 0 and client:GetAttachment(index)

	if (attachment) then
		return attachment.Pos, attachment.Ang:Forward()
	end

	local angles = client:EyeAngles()
	angles.p = 0

	return client:EyePos() + angles:Forward() * 4 - Vector(0, 0, 3), angles:Forward()
end

local function AirAt(client, now)
	if (!client.ixExposureAirTime or now - client.ixExposureAirTime > visual.breath.airCache) then
		client.ixExposureAirTime = now
		client.ixExposureAir = ix.weather and ix.weather.GetTemperatureAt(client:EyePos()) or 15
	end

	return client.ixExposureAir
end

--- One breath of vapour at a player's mouth. `coldness` 0..1 makes it denser.
function PLUGIN:EmitBreath(client, coldness)
	local position, forward = MouthPosition(client)
	local emitter = Emitter()
	local velocity = client:GetVelocity() * 0.6

	local breath = visual.breath

	for _ = 1, breath.puffs do
		local particle = emitter:Add(breath.material, position + VectorRand() * 0.5)

		if (particle) then
			particle:SetVelocity(velocity + forward * math.Rand(14, 24) + VectorRand() * 3 + Vector(0, 0, 2))
			particle:SetDieTime(math.Rand(breath.life[1], breath.life[2]))
			particle:SetStartAlpha(Lerp(coldness, breath.alpha[1], breath.alpha[2]))
			particle:SetEndAlpha(0)
			particle:SetStartSize(math.Rand(breath.size[1], breath.size[2]))
			particle:SetEndSize(math.Rand(breath.endSize[1], breath.endSize[2]))
			particle:SetRoll(math.Rand(0, 360))
			particle:SetRollDelta(math.Rand(-0.6, 0.6))
			particle:SetColor(235, 240, 245)
			particle:SetAirResistance(70)
			particle:SetGravity(Vector(0, 0, 4))
		end
	end
end

--- One drop of water falling from a soaked player.
function PLUGIN:EmitDrip(client)
	local mins, maxs = client:OBBMins(), client:OBBMaxs()
	local position = client:GetPos() + Vector(math.Rand(mins.x, maxs.x) * 0.6, math.Rand(mins.y, maxs.y) * 0.6,
		math.Rand(maxs.z * 0.25, maxs.z * 0.8))
	local particle = Emitter():Add(visual.drips.material, position)

	if (particle) then
		particle:SetVelocity(client:GetVelocity() * 0.8 + Vector(0, 0, -30))
		particle:SetDieTime(0.7)
		particle:SetStartAlpha(140)
		particle:SetEndAlpha(60)
		particle:SetStartSize(0.6)
		particle:SetEndSize(0.4)
		particle:SetColor(190, 205, 220)
		particle:SetGravity(Vector(0, 0, -600))
		particle:SetCollide(true)
		particle:SetStartLength(3)
		particle:SetEndLength(5)
	end
end

local function UpdateOthers(viewer, now)
	local origin = EyePos()
	local breathRange, dripRange = visual.breath.range ^ 2, visual.drips.range ^ 2
	local bFirstPerson = !viewer:ShouldDrawLocalPlayer()
	local breathBelow = ix.exposure.tuning.breathBelow

	if (!ix.config.Get("exposureEnabled", true)) then
		return
	end

	for _, client in player.Iterator() do
		if (!client:Alive() or client:IsDormant() or !client:GetCharacter() or IsSealedTeam(client) or
			client:GetMoveType() == MOVETYPE_NOCLIP or client:GetNoDraw() or (client == viewer and bFirstPerson)) then
			continue
		end

		local distance = origin:DistToSqr(client:EyePos())

		if (distance <= breathRange and now >= (client.ixExposureNextBreath or 0)) then
			local air = AirAt(client, now)
			local bHard = client:GetVelocity():Length2D() > client:GetWalkSpeed() + 20 or client:GetNetVar("brth", false)
			local interval = bHard and visual.breath.hardInterval or visual.breath.interval

			client.ixExposureNextBreath = now + math.Rand(interval[1], interval[2])

			if (air <= breathBelow and client:WaterLevel() < 3) then
				PLUGIN:EmitBreath(client, math.Clamp((breathBelow - air) / 15, 0, 1))
			end
		end

		if (distance <= dripRange and client:GetNetVar("ixSoaked") and client:WaterLevel() < 2 and
			now >= (client.ixExposureNextDrip or 0)) then
			client.ixExposureNextDrip = now + math.Rand(visual.drips.interval[1], visual.drips.interval[2])
			PLUGIN:EmitDrip(client)
		end
	end
end

--- The cold and heat severities (0..1) the screen should show for a temperature.
function PLUGIN:GetSeverities(temperature)
	local cold = math.Clamp((-temperature - visual.coldFrom) / (100 - visual.coldFrom), 0, 1)
	local heat = math.Clamp((temperature - visual.heatFrom) / (100 - visual.heatFrom), 0, 1)

	return cold, heat
end

function PLUGIN:Think()
	local client = LocalPlayer()

	if (!IsValid(client)) then
		return
	end

	local now = RealTime()

	UpdateOthers(client, now)

	local character = client:GetCharacter()
	local bFeels = ix.exposure.Applies(client) and client:GetViewEntity() == client and
		!(IsValid(ix.gui.characterMenu) and !ix.gui.characterMenu:IsClosing())

	if (!bFeels) then
		if (state.character) then
			ResetState()
		end

		return
	end

	if (state.character != character:GetID()) then
		ResetState()
		state.character = character:GetID()
	end

	local temperature = character:GetTemperature()
	local cold, heat = self:GetSeverities(temperature)
	local rate = RealFrameTime() * visual.smoothing

	state.cold = math.Approach(state.cold, cold, rate)
	state.heat = math.Approach(state.heat, heat, rate)

	local shiver = math.Clamp((-temperature - visual.shiver.from) / (100 - visual.shiver.from), 0, 1)

	-- starts small rather than at nothing once "cold" is reached
	if (-temperature >= visual.shiver.from) then
		shiver = 0.1 + shiver * 0.9
	end

	state.shiver = math.Approach(state.shiver, shiver, rate)

	UpdateShiver(client, now)
end

local colourModify = {
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

-- Helix's soft vignette, tinted, drawn larger than the screen at low strength so only the corners show and
-- closing in as it grows.
local function DrawEdges(colour, alpha, reach, width, height)
	if (vignette:IsError() or alpha < 1) then
		return
	end

	local extraX, extraY = width * reach, height * reach

	surface.SetMaterial(vignette)
	surface.SetDrawColor(colour.r, colour.g, colour.b, alpha)
	surface.DrawTexturedRect(-extraX, -extraY, width + extraX * 2, height + extraY * 2)
end

function PLUGIN:RenderScreenspaceEffects()
	if (!state.character) then
		return
	end

	local cold, heat = state.cold, state.heat

	if (cold < 0.005 and heat < 0.005) then
		return
	end

	colourModify["$pp_colour_colour"] = 1 - cold * visual.cold.desaturate + heat * visual.heat.saturate
	colourModify["$pp_colour_addb"] = cold * visual.cold.blue
	colourModify["$pp_colour_addr"] = heat * visual.heat.red
	colourModify["$pp_colour_addg"] = heat * visual.heat.green
	colourModify["$pp_colour_brightness"] = -cold * visual.cold.dim

	DrawColorModify(colourModify)

	if (heat > 0.05) then
		DrawBloom(0.65, heat * visual.heat.glare, 9, 9, 1, 1, 1, 0.9, 0.75)
	end

	local width, height = ScrW(), ScrH()

	cam.Start2D()
		if (cold > 0.005) then
			-- frost creeps in from the corners: the square root makes it visible early, the reach shrinks with it
			DrawEdges(visual.cold.frostColour, visual.cold.frostAlpha * math.sqrt(cold),
				visual.cold.frostReach * (1 - cold), width, height)
		end

		if (heat > 0.005) then
			DrawEdges(visual.heat.edgeColour, visual.heat.edgeAlpha * heat, 0.3 * (1 - heat), width, height)
		end
	cam.End2D()
end

function PLUGIN:CharacterLoaded()
	ResetState()
end

function PLUGIN:ShutDown()
	Cleanup()
end
