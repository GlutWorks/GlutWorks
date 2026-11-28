local PLUGIN = PLUGIN

ix.option.Add("weatherParticles", ix.type.number, 1, {
	category = "weather", min = 0, max = 2, decimals = 1
})

ix.weather.RAIN_SOUND = "ambient/weather/rumble_rain.wav"
ix.weather.WIND_SOUND = "ambient/wind/wasteland_wind.wav"

-- Everything the look of the weather can be tuned with. Distances are units, rates are particles per second at
-- full precipitation and a particle scale of 1, alphas 0..255.
ix.weather.look = {
	columnSize = 24, -- size of a cached "open to the sky" column
	columnLife = 4, -- seconds one is trusted
	spawnHeight = 380, -- highest a particle starts above the view
	maxPerFrame = 640, -- particles of all kinds started in one frame, at most
	rain = {
		-- fine, fast streaks close to the view: what falls on you
		near = {rate = 2400, radius = 420, speed = {1150, 1500}, width = {0.8, 1.5}, length = {70, 150}, alpha = {75, 150}},
		-- thicker ones further out, so the rain has depth
		mid = {rate = 1300, radius = {300, 1000}, speed = {1050, 1350}, width = {2, 3.6}, length = {160, 280}, alpha = {38, 76}},
		-- wide, faint curtains further off: what the distance is seen through
		far = {rate = 90, radius = {500, 2000}, speed = {900, 1150}, width = {12, 30}, length = {380, 720}, alpha = {16, 34}},
		-- a drop hitting the ground: a short splash and a ring that spreads on the surface
		splash = {rate = 1400, radius = 260, size = {1.6, 3.4}, alpha = {110, 180}, life = {0.08, 0.15}},
		ring = {rate = 600, radius = 220, size = {1, 8}, alpha = {150, 220}, life = {0.3, 0.5}},
		-- spray hanging just above the ground in heavy rain
		mist = {rate = 10, radius = {150, 1100}, from = 0.5, size = {70, 150}, alpha = {7, 15}, life = {2.2, 3.6}},
		colour = {205, 212, 222}, -- before the light at the spot
		drift = 430 -- sideways speed at full wind
	},
	snow = {
		rate = 800, radius = 620, speed = {70, 130}, size = {0.9, 2.3}, alpha = {150, 225}, drift = 110, sway = 34
	},
	sky = {
		height = 900, -- the cloud layers sit this far above the eye, in sky units
		reach = 12000, -- and fade out this far away, toward the horizon
		-- Cloud layers, added as light onto the sky's colour: big slow masses and faster, finer scud under
		-- them. scale is sky units per texture repeat, light how bright the cloud's pale parts get.
		layers = {
			{scale = 5200, speed = 9, light = 1.7, offset = {0, 0}},
			{scale = 2900, speed = 15, light = 1.1, offset = {0.37, 0.61}},
			{scale = 1500, speed = 26, light = 0.5, offset = {0.73, 0.19}}
		},
		-- how the stock cloud texture is sharpened: drawn this many times over, then this much grey taken off
		textureGain = 12,
		textureCut = 0.1,
		-- sky colour from thin cloud to the heaviest, and the lighter haze at the horizon
		thin = {126, 134, 146},
		heavy = {76, 81, 89},
		horizon = 1.18
	},
	fog = {
		far = 22000, -- where clear air ends
		near = 900, -- where the thickest weather ends
		rain = 0.72, -- how much full precipitation thickens it, 0..1
		cloud = 0.2
	},
	grade = {
		-- at full cloud outdoors; under cover the grade is this share of it
		indoors = 0.35,
		brightness = -0.1,
		contrast = 0.88,
		colour = 0.48,
		tint = {-0.012, -0.002, 0.012} -- red, green, blue added
	},
	lightning = {
		length = 0.5, -- seconds
		brightness = 0.2,
		sky = 1.3, -- how much the cloud lights up
		light = {size = 5000, brightness = 5, colour = {205, 220, 255}}
	}
}

local look = ix.weather.look
local COLUMN_SIZE, COLUMN_LIFE = look.columnSize, look.columnLife
local SPAWN_HEIGHT = look.spawnHeight

-- A Lua refresh or a second load must not leave the previous load's sounds playing or its emitter alive.
if (ix.weather.sounds) then
	for _, v in pairs(ix.weather.sounds) do
		v:Stop()
	end
