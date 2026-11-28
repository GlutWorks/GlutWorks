local PLUGIN = PLUGIN

ix.option.Add("weatherParticles", ix.type.number, 1, {
	category = "weather", min = 0, max = 2, decimals = 1
})

ix.weather.RAIN_SOUND = "ambient/weather/rumble_rain.wav"
ix.weather.WIND_SOUND = "ambient/wind/wasteland_wind.wav"

-- Particles spawn within this many units of a point just ahead of the view, more of them close in.
local SPAWN_RADIUS = 600
-- Size of a cached "open to the sky" column, and how long one is trusted.
local COLUMN_SIZE = 24
local COLUMN_LIFE = 4
-- Particles per second at full precipitation and a particle scale of 1.
local RAIN_RATE, SNOW_RATE = 2600, 900
local RAIN_SPEED, SNOW_SPEED = 900, 110
-- Highest a particle starts above the view.
local SPAWN_HEIGHT = 360

-- A Lua refresh or a second load must not leave the previous load's sounds playing or its emitter alive.
if (ix.weather.sounds) then
	for _, v in pairs(ix.weather.sounds) do
		v:Stop()
	end
end

if (ix.weather.emitter and ix.weather.emitter:IsValid()) then
	ix.weather.emitter:Finish()
end

ix.weather.sounds = {}
ix.weather.volumes = {}
ix.weather.emitter = nil
ix.weather.columns = {}
ix.weather.columnCount = 0
ix.weather.openness = 0
ix.weather.viewOrigin = ix.weather.viewOrigin or Vector()
ix.weather.viewForward = ix.weather.viewForward or Vector(1, 0, 0)

net.Receive("ixWeatherState", function()
	local state = {
		type = net.ReadString(),
		previous = net.ReadString(),
		changedAt = net.ReadDouble(),
		transition = net.ReadDouble(),
		endsAt = net.ReadDouble()
	}

	if (!ix.weather.types[state.type]) then
		state.type = "clear"
	end

	if (!ix.weather.types[state.previous]) then
		state.previous = state.type
	end

	local old = ix.weather.state.type

	ix.weather.state = state

	if (old != state.type) then
		hook.Run("WeatherChanged", state.type, old)
	end
end)

local function StopAll()
	for name, v in pairs(ix.weather.sounds) do
		v:Stop()
		ix.weather.volumes[name] = 0
	end

	if (ix.weather.emitter) then
		if (ix.weather.emitter:IsValid()) then
			ix.weather.emitter:Finish()
		end

		ix.weather.emitter = nil
	end
end

ix.weather.StopAll = StopAll

local function Character()
	local client = LocalPlayer()

	return IsValid(client) and client:GetCharacter()
end

net.Receive("ixWeatherThunder", function()
	local index = net.ReadUInt(4)
	local distance = net.ReadFloat()
	local path = ix.weather.thunderSounds[index]

	if (!path or !Character()) then
		return
	end

	local openness = ix.weather.openness

	if (openness > 0.05) then
		ix.weather.flash = {time = RealTime(), strength = (1 - distance * 0.7) * openness}
	end

	local volume = (0.45 + 0.55 * (1 - distance)) * (0.35 + 0.65 * openness)

	timer.Simple(distance * 2.5, function()
		local client = LocalPlayer()

		if (IsValid(client) and client:GetCharacter()) then
			client:EmitSound(path, 0, math.random(92, 106), volume, CHAN_STATIC)
		end
	end)
end)

function PLUGIN:RenderScene(origin, angles)
	ix.weather.viewOrigin = origin
	ix.weather.viewForward = angles:Forward()
end

local skyTrace = {mask = MASK_SOLID, filter = ix.weather.SkyTraceFilter}
local groundTrace = {mask = bit.bor(MASK_SOLID, MASK_WATER), filter = ix.weather.SkyTraceFilter}
local up, down = Vector(0, 0, 32768), Vector(0, 0, -4096)

