-- Weather (weather): the type table, blending through a transition, the outdoor temperature from hour, month,
-- weather and config, snow against rain, the picker and its timer step, exposure under a roof and under open
-- sky, /WeatherSet, and saving and loading the state. Every check puts the weather state and config back.

local Lib = GWH.Lib
local Plugin, WithConfig, Scoped, Capture, Replace = Lib.Plugin, Lib.WithConfig, Lib.Scoped, Lib.Capture, Lib.Replace

local S = Lib.NewS()

local KEYS = {"precipitation", "wind", "cloud", "fog", "temperature"}

-- Puts the weather straight into type id, with no transition, lasting ten minutes from now.
local function Force(id, now)
	now = now or CurTime()
	ix.weather.state = {type = id, previous = id, changedAt = now, transition = 0, endsAt = now + 600}
end

local function Near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 1e-6)
end

-- Puts the weather state, the thunder schedule and the saved data back when the check ends.
local function KeepWeather(defer, plugin)
	local state, nextThunder, lastStrike = ix.weather.state, ix.weather.nextThunder, ix.weather.lastStrike

	defer(function()
		ix.weather.state = state
		ix.weather.nextThunder = nextThunder
		ix.weather.lastStrike = lastStrike
		ix.weather.Send()

		if (plugin) then plugin:SaveData() end
	end)
end

GWH.Check("weather: every type has its fields and only plausible follow-ons", function(fail)
	if (!Plugin("weather", fail)) then return end

	for _, id in ipairs({"clear", "cloudy", "fog", "drizzle", "rain", "storm"}) do
		if (!ix.weather.types[id]) then fail("type " .. id .. " is missing") end
	end

	for id, definition in pairs(ix.weather.types) do
		if (!isstring(definition.name) or !ix.lang.stored.english[definition.name]) then
			fail(id .. " has no language phrase for its name")
		end

		for _, key in ipairs({"precipitation", "wind", "cloud", "fog"}) do
			local value = definition[key]

			if (!isnumber(value) or value < 0 or value > 1) then
				fail(id .. "." .. key .. " is " .. tostring(value) .. ", expected 0..1")
			end
		end

		if (!isnumber(definition.temperature)) then fail(id .. ".temperature is not a number") end
		if (!isbool(definition.thunder)) then fail(id .. ".thunder is not a bool") end

		if (!istable(definition.next) or table.IsEmpty(definition.next)) then
			fail(id .. " has no follow-on types")
		else
			for nextID, weight in pairs(definition.next) do
				if (!ix.weather.types[nextID]) then fail(id .. " may be followed by unknown type " .. nextID) end
				if (!isnumber(weight) or weight <= 0) then fail(id .. " -> " .. nextID .. " has weight " .. tostring(weight)) end
			end
		end
	end

	local clear, storm = ix.weather.types.clear.next, ix.weather.types.storm.next

	for _, id in ipairs({"drizzle", "rain", "storm"}) do
		if (clear[id]) then fail("clear may be followed directly by " .. id) end
	end

	if (storm.clear or storm.cloudy or storm.fog) then fail("storm may clear up without rain in between") end
	if (!ix.weather.types.storm.thunder or ix.weather.types.rain.thunder) then fail("only storm should thunder") end
end)