end

for _, name in ipairs({"emitter", "groundEmitter"}) do
	if (ix.weather[name] and ix.weather[name]:IsValid()) then
		ix.weather[name]:Finish()
	end
end

ix.weather.sounds = {}
ix.weather.volumes = {}
ix.weather.emitter = nil
ix.weather.groundEmitter = nil
ix.weather.smoothOpenness = ix.weather.smoothOpenness or 0
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

	for _, name in ipairs({"emitter", "groundEmitter"}) do
		if (ix.weather[name]) then
			if (ix.weather[name]:IsValid()) then
				ix.weather[name]:Finish()
			end

			ix.weather[name] = nil
		end
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

	-- under cover it still comes in through the openings
	local strength = (1 - distance * 0.7) * (0.25 + 0.75 * openness)

	ix.weather.flash = {time = RealTime(), strength = strength}

	if (openness > 0.05) then
		local light = DynamicLight(LocalPlayer():EntIndex())
		local info = ix.weather.look.lightning.light

		if (light) then
			light.pos = ix.weather.viewOrigin + Vector(0, 0, 700)
			light.r, light.g, light.b = info.colour[1], info.colour[2], info.colour[3]
			light.brightness = info.brightness * strength
			light.size = info.size
			light.decay = info.size * 2.5
			light.dietime = CurTime() + ix.weather.look.lightning.length
		end
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
		column.flat = ground.HitNormal.z > 0.97
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

local function Pair(pair)
	return math.Rand(pair[1], pair[2])
end

-- Spawn budgets carried between frames, by kind.
local budgets = {}
local frameLeft = 0

-- How many particles of a kind to start this frame for a rate per second.
local function Budget(kind, rate, delta)
	local budget = math.min((budgets[kind] or 0) + rate * delta, 300)
	local count = math.min(math.floor(budget), frameLeft)

	budgets[kind] = budget - count
	frameLeft = frameLeft - count

	return count
end

local function GetEmitter(name, origin, b3D)
	local emitter = ix.weather[name]

	if (!emitter or !emitter:IsValid()) then
		emitter = ParticleEmitter(origin, b3D)
		ix.weather[name] = emitter
	end

	emitter:SetPos(origin)

	return emitter
end

-- A random point within radius (a number, or {inner, outer}) of centre, more of them close in.
local function Scatter(centre, radius)
	local distance

	if (istable(radius)) then
		distance = Lerp(math.Rand(0, 1) ^ 1.3, radius[1], radius[2])
	else
		distance = radius * math.Rand(0.03, 1) ^ 1.5
	end

	local direction = math.Rand(0, math.pi * 2)

	return centre.x + math.cos(direction) * distance, centre.y + math.sin(direction) * distance
end

-- The wind blows from a direction fixed for each spell of weather, and comes in gusts.
local function Wind()
	local yaw = (ix.weather.state.changedAt * 47) % 360
	local time = RealTime()
	local gust = 0.92 + 0.14 * math.sin(time * 0.37) + 0.07 * math.sin(time * 1.13 + 1.7)

	return Angle(0, yaw, 0):Forward(), ix.weather.GetValue("wind") * gust, gust
end

-- One falling streak or flake from an open column, stopping where it lands. Returns the particle.
local function Fall(emitter, material, x, y, originZ, speed, drift)
	local column = Column(x, y, originZ)

	if (!column or column.top <= column.bottom) then
		return
	end

	local low = math.max(column.bottom, originZ - 260)
	local z = math.Rand(math.min(low, column.top), column.top)

	-- the wind carries it sideways, so where it lands must be open too, and it stops at the higher ground
	local fall = (z - column.bottom) / speed
	local landing = Column(x + drift.x * fall, y + drift.y * fall, originZ)

	if (!landing) then
		return
	end

	local bottom = math.max(column.bottom, landing.bottom)

	if (z <= bottom) then
		return
	end

	local particle = emitter:Add(material, Vector(x, y, z))

	if (particle) then
		particle:SetVelocity(Vector(drift.x, drift.y, -speed))
		particle:SetGravity(vector_origin)
		particle:SetAirResistance(0)
		particle:SetDieTime((z - bottom) / speed)
	end

	return particle, column