-- A column of air at (x, y) from the view's height up: where particles may start (top) and where they land
-- (bottom), or false when something covers it.
local function Column(x, y, viewZ)
	local gx, gy, gz = math.floor(x / COLUMN_SIZE), math.floor(y / COLUMN_SIZE), math.floor(viewZ / 128)
	local key = gx .. ":" .. gy .. ":" .. gz
	local now = RealTime()
	local column = ix.weather.columns[key]

	if (column != nil and column.expires > now) then
		return column.open and column
	end

	if (ix.weather.columnCount > 6000) then
		ix.weather.columns = {}
		ix.weather.columnCount = 0
	end

	local start = Vector((gx + 0.5) * COLUMN_SIZE, (gy + 0.5) * COLUMN_SIZE, viewZ + 16)

	skyTrace.start = start
	skyTrace.endpos = start + up

	local sky = util.TraceLine(skyTrace)

	column = {expires = now + COLUMN_LIFE + math.Rand(0, 1), open = false}

	if (!sky.StartSolid and (sky.HitSky or !sky.Hit)) then
		local top = math.min(sky.HitPos.z - 4, viewZ + SPAWN_HEIGHT)
		local from = Vector(start.x, start.y, top)

		groundTrace.start = from
		groundTrace.endpos = from + down

		local ground = util.TraceLine(groundTrace)
		local light = render.GetLightColor(ground.HitPos + Vector(0, 0, 48))

		column.open = true
		column.top = top
		column.bottom = ground.HitPos.z
		column.light = math.Clamp(0.35 + (light.x + light.y + light.z) * 0.6, 0.35, 1)
	end

	ix.weather.columns[key] = column
	ix.weather.columnCount = ix.weather.columnCount + 1

	return column.open and column
end

ix.weather.Column = Column

local nextOpenness = 0
local probeTrace = {mask = MASK_SOLID, filter = ix.weather.SkyTraceFilter}
local probes = {Vector(140, 0, 0), Vector(-140, 0, 0), Vector(0, 140, 0), Vector(0, -140, 0)}

-- How open to the sky the view is, 0..1: the point itself counts double, plus four points around it that are
-- not behind a wall. Near a doorway or window it sits between the two, which is what the sounds follow.
local function UpdateOpenness()
	local now = RealTime()

	if (now < nextOpenness) then
		return
	end

	nextOpenness = now + 0.25

	local origin = ix.weather.viewOrigin
	local total = ix.weather.IsOutdoors(origin) and 2 or 0

	for _, offset in ipairs(probes) do
		probeTrace.start = origin
		probeTrace.endpos = origin + offset

		local trace = util.TraceLine(probeTrace)
		local point = trace.Hit and (trace.HitPos - offset:GetNormalized() * 8) or trace.HitPos

		if (!trace.StartSolid and ix.weather.IsOutdoors(point)) then
			total = total + 1
		end
	end

	ix.weather.openness = total / 6
end

local function Loop(name, path, target, delta)
	local volume = math.Approach(ix.weather.volumes[name] or 0, target, delta * 0.6)
	local patch = ix.weather.sounds[name]

	ix.weather.volumes[name] = volume

	if (volume <= 0.005) then
		if (patch and patch:IsPlaying()) then
			patch:Stop()
		end

		return
	end

	if (!patch) then
		patch = CreateSound(LocalPlayer(), path)
		patch:SetSoundLevel(0)
		ix.weather.sounds[name] = patch
	end

	-- restarted when the file reaches its end, in case it has no loop points
	if (!patch:IsPlaying()) then
		patch:PlayEx(volume, 100)
	else
		patch:ChangeVolume(volume, 0)
	end
end