GWH.Check("weather: values blend from the previous type through the transition", function(fail)
	local plugin = Plugin("weather", fail)
	if (!plugin) then return end

	return Scoped(function(defer)
		KeepWeather(defer, plugin)

		local now = CurTime()
		local fired = {}

		hook.Add("WeatherChanged", "gwhWeather", function(newType, oldType)
			fired[#fired + 1] = oldType .. ">" .. newType
		end)
		defer(function() hook.Remove("WeatherChanged", "gwhWeather") end)

		Force("clear", now - 1000)
		fired = {}
		ix.weather.Set("rain", 600, 10, now)

		local state = ix.weather.GetState()

		if (ix.weather.Get() != "rain") then fail("Get() is " .. tostring(ix.weather.Get()) .. " during the transition") end
		if (state.previous != "clear" or state.changedAt != now or state.transition != 10 or state.endsAt != now + 600) then
			fail("state after Set is " .. util.TableToJSON(state))
		end

		if (fired[1] != "clear>rain" or #fired != 1) then fail("WeatherChanged fired " .. table.concat(fired, ",")) end

		local clear, rain = ix.weather.types.clear, ix.weather.types.rain

		for _, key in ipairs(KEYS) do
			local from, to = clear[key], rain[key]
			local atStart, halfway, atEnd = ix.weather.GetValue(key, now), ix.weather.GetValue(key, now + 5),
				ix.weather.GetValue(key, now + 10)

			if (!Near(atStart, from)) then fail(key .. " at the start is " .. atStart .. ", expected " .. from) end
			if (!Near(halfway, (from + to) / 2)) then fail(key .. " halfway is " .. halfway .. ", expected " .. (from + to) / 2) end
			if (!Near(atEnd, to)) then fail(key .. " at the end is " .. atEnd .. ", expected " .. to) end

			local quarter = ix.weather.GetValue(key, now + 2.5)

			if (from != to and !(math.min(from, to) < quarter and quarter < math.max(from, to))) then
				fail(key .. " a quarter of the way is " .. quarter .. ", outside " .. from .. ".." .. to)
			end
		end

		-- setting the current type again only moves its end
		ix.weather.Set("rain", 60, 99, now)

		if (#fired != 1) then fail("setting the current type again fired WeatherChanged") end
		if (ix.weather.GetState().changedAt != now or ix.weather.GetState().endsAt != now + 60) then
			fail("setting the current type again changed the transition or did not move the end")
		end

		-- a zero transition switches at once
		ix.weather.Set("storm", 600, 0, now)

		if (!Near(ix.weather.GetValue("precipitation", now), 1)) then fail("a zero transition did not switch at once") end
	end)
end)

GWH.Check("weather: temperature follows hour, month, weather and config", function(fail)
	local plugin = Plugin("weather", fail)
	if (!plugin) then return end

	local detail = {}

	Scoped(function(defer)
		KeepWeather(defer, plugin)

		WithConfig({weatherMeanTemperature = 10, weatherSeasonSwing = 6, weatherDaySwing = 5, weatherIndoorTemperature = 15}, function()
			local T = ix.weather.ComputeTemperature

			local cases = {
				{5, 7.5, 0, 11, "05:00 mid-July"},
				{15, 7.5, 0, 21, "15:00 mid-July"},
				{15, 1.5, 0, 9, "15:00 mid-January"},
				{5, 1.5, 0, -1, "05:00 mid-January"},
				{10, 4.5, 0, 10, "10:00 mid-April"},
				{15, 7.5, -5, 16, "15:00 mid-July in a storm"}
			}

			for _, v in ipairs(cases) do
				local got = T(v[1], v[2], v[3])
				detail[v[5]] = got

				if (!Near(got, v[4], 1e-4)) then fail(v[5] .. " is " .. got .. " °C, expected " .. v[4]) end
			end

			-- smooth: no jump at midnight, warming before 15:00 and cooling after
			if (!Near(T(23.999, 7.5, 0), T(0, 7.5, 0), 1e-2)) then fail("the temperature jumps at midnight") end
			if (!(T(9, 7.5, 0) < T(12, 7.5, 0) and T(18, 7.5, 0) < T(16, 7.5, 0) and T(2, 7.5, 0) > T(5, 7.5, 0))) then
				fail("the day curve is not coldest at 05:00 and warmest at 15:00")
			end

			ix.config.Set("weatherSeasonSwing", 0)

			if (!Near(T(12, 1, 0), T(12, 7, 0))) then fail("a season swing of 0 still changes with the month") end

			ix.config.Set("weatherMeanTemperature", 20)

			if (!Near(T(10, 4.5, 0), 20, 1e-4)) then fail("the mean temperature config is not followed") end

			-- the live temperature includes the blended weather offset
			local hour, month = ix.weather.GetDateParts()

			Force("clear")
			local clear = ix.weather.GetTemperature()
			Force("storm")
			local storm = ix.weather.GetTemperature()

			detail.clear, detail.storm = clear, storm

			if (!Near(storm, T(hour, month, ix.weather.types.storm.temperature), 1e-3)) then
				fail("GetTemperature in a storm is " .. storm .. ", expected " .. T(hour, month, ix.weather.types.storm.temperature))
			end

			if (!Near(clear - storm, ix.weather.types.clear.temperature - ix.weather.types.storm.temperature, 1e-3)) then
				fail("clear is " .. clear .. " and storm " .. storm .. "; the weather offset is not applied")
			end

			-- under cover the temperature is pulled most of the way to the indoor one
			local indoor = ix.weather.GetTemperatureAt(vector_origin, false)
			local expected = Lerp(ix.weather.INDOOR_DAMPING, storm, 15)

			if (!Near(indoor, expected, 1e-3)) then fail("under cover it is " .. indoor .. ", expected " .. expected) end
			if (!Near(ix.weather.GetTemperatureAt(vector_origin, true), storm, 1e-3)) then fail("in the open it is not the outdoor temperature") end
		end)
	end)

	return detail
end)

GWH.Check("weather: precipitation is snow at or below 1 °C and rain above", function(fail)
	local plugin = Plugin("weather", fail)
	if (!plugin) then return end

	local kind = ix.weather.GetPrecipitationKind

	if (kind(0.5, 1) != "snow") then fail("1 °C is " .. tostring(kind(0.5, 1))) end
	if (kind(0.5, -8) != "snow") then fail("-8 °C is " .. tostring(kind(0.5, -8))) end
	if (kind(0.5, 1.5) != "rain") then fail("1.5 °C is " .. tostring(kind(0.5, 1.5))) end
	if (kind(0, -8) != nil) then fail("nothing falling is " .. tostring(kind(0, -8))) end

	Scoped(function(defer)
		KeepWeather(defer, plugin)

		WithConfig({weatherMeanTemperature = -15, weatherSeasonSwing = 0, weatherDaySwing = 0}, function()
			Force("storm")
			if (ix.weather.GetPrecipitationKind() != "snow") then fail("a storm at -20 °C does not snow") end

			Force("clear")
			if (ix.weather.GetPrecipitationKind() != nil) then fail("clear weather has precipitation") end

			ix.config.Set("weatherMeanTemperature", 20)
			Force("rain")
			if (ix.weather.GetPrecipitationKind() != "rain") then fail("rain at 17 °C is not rain") end
		end)
	end)
end)

GWH.Check("weather: the picker follows allowed transitions and weatherEnabled", function(fail)
	local plugin = Plugin("weather", fail)
	if (!plugin) then return end

	Scoped(function(defer)
		KeepWeather(defer, plugin)

		WithConfig({weatherEnabled = true, weatherMinDuration = 10, weatherMaxDuration = 30}, function()
			for from, definition in pairs(ix.weather.types) do
				local seen = {}

				for roll = 0, 0.999, 0.01 do
					local picked = ix.weather.PickNext(from, function() return roll end)

					if (!definition.next[picked]) then fail(from .. " picked " .. tostring(picked) .. " at roll " .. roll) end
					seen[picked] = true
				end

				for id in pairs(definition.next) do
					if (!seen[id]) then fail(from .. " never picks " .. id) end
				end
			end

			for _ = 1, 200 do
				if (ix.weather.PickNext("clear") == "storm") then fail("clear went straight to storm") break end
			end

			local low, high = ix.weather.RandomDuration(function() return 0 end), ix.weather.RandomDuration(function() return 1 end)

			if (low != 600 or high != 1800) then fail("durations run " .. low .. ".." .. high .. " s, expected 600..1800") end

			-- the timer step ends a spell that has run out, and not one that has not; a roll of 0 picks the
			-- first follow-on in name order (cloudy after rain) and the shortest duration
			local now = CurTime()
			local random = math.random

			Replace(defer, math, "random", function(...)
				if (select("#", ...) > 0) then return random(...) end
				return 0
			end)

			Force("rain", now - 200)
			ix.weather.state.endsAt = now - 100
			ix.weather.Tick(now - 150)
			if (ix.weather.Get() != "rain" or ix.weather.GetState().changedAt != now - 200) then fail("Tick ended a spell early") end

			ix.weather.Tick(now)
			local after = ix.weather.GetState()

			if (after.type != "cloudy" or after.previous != "rain" or after.changedAt != now or after.endsAt != now + 600) then
				fail("Tick after rain ran out gave " .. util.TableToJSON(after) .. ", expected cloudy after rain for 600 s")
			end

			-- thunder: the server strikes during a storm, and not during rain
			ix.weather.lastStrike = nil
			Force("rain", now)
			ix.weather.nextThunder = 0
			ix.weather.Tick(now)
			if (ix.weather.lastStrike) then fail("thunder struck during rain") end

			Force("storm", now)
			ix.weather.nextThunder = 0
			ix.weather.Tick(now)

			local strike = ix.weather.lastStrike

			if (!strike) then
				fail("no thunder during a storm")
			elseif (!ix.weather.thunderSounds[strike.sound] or strike.distance < 0 or strike.distance > 1) then
				fail("bad strike " .. util.TableToJSON(strike))
			elseif (ix.weather.nextThunder <= now) then
				fail("the next strike was not scheduled")
			end

			-- disabled: the sky clears, nothing cycles, and the picker only gives clear
			ix.config.Set("weatherEnabled", false)

			if (ix.weather.Get() != "clear") then fail("turning weatherEnabled off left " .. ix.weather.Get()) end
			if (ix.weather.PickNext("cloudy") != "clear") then fail("the picker cycles while disabled") end

			local held = ix.weather.GetState()
			ix.weather.Tick(held.endsAt + 10)

			if (ix.weather.Get() != "clear" or ix.weather.GetState() != held) then fail("Tick changed the weather while disabled") end

			Force("storm")
			ix.weather.Tick()
			if (ix.weather.Get() != "clear") then fail("Tick did not clear the sky while disabled") end
		end)
	end)
end)

-- A point under open sky and one under a roof near the bot, found by tracing, at standing eye height.
local function FindSpots(origin)
	local open, covered

	for radius = 0, 4000, 160 do
		for angle = 0, 359, 30 do
			local point = origin + Angle(0, angle, 0):Forward() * radius

			-- stand on whatever is below, if anything is within reach
			local ground = util.TraceLine({start = point + Vector(0, 0, 32), endpos = point - Vector(0, 0, 512), mask = MASK_PLAYERSOLID})

			if (!ground.StartSolid and ground.Hit) then
				local eye = ground.HitPos + Vector(0, 0, 64)

				if (bit.band(util.PointContents(eye), CONTENTS_SOLID) == 0) then
					if (ix.weather.IsOutdoors(eye)) then
						open = open or eye
					else
						covered = covered or eye
					end
				end
			end

			if (open and covered) then return open, covered end
		end
	end

	return open, covered
end

GWH.Check("weather: exposure is dry under a roof and wet under open sky", function(fail)
	local plugin = Plugin("weather", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local detail = {}

	Scoped(function(defer)
		KeepWeather(defer, plugin)

		local position = bot:GetPos()
		defer(function()
			bot:SetPos(position)
			bot.ixWeatherExposure = nil
		end)

		local open, covered = FindSpots(position)
		detail.open, detail.covered = tostring(open), tostring(covered)

		if (!open or !covered) then return fail("could not find both an open and a covered spot on " .. game.GetMap()) end

		Force("rain")

		local offset = bot:EyePos() - bot:GetPos()

		bot:SetPos(open - offset)
		bot.ixWeatherExposure = nil

		local outside = ix.weather.GetExposure(bot)

		if (!outside.outdoors) then fail("the open spot " .. tostring(open) .. " is not outdoors") end
		if (!Near(outside.precipitation, ix.weather.types.rain.precipitation)) then fail("rain in the open is " .. outside.precipitation) end
		if (!Near(outside.wind, ix.weather.types.rain.wind)) then fail("wind in the open is " .. outside.wind) end

		-- cached for a moment
		if (ix.weather.GetExposure(bot) != outside) then fail("the exposure was not cached") end

		bot:SetPos(covered - offset)
		bot.ixWeatherExposure = nil

		local inside = ix.weather.GetExposure(bot)

		if (inside.outdoors) then fail("the covered spot " .. tostring(covered) .. " is outdoors") end
		if (inside.precipitation != 0) then fail("rain under a roof is " .. inside.precipitation) end
		if (!(inside.wind > 0 and inside.wind < outside.wind * 0.5)) then fail("wind under a roof is " .. inside.wind) end

		-- a weather change does not wait for the cache
		bot:SetPos(open - offset)
		bot.ixWeatherExposure = nil
		ix.weather.GetExposure(bot)
		ix.weather.Set("clear", 600, 0)

		if (ix.weather.GetExposure(bot).precipitation != 0) then fail("the cached exposure outlived a weather change") end

		detail.inside, detail.outside = util.TableToJSON(inside), util.TableToJSON(outside)
	end)

	return detail
end)

GWH.Check("weather: /WeatherSet needs an admin and a real type", function(fail)
	local plugin = Plugin("weather", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	Scoped(function(defer)
		KeepWeather(defer, plugin)

		local group = bot:GetUserGroup()
		defer(function() bot:SetUserGroup(group) end)

		WithConfig({weatherEnabled = true}, function()
			Force("clear")

			bot:SetUserGroup("user")
			S.Command(bot, "/WeatherSet storm")
			if (ix.weather.Get() != "clear") then fail("a user set the weather") end

			bot:SetUserGroup("superadmin")

			local seen = Capture(bot, function() S.Command(bot, "/WeatherSet hail") end)

			if (ix.weather.Get() != "clear") then fail("an unknown type changed the weather") end
			if (!string.find(seen.notices, "weatherUnknown", 1, true)) then fail("an unknown type was not refused, notices: " .. seen.notices) end

			local now = CurTime()

			S.Command(bot, "/WeatherSet Storm 5")

			if (ix.weather.Get() != "storm") then
				fail("an admin could not set a storm")
			elseif (!Near(ix.weather.GetState().endsAt, now + 300, 0.01)) then
				fail("a 5 minute storm ends after " .. (ix.weather.GetState().endsAt - now) .. " s")
			end

			ix.config.Set("weatherEnabled", false)
			seen = Capture(bot, function() S.Command(bot, "/WeatherSet rain") end)

			if (ix.weather.Get() != "clear") then fail("/WeatherSet worked while weatherEnabled is off") end
			if (!string.find(seen.notices, "weatherDisabled", 1, true)) then fail("no weatherDisabled notice, notices: " .. seen.notices) end
		end)
	end)
end)

GWH.Check("weather: the state survives saving and loading", function(fail)
	local plugin = Plugin("weather", fail)
	if (!plugin) then return end

	Scoped(function(defer)
		KeepWeather(defer, plugin)

		local now = CurTime()

		Force("drizzle", now - 1000)
		ix.weather.Set("rain", 500, 80, now - 30)

		local before = ix.weather.GetState()

		plugin:SaveData()
		ix.weather.Set("fog", 900, 0, now)
		plugin:LoadData()

		local after = ix.weather.GetState()

		for _, key in ipairs({"type", "previous", "transition"}) do
			if (after[key] != before[key]) then fail(key .. " loaded as " .. tostring(after[key]) .. ", saved " .. tostring(before[key])) end
		end

		if (!Near(after.changedAt, before.changedAt, 1e-3)) then fail("the transition phase did not survive (changedAt " .. after.changedAt .. ", saved " .. before.changedAt .. ")") end
		if (!Near(after.endsAt, before.endsAt, 1e-3)) then fail("the end did not survive (endsAt " .. after.endsAt .. ", saved " .. before.endsAt .. ")") end
		if (!Near(ix.weather.GetValue("precipitation", now), ix.weather.GetValue("precipitation", now, before))) then
			fail("the blended precipitation differs after loading")
		end

		-- unusable data leaves the state alone
		plugin:SetData({type = "hail"})
		plugin:LoadData()

		if (ix.weather.GetState() != after) then fail("loading an unknown type changed the state") end
	end)
end)