end

local function Shade(particle, colour, light)
	particle:SetColor(colour[1] * light, colour[2] * light, colour[3] * light)
end

local ringAngle = Angle(-90, 0, 0)

local function SpawnRain(delta, amount, scale, origin, centre)
	local rain = look.rain
	local direction, wind, gust = Wind()
	local drift = direction * (wind * rain.drift)
	local emitter = GetEmitter("emitter", origin, false)
	local strength = amount * scale * gust

	for _ = 1, Budget("near", rain.near.rate * strength, delta) do
		local x, y = Scatter(centre, rain.near.radius)
		local particle, column = Fall(emitter, "particle/rain_streak", x, y, origin.z, Pair(rain.near.speed), drift)

		if (particle) then
			particle:SetStartSize(Pair(rain.near.width))
			particle:SetEndSize(particle:GetStartSize())
			particle:SetStartLength(Pair(rain.near.length))
			particle:SetEndLength(particle:GetStartLength())
			particle:SetStartAlpha(Pair(rain.near.alpha))
			particle:SetEndAlpha(particle:GetStartAlpha())
			Shade(particle, rain.colour, column.light)
		end
	end

	for _, name in ipairs({"mid", "far"}) do
		local layer = rain[name]

		for _ = 1, Budget(name, layer.rate * strength, delta) do
			local x, y = Scatter(origin, layer.radius)
			local particle, column = Fall(emitter, "particle/rain_streak", x, y, origin.z, Pair(layer.speed), drift)

			if (particle) then
				particle:SetStartSize(Pair(layer.width))
				particle:SetEndSize(particle:GetStartSize())
				particle:SetStartLength(Pair(layer.length))
				particle:SetEndLength(particle:GetStartLength())
				particle:SetStartAlpha(Pair(layer.alpha))
				particle:SetEndAlpha(particle:GetStartAlpha())
				Shade(particle, rain.colour, column.light)
			end
		end
	end

	for _ = 1, Budget("splash", rain.splash.rate * strength, delta) do
		local x, y = Scatter(centre, rain.splash.radius)
		local column = Column(x, y, origin.z)

		if (column and column.bottom > origin.z - 400) then
			local size = Pair(rain.splash.size)
			local particle = emitter:Add("particle/particle_glow_04", Vector(x, y, column.bottom + size * 0.6))

			if (particle) then
				particle:SetVelocity(Vector(math.Rand(-6, 6), math.Rand(-6, 6), math.Rand(14, 30)))
				particle:SetGravity(Vector(0, 0, -260))
				particle:SetDieTime(Pair(rain.splash.life))
				particle:SetStartSize(size * 0.5)
				particle:SetEndSize(size)
				particle:SetStartAlpha(Pair(rain.splash.alpha))
				particle:SetEndAlpha(0)
				particle:SetRoll(math.Rand(0, 360))
				Shade(particle, rain.colour, column.light * 1.2)
			end
		end
	end

	local ground = GetEmitter("groundEmitter", origin, true)

	for _ = 1, Budget("ring", rain.ring.rate * strength, delta) do
		local x, y = Scatter(centre, rain.ring.radius)
		local column = Column(x, y, origin.z)

		if (column and column.bottom > origin.z - 400 and column.flat) then
			local particle = ground:Add("particle/particle_ring_blur", Vector(x, y, column.bottom + 0.6))

			if (particle) then
				particle:SetAngles(ringAngle)
				particle:SetDieTime(Pair(rain.ring.life))
				particle:SetStartSize(rain.ring.size[1])
				particle:SetEndSize(math.Rand(rain.ring.size[2] * 0.6, rain.ring.size[2]))
				particle:SetStartAlpha(Pair(rain.ring.alpha))
				particle:SetEndAlpha(0)
				Shade(particle, rain.colour, column.light * 1.1)
			end
		end
	end

	if (amount >= rain.mist.from) then
		local heavy = (amount - rain.mist.from) / (1 - rain.mist.from)

		for _ = 1, Budget("mist", rain.mist.rate * heavy * scale, delta) do
			local x, y = Scatter(origin, rain.mist.radius)
			local column = Column(x, y, origin.z)

			if (column and column.bottom > origin.z - 400) then
				local size = Pair(rain.mist.size)
				local particle = emitter:Add("particle/particle_smokegrenade", Vector(x, y, column.bottom + size * 0.35))

				if (particle) then
					particle:SetVelocity(drift * 0.25 + Vector(math.Rand(-12, 12), math.Rand(-12, 12), 3))
					particle:SetDieTime(Pair(rain.mist.life))
					particle:SetStartSize(size * 0.7)
					particle:SetEndSize(size * 1.5)
					particle:SetStartAlpha(0)
					particle:SetEndAlpha(0)
					particle:SetRoll(math.Rand(0, 360))
					particle:SetRollDelta(math.Rand(-0.2, 0.2))

					-- fades in and out
					local alpha = Pair(rain.mist.alpha)
					local life = particle:GetDieTime()

					particle:SetNextThink(CurTime())
					particle:SetThinkFunction(function(this)
						local fraction = this:GetLifeTime() / life

						this:SetStartAlpha(alpha * math.sin(math.Clamp(fraction, 0, 1) * math.pi))
						this:SetEndAlpha(this:GetStartAlpha())
						this:SetNextThink(CurTime() + 0.05)
					end)

					Shade(particle, {190, 196, 204}, column.light)
				end
			end
		end
	end