local function UpdateSounds(delta)
	local openness = ix.weather.openness
	local precipitation = ix.weather.GetValue("precipitation")
	local bRain = ix.weather.GetPrecipitationKind(precipitation) == "rain"

	Loop("rain", ix.weather.RAIN_SOUND, bRain and precipitation * (0.12 + 0.78 * openness) or 0, delta)
	Loop("wind", ix.weather.WIND_SOUND, ix.weather.GetValue("wind") * (0.08 + 0.62 * openness), delta)
end

local spawnBudget = 0

local function SpawnParticles(delta)
	local precipitation = ix.weather.GetValue("precipitation")
	local scale = ix.option.Get("weatherParticles", 1)
	local kind = ix.weather.GetPrecipitationKind(precipitation)

	if (!kind or scale <= 0) then
		spawnBudget = 0
		return
	end

	local bSnow = kind == "snow"

	spawnBudget = math.min(spawnBudget + (bSnow and SNOW_RATE or RAIN_RATE) * precipitation * scale * delta, 120)

	local count = math.floor(spawnBudget)

	if (count < 1) then
		return
	end

	spawnBudget = spawnBudget - count

	local origin = ix.weather.viewOrigin
	local forward = ix.weather.viewForward
	local centre = origin + Vector(forward.x, forward.y, 0):GetNormalized() * (SPAWN_RADIUS * 0.3)
	local emitter = ix.weather.emitter

	if (!emitter or !emitter:IsValid()) then
		emitter = ParticleEmitter(origin, false)
		ix.weather.emitter = emitter
	end

	emitter:SetPos(origin)

	-- the wind blows from a direction fixed for each spell of weather
	local yaw = (ix.weather.state.changedAt * 47) % 360
	local wind = ix.weather.GetValue("wind")
	local drift = Angle(0, yaw, 0):Forward() * wind * (bSnow and 90 or 220)
	local speed = bSnow and SNOW_SPEED or RAIN_SPEED
	local material = bSnow and "particle/particle_glow_04" or "particle/rain_streak"

	for _ = 1, count do
		local distance = SPAWN_RADIUS * math.Rand(0.03, 1) ^ 1.5
		local direction = math.Rand(0, math.pi * 2)
		local x = centre.x + math.cos(direction) * distance
		local y = centre.y + math.sin(direction) * distance
		local column = Column(x, y, origin.z)
		local z, landing, bottom

		if (column and column.top > column.bottom) then
			local low = math.max(column.bottom, origin.z - 250)

			z = math.Rand(math.min(low, column.top), column.top)

			-- the wind carries it sideways, so where it lands must be open too, and it stops at the higher ground
			local fall = (z - column.bottom) / speed

			landing = Column(x + drift.x * fall, y + drift.y * fall, origin.z)
			bottom = landing and math.max(column.bottom, landing.bottom)
		end

		local particle = bottom and z > bottom and emitter:Add(material, Vector(x, y, z))

		if (particle) then
			local shade = 255 * column.light
			local velocity = Vector(drift.x, drift.y, -speed)

			if (bSnow) then
				velocity.x = velocity.x + math.Rand(-25, 25)
				velocity.y = velocity.y + math.Rand(-25, 25)
				particle:SetStartSize(math.Rand(1.4, 2.6))
				particle:SetEndSize(particle:GetStartSize())
				particle:SetStartAlpha(230)
				particle:SetEndAlpha(230)
				particle:SetRoll(math.Rand(0, 360))
				particle:SetRollDelta(math.Rand(-2, 2))
			else
				particle:SetStartSize(math.Rand(1.3, 1.9))
				particle:SetEndSize(particle:GetStartSize())
				particle:SetStartLength(math.Rand(50, 80))
				particle:SetEndLength(particle:GetStartLength())
				particle:SetStartAlpha(180)
				particle:SetEndAlpha(180)
			end

			particle:SetColor(shade * 0.9, shade * 0.93, shade)
			particle:SetVelocity(velocity)
			particle:SetGravity(vector_origin)
			particle:SetAirResistance(0)
			particle:SetDieTime((z - bottom) / speed)
		end
	end
