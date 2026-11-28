local PLUGIN = PLUGIN

PLUGIN.name = "Weather"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "A server-wide weather cycle, the outdoor temperature, and the rain, snow, wind, fog and thunder players see and hear."

ix.weather = ix.weather or {}

-- Precipitation falls as snow at or below this outdoor temperature (°C).
ix.weather.SNOW_TEMPERATURE = 1
-- Fraction of the way a covered spot's temperature is pulled from the outdoor one toward weatherIndoorTemperature.
ix.weather.INDOOR_DAMPING = 0.7
-- Fraction of the wind that still reaches a player under cover.
ix.weather.INDOOR_WIND = 0.15
-- Seconds the server keeps a player's GetExposure result.
ix.weather.EXPOSURE_CACHE = 1

ix.util.Include("sh_types.lua")

-- Thunder sounds, by index; the server picks one per strike so every client plays the same.
ix.weather.thunderSounds = {
	"ambient/weather/thunder1.wav",
	"ambient/weather/thunder2.wav",
	"ambient/weather/thunder3.wav",
	"ambient/weather/thunder4.wav",
	"ambient/weather/thunder5.wav",
	"ambient/weather/thunder6.wav"
}

ix.config.Add("weatherEnabled", true, "Whether the weather changes. When off the sky stays clear; the temperature still follows the season and the hour.", function(oldValue, newValue)
	if (SERVER) then
		PLUGIN:OnEnabledChanged(newValue)
	end
end, {category = "Weather"})

ix.config.Add("weatherMinDuration", 10, "Shortest time a weather type lasts, in minutes.", nil, {
	data = {min = 1, max = 240},
	category = "Weather"
})

ix.config.Add("weatherMaxDuration", 30, "Longest time a weather type lasts, in minutes.", nil, {
	data = {min = 1, max = 240},
	category = "Weather"
})

ix.config.Add("weatherTransitionTime", 90, "Seconds the sky takes to change from one weather type to the next.", nil, {
	data = {min = 0, max = 600},
	category = "Weather"
})

ix.config.Add("weatherMeanTemperature", 12, "Annual mean outdoor temperature, in °C.", nil, {
	data = {min = -30, max = 40},
	category = "Weather"
})

ix.config.Add("weatherSeasonSwing", 6, "How far the season moves the temperature above or below the mean (warmest in July), in °C. 0 disables seasons.", nil, {
	data = {min = 0, max = 30},
	category = "Weather"
})

ix.config.Add("weatherDaySwing", 5, "How far the hour moves the temperature above or below the day's mean (coldest at 05:00, warmest at 15:00), in °C.", nil, {
	data = {min = 0, max = 20},
	category = "Weather"
})

ix.config.Add("weatherIndoorTemperature", 15, "Temperature that being under cover pulls toward, in °C.", nil, {
	data = {min = -10, max = 30},
	category = "Weather"
})

-- The state is replaced wholesale (never edited in place) so a reference held by a caller stays as it was.
ix.weather.state = ix.weather.state or {
	type = "clear",
	previous = "clear",
	changedAt = 0,
	transition = 0,
	endsAt = 0
}

--- The ID of the current weather type: during a transition, the one being moved to.
function ix.weather.Get()
	return ix.weather.state.type
end

--- The current state: type, previous, changedAt (CurTime), transition (seconds) and endsAt (CurTime).
function ix.weather.GetState()
	return ix.weather.state
end

--- How far the transition from the previous type to the current one has gone at `time` (default now), 0..1,
-- eased so the change starts and ends gently.
function ix.weather.GetBlend(time, state)
	state = state or ix.weather.state
	time = time or CurTime()

	if (state.transition <= 0) then
		return 1
	end

	local fraction = math.Clamp((time - state.changedAt) / state.transition, 0, 1)

	return fraction * fraction * (3 - 2 * fraction)
end

--- A weather value ("precipitation", "wind", "cloud", "fog" or "temperature", the last being the type's °C
-- offset) blended from the previous type to the current one. `time` defaults to now.
function ix.weather.GetValue(key, time, state)
	state = state or ix.weather.state

	local types = ix.weather.types
	local current = types[state.type] or types.clear
	local previous = types[state.previous] or current
	local to, from = current[key], previous[key]

	if (!isnumber(to)) then
		return 0
	end

	from = isnumber(from) and from or to

	return Lerp(ix.weather.GetBlend(time, state), from, to)
end

-- The day/night offset for a fractional hour, -1 at 05:00 and +1 at 15:00, cosine on both sides (a 10 hour
-- warming and a 14 hour cooling).
local function DayCurve(hour)
	hour = hour % 24

	if (hour >= 5 and hour < 15) then
		return -math.cos(math.pi * (hour - 5) / 10)
	end

	return math.cos(math.pi * ((hour - 15) % 24) / 14)
end