end

local function SpawnSnow(delta, amount, scale, origin, centre)
	local snow = look.snow
	local direction, wind = Wind()
	local drift = direction * (wind * snow.drift)
	local emitter = GetEmitter("emitter", origin, false)

	for _ = 1, Budget("snow", snow.rate * amount * scale, delta) do
		local x, y = Scatter(centre, snow.radius)
		local particle, column = Fall(emitter, "particle/particle_glow_04", x, y, origin.z, Pair(snow.speed), drift)

		if (particle) then
			local velocity = particle:GetVelocity()

			velocity.x = velocity.x + math.Rand(-snow.sway, snow.sway)
			velocity.y = velocity.y + math.Rand(-snow.sway, snow.sway)
			particle:SetVelocity(velocity)
			particle:SetStartSize(Pair(snow.size))
			particle:SetEndSize(particle:GetStartSize())
			particle:SetStartAlpha(Pair(snow.alpha))
			particle:SetEndAlpha(particle:GetStartAlpha())
			particle:SetRoll(math.Rand(0, 360))
			particle:SetRollDelta(math.Rand(-2, 2))
			Shade(particle, {236, 240, 246}, column.light)
		end
	end
end

local function SpawnParticles(delta)
	local precipitation = ix.weather.GetValue("precipitation")
	local scale = ix.option.Get("weatherParticles", 1)
	local kind = ix.weather.GetPrecipitationKind(precipitation)

	if (!kind or scale <= 0) then
		budgets = {}
		return
	end

	frameLeft = look.maxPerFrame

	local origin = ix.weather.viewOrigin
	local forward = ix.weather.viewForward
	local flat = Vector(forward.x, forward.y, 0)

	flat:Normalize()

	if (kind == "snow") then
		SpawnSnow(delta, precipitation, scale, origin, origin + flat * (look.snow.radius * 0.3))
	else
		SpawnRain(delta, precipitation, scale, origin, origin + flat * (look.rain.near.radius * 0.35))
	end
end

function PLUGIN:Think()
	if (!Character()) then
		StopAll()
		return
	end

	-- real time, so the rain is as dense at any frame rate; a long hitch does not pour it all at once
	local delta = math.min(RealFrameTime(), 0.1)

	if (ix.weather.NeedsCloudTexture()) then
		ix.weather.BuildCloudTexture()
	end

	UpdateOpenness()
	ix.weather.smoothOpenness = math.Approach(ix.weather.smoothOpenness, ix.weather.openness, delta * 0.7)
	UpdateSounds(delta)
	SpawnParticles(delta)
end

function PLUGIN:CharacterLoaded()
	ix.weather.columns = {}
	ix.weather.columnCount = 0
end

-- How strong the lightning is right now, 0..1: two quick pulses and an afterglow.
local function Flash()
	local strike = ix.weather.flash

	if (!strike) then
		return 0
	end

	local age = RealTime() - strike.time
	local length = look.lightning.length

	if (age > length) then
		ix.weather.flash = nil
		return 0
	end

	local pulse = age < 0.07 and 1 or (age < 0.13 and 0.25 or (age < 0.2 and 0.85 or 0.5))

	return strike.strength * pulse * math.max(0, 1 - age / length)