end

function PLUGIN:Think()
	if (!Character()) then
		StopAll()
		return
	end

	local delta = FrameTime()

	UpdateOpenness()
	UpdateSounds(delta)
	SpawnParticles(delta)
end

function PLUGIN:CharacterLoaded()
	ix.weather.columns = {}
	ix.weather.columnCount = 0
end

-- How thick the weather's fog is, 0..1: its own fog, and some from rain and low cloud.
local function FogDensity()
	return math.max(ix.weather.GetValue("fog"), ix.weather.GetValue("precipitation") * 0.45,
		ix.weather.GetValue("cloud") * 0.2)
end

local function ApplyFog(scale)
	local density = FogDensity()

	if (density < 0.02) then
		return
	end

	local fogEnd = 26000 * (1 - density) ^ 2 + 600
	local cloud = ix.weather.GetValue("cloud")
	local shade = Lerp(cloud, 190, 105)
	local r, g, b = shade, shade + 3, shade + 8

	-- the map's own fog, if closer, stays as close
	if (render.GetFogMode() != MATERIAL_FOG_NONE) then
		local _, mapEnd = render.GetFogDistances()

		if (mapEnd and mapEnd > 0) then
			fogEnd = math.min(fogEnd, mapEnd / scale)
		end
	end

	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(fogEnd * 0.05 * scale)
	render.FogEnd(fogEnd * scale)
	render.FogMaxDensity(math.min(1, 0.55 + 0.45 * density))
	render.FogColor(r, g, b)

	return true
end

-- These return true only while weather fog is drawn, so the map's own fog is untouched otherwise.
function PLUGIN:SetupWorldFog()
	return ApplyFog(1)
end

function PLUGIN:SetupSkyboxFog(scale)
	return ApplyFog(scale)
end

local skyColour = Color(0, 0, 0, 0)

-- Overcast: a grey veil over the 2D sky, as thick as the cloud and fog.
function PLUGIN:PostDraw2DSkyBox()
	local alpha = math.max(ix.weather.GetValue("cloud") * 0.8, FogDensity())

	if (alpha < 0.02) then
		return
	end

	local shade = Lerp(ix.weather.GetValue("cloud"), 190, 105)

	skyColour.r, skyColour.g, skyColour.b = shade, shade + 3, shade + 8
	skyColour.a = math.min(alpha, 0.97) * 255

	render.OverrideDepthEnable(true, false)
	cam.Start3D(vector_origin, EyeAngles())
		render.SetColorMaterial()
		render.CullMode(MATERIAL_CULLMODE_CW)
		render.DrawSphere(vector_origin, 64, 16, 12, skyColour)
		render.CullMode(MATERIAL_CULLMODE_CCW)
	cam.End3D()
	render.OverrideDepthEnable(false, false)
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

-- Heavy cloud dims and greys the picture a little; a lightning strike brightens it for a moment. Applied on top
-- of whatever else draws colour correction.
function PLUGIN:RenderScreenspaceEffects()
	local cloud = ix.weather.GetValue("cloud")
	local flash = 0
	local strike = ix.weather.flash

	if (strike) then
		local age = RealTime() - strike.time

		if (age > 0.35) then
			ix.weather.flash = nil
		else
			-- two quick pulses
			flash = strike.strength * math.max(0, 1 - age / 0.35) * (age < 0.08 and 1 or (age < 0.14 and 0.3 or 0.8))
		end
	end

	if (cloud < 0.02 and flash <= 0) then
		return
	end

	colourModify["$pp_colour_brightness"] = -0.06 * cloud + 0.35 * flash
	colourModify["$pp_colour_contrast"] = 1 - 0.08 * cloud
	colourModify["$pp_colour_colour"] = 1 - 0.3 * cloud

	DrawColorModify(colourModify)
end