--- The outdoor temperature (°C) for a fractional hour (0..24), a fractional month (1..13, mid-July warmest)
-- and a weather offset. Pure: the same arguments give the same answer on either realm.
function ix.weather.ComputeTemperature(hour, month, weatherOffset)
	local mean = ix.config.Get("weatherMeanTemperature", 12)
	local season = ix.config.Get("weatherSeasonSwing", 6) * math.cos(2 * math.pi * (month - 7.5) / 12)
	local day = ix.config.Get("weatherDaySwing", 5) * DayCurve(hour)

	return mean + season + day + (weatherOffset or 0)
end

--- The fractional hour and month of the in-game date.
function ix.weather.GetDateParts()
	local date = ix.date.Get()
	local hour = date:gethours() + date:getminutes() / 60
	local month = date:getmonth() + (date:getday() - 1) / 31

	return hour, month
end

--- The outdoor air temperature (°C) now: mean, season, hour and the blended weather offset.
function ix.weather.GetTemperature()
	local hour, month = ix.weather.GetDateParts()

	return ix.weather.ComputeTemperature(hour, month, ix.weather.GetValue("temperature"))
end

--- "rain", "snow" or nil (nothing falling). Both arguments default to the current values.
function ix.weather.GetPrecipitationKind(precipitation, temperature)
	precipitation = precipitation or ix.weather.GetValue("precipitation")

	if (precipitation < 0.01) then
		return
	end

	temperature = temperature or ix.weather.GetTemperature()

	return temperature <= ix.weather.SNOW_TEMPERATURE and "snow" or "rain"
end

local function SkyTraceFilter(entity)
	return !(entity:IsPlayer() or entity:IsNPC() or entity:IsRagdoll() or entity:IsWeapon())
end

ix.weather.SkyTraceFilter = SkyTraceFilter

local skyTrace = {mask = MASK_SOLID, filter = SkyTraceFilter}
local skyOffset = Vector(0, 0, 32768)

--- Whether there is open sky straight above pos.
function ix.weather.IsOutdoors(pos)
	skyTrace.start = pos
	skyTrace.endpos = pos + skyOffset

	local trace = util.TraceLine(skyTrace)

	if (trace.StartSolid) then
		return false
	end

	return trace.HitSky or !trace.Hit
end

--- The temperature (°C) at pos: the outdoor one under open sky, otherwise pulled most of the way toward
-- weatherIndoorTemperature. `bOutdoors` skips the trace when the caller already knows.
function ix.weather.GetTemperatureAt(pos, bOutdoors)
	local outdoor = ix.weather.GetTemperature()

	if (bOutdoors == nil) then
		bOutdoors = ix.weather.IsOutdoors(pos)
	end

	if (bOutdoors) then
		return outdoor
	end

	local indoor = ix.config.Get("weatherIndoorTemperature", 15)

	return Lerp(ix.weather.INDOOR_DAMPING, outdoor, indoor)
end

--- What reaches pos: {outdoors, precipitation 0..1, wind 0..1}. Uncached.
function ix.weather.GetExposureAt(pos)
	local bOutdoors = ix.weather.IsOutdoors(pos)
	local wind = ix.weather.GetValue("wind")

	return {
		outdoors = bOutdoors,
		precipitation = bOutdoors and ix.weather.GetValue("precipitation") or 0,
		wind = bOutdoors and wind or wind * ix.weather.INDOOR_WIND
	}
end

--- What reaches the player: {outdoors, precipitation, wind}, from their eyes. The server keeps the answer for
-- EXPOSURE_CACHE seconds; clear `client.ixWeatherExposure` to force a new one.
function ix.weather.GetExposure(client)
	local cached = client.ixWeatherExposure
	local now = CurTime()

	if (SERVER and cached and cached.state == ix.weather.state and now - cached.time < ix.weather.EXPOSURE_CACHE) then
		return cached.result
	end

	local result = ix.weather.GetExposureAt(client:EyePos())
	client.ixWeatherExposure = {time = now, state = ix.weather.state, result = result}

	return result
end

ix.util.Include("sv_plugin.lua")
ix.util.Include("cl_plugin.lua")

ix.command.Add("WeatherSet", {
	description = "@cmdWeatherSet",
	adminOnly = true,
	arguments = {
		ix.type.string,
		bit.bor(ix.type.number, ix.type.optional)
	},
	OnRun = function(self, client, id, minutes)
		id = string.lower(id)

		if (!ix.weather.types[id]) then
			local valid = table.GetKeys(ix.weather.types)
			table.sort(valid)

			return "@weatherUnknown", table.concat(valid, ", ")
		end

		if (!ix.config.Get("weatherEnabled", true)) then
			return "@weatherDisabled"
		end

		local duration = minutes and math.Clamp(minutes, 1, 1440) * 60 or nil

		ix.weather.Set(id, duration)

		for _, v in ipairs(player.GetAll()) do
			if (self:OnCheckAccess(v)) then
				v:NotifyLocalized("weatherSetBy", client:GetName(), L(ix.weather.types[id].name, v))
			end
		end
	end
})