end

-- How thick the weather is between the eye and the distance, 0..1: fog, rain and low cloud.
local function Murk()
	return math.Clamp(math.max(ix.weather.GetValue("fog"), ix.weather.GetValue("precipitation") * look.fog.rain,
		ix.weather.GetValue("cloud") * look.fog.cloud), 0, 1)
end

-- The colour of the cloud and of what the distance fades into, darker the heavier the cloud. `lift` brightens it.
local function SkyColour(lift)
	local cloud = ix.weather.GetValue("cloud")
	local thin, heavy = look.sky.thin, look.sky.heavy

	lift = lift or 1

	return math.min(Lerp(cloud, thin[1], heavy[1]) * lift, 255), math.min(Lerp(cloud, thin[2], heavy[2]) * lift, 255),
		math.min(Lerp(cloud, thin[3], heavy[3]) * lift, 255)
end

local function ApplyFog(scale)
	local murk = Murk()

	if (murk < 0.02) then
		return
	end

	local fogEnd = Lerp((1 - murk) ^ 2, look.fog.near, look.fog.far)
	local r, g, b = SkyColour(look.sky.horizon)

	-- the map's own fog, if closer, stays as close
	if (render.GetFogMode() != MATERIAL_FOG_NONE) then
		local _, mapEnd = render.GetFogDistances()

		if (mapEnd and mapEnd > 0) then
			fogEnd = math.min(fogEnd, mapEnd / scale)
		end
	end

	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(-fogEnd * 0.12 * murk * scale)
	render.FogEnd(fogEnd * scale)
	render.FogMaxDensity(math.min(1, 0.5 + 0.5 * murk))
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

-- The cloud texture Garry's Mod ships for painted skies, drawn as moving layers.
-- That texture is faint wisps on black, too soft to read as cloud. It is drawn several times over into a
-- texture of our own and a flat grey taken off, which leaves distinct masses with gaps between them; a layer
-- of that is then added as light onto the sky's colour.
local cloudSource = CreateMaterial("ixWeatherCloudSource", "UnlitGeneric", {
	["$basetexture"] = "skybox/clouds",
	["$additive"] = 1,
	["$vertexcolor"] = 1
})

local cloudTarget = GetRenderTargetEx("ixWeatherCloudTarget", 1024, 1024, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_NONE,
	0, 0, IMAGE_FORMAT_RGBA8888)

local cloudMaterial = CreateMaterial("ixWeatherCloud6", "UnlitGeneric", {
	["$basetexture"] = cloudTarget:GetName(),
	["$vertexcolor"] = 1,
	["$additive"] = 1,
	["$nocull"] = 1,
	["$ignorez"] = 1
})

local bCloudsBuilt = false
local nextCloudBuild = 0

local function BuildCloudTexture()
	local sky = look.sky

	bCloudsBuilt = true
	-- built again now and then: a lost device (alt-tab on some systems) empties render targets without notice
	nextCloudBuild = RealTime() + 60

	render.PushRenderTarget(cloudTarget)
	render.OverrideAlphaWriteEnable(true, true)
	render.Clear(0, 0, 0, 255)

	cam.Start2D()
		surface.SetMaterial(cloudSource)
		surface.SetDrawColor(255, 255, 255, 255)

		for _ = 1, sky.textureGain do
			surface.DrawTexturedRect(0, 0, 1024, 1024)
		end

		local cut = sky.textureCut * 255

		-- colour only: the alpha stays opaque, since the layer's material blends by it
		render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_REVERSE_SUBTRACT, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
			draw.NoTexture()
			surface.SetDrawColor(cut, cut, cut, 255)
			surface.DrawRect(0, 0, 1024, 1024)
		-- and the alpha set opaque whatever the passes above left in it
		render.OverrideBlend(true, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawRect(0, 0, 1024, 1024)
		render.OverrideBlend(false)
	cam.End2D()

	render.OverrideAlphaWriteEnable(false)
	render.PopRenderTarget()
end

ix.weather.BuildCloudTexture = BuildCloudTexture

-- Whether the cloud texture needs building; Think does it, outside the frame's drawing (built inside a render
-- hook it comes out empty).
function ix.weather.NeedsCloudTexture()
	return !bCloudsBuilt or RealTime() >= nextCloudBuild
end

-- A changed resolution or a lost device empties render targets.
function PLUGIN:OnScreenSizeChanged()
	bCloudsBuilt = false
end

local skyColour = Color(0, 0, 0, 0)

-- One flat layer of cloud over the eye, fading out toward the horizon. A render target's texture does not
-- repeat, so the layer is laid as tiles of one whole texture each, and drifting moves the tiles.
local function DrawCloudLayer(layer, r, g, b, alpha, time)
	local sky = look.sky
	local reach, height, size = sky.reach, sky.height, layer.scale
	local direction = Wind()
	local shiftX = (direction.x * layer.speed * time + layer.offset[1] * size) % size
	local shiftY = (direction.y * layer.speed * time + layer.offset[2] * size) % size
	local count = math.ceil(reach / size) + 1

	local function Vertex(x, y, u, v)
		local fade = math.Clamp(1 - math.sqrt(x * x + y * y) / reach, 0, 1) ^ 0.8

		-- added light, so fading is done on the colour
		mesh.Position(Vector(x, y, height))
		mesh.TexCoord(0, u, v)
		mesh.Color(r * fade, g * fade, b * fade, alpha)
		mesh.AdvanceVertex()
	end

	render.SetMaterial(cloudMaterial)
	mesh.Begin(MATERIAL_QUADS, count * count * 4)

	for i = -count, count - 1 do
		for j = -count, count - 1 do
			local x, y = i * size + shiftX, j * size + shiftY

			Vertex(x, y, 0, 0)
			Vertex(x + size, y, 1, 0)
			Vertex(x + size, y + size, 1, 1)
			Vertex(x, y + size, 0, 1)
		end
	end

	mesh.End()
end

-- Overcast: the sky is filled with the colour of the weather, then cloud layers drift across it.
function PLUGIN:PostDraw2DSkyBox()
	local cloud = ix.weather.GetValue("cloud")
	local cover = math.Clamp(math.max(cloud * 1.15, Murk()), 0, 1)

	if (cover < 0.02) then
		return
	end

	local flash = Flash() * look.lightning.sky
	local r, g, b = SkyColour(look.sky.horizon * (1 + flash * 0.5))

	skyColour.r, skyColour.g, skyColour.b = r, g, b
	skyColour.a = math.min(cover, 1) * 255

	render.OverrideDepthEnable(true, false)
	cam.Start3D(vector_origin, EyeAngles(), nil, nil, nil, nil, nil, 8, look.sky.reach * 2)
		render.SetColorMaterial()
		render.CullMode(MATERIAL_CULLMODE_CW)
		render.DrawSphere(vector_origin, 64, 16, 12, skyColour)
		render.CullMode(MATERIAL_CULLMODE_CCW)

		local time = CurTime()

		for _, layer in ipairs(look.sky.layers) do
			-- a layer brighter than the texture allows is drawn again for the rest
			local light = layer.light * (1 + flash) * cover

			while (light > 0.01) do
				local pass = math.min(light, 1)

				DrawCloudLayer(layer, 235 * pass, 240 * pass, 250 * pass, 255, time)
				light = light - pass
			end
		end
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

-- Under cloud the light goes flat, dim and cold: less so under cover, where it only comes in through openings.
-- A lightning strike lifts it for a moment. Applied on top of whatever else draws colour correction.
function PLUGIN:RenderScreenspaceEffects()
	local cloud = ix.weather.GetValue("cloud")
	local flash = Flash()

	if (cloud < 0.02 and flash <= 0) then
		return
	end

	local grade = look.grade
	local amount = cloud * Lerp(ix.weather.smoothOpenness, grade.indoors, 1)

	colourModify["$pp_colour_brightness"] = grade.brightness * amount + look.lightning.brightness * flash
	colourModify["$pp_colour_contrast"] = Lerp(amount, 1, grade.contrast)
	colourModify["$pp_colour_colour"] = Lerp(amount, 1, grade.colour)
	colourModify["$pp_colour_addr"] = grade.tint[1] * amount
	colourModify["$pp_colour_addg"] = grade.tint[2] * amount
	colourModify["$pp_colour_addb"] = grade.tint[3] * amount

	DrawColorModify(colourModify)
end
