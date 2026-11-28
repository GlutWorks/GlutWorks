-- Exposure (exposure): the comfort band and target for a table of environments built from the weather
-- defaults (the sanity targets); clothing warmth scaled by condition, the faction base and the sealed faction;
-- temperature approaching its target at the configured rate and recovering faster; wetting in rain with and
-- without a poncho, wading, drying faster by heat; heat sources by distance and the registry; each effect at
-- its level; level lines sent once per crossing; soaked clothes wearing and the boots-in-rain modifier; /Feel
-- wrapping with a stand-in immersion plugin; the admin commands; nothing in noclip, sealed or disabled; death
-- resetting both. Named so it sorts after 59_wear.lua. Every check puts back the bot's faction, inventory,
-- temperature, wetness, health and the config it changes.

local Lib = GWH.Lib
local Scoped, WithConfig, ResetBot, Fresh, GiveItem, Replace = Lib.Scoped, Lib.WithConfig, Lib.ResetBot, Lib.Fresh,
	Lib.GiveItem, Lib.Replace
local Expect, Plugin = Lib.Expect, Lib.Plugin
local S = Lib.NewS()

local function Near(fail, label, actual, expected, epsilon)
	if (!isnumber(actual) or math.abs(actual - expected) > (epsilon or 1e-6)) then
		fail(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function Clear(bot)
	for _, item in pairs(bot:GetCharacter():GetInventory():GetItems()) do
		if (item.data) then item.data.equip = nil end
	end

	Fresh(bot)
end

-- The bot as a citizen, inventory empty, comfortable and dry, with everything put back afterwards.
local function Setup(defer, plugin)
	local bot = GWH.Bot()

	if (!bot) then error("no bot") end

	local character = bot:GetCharacter()
	local snapshot = S.Snapshot(bot)
	local temperature, wetness = character:GetTemperature(), character:GetWetness()

	ResetBot(bot)
	bot:SetMoveType(MOVETYPE_WALK)
	Clear(bot)
	S.Become(bot, FACTION_CITIZEN)
	character:SetTemperature(0)
	character:SetWetness(0)
	plugin:ResetTracking(bot)

	defer(function()
		Clear(bot)
		bot:SetMoveType(MOVETYPE_WALK)
		ResetBot(bot)
		S.Restore(bot, snapshot)

		local current = bot:GetCharacter()

		if (current) then
			current:SetTemperature(temperature)
			current:SetWetness(wetness)
		end

		plugin:ResetTracking(bot)
		bot:SetNetVar("ixSoaked", nil)
	end)

	return bot, character, character:GetInventory()
end

local function Wear(bot, inventory, uniqueID)
	local item = GiveItem(inventory, uniqueID)

	item.player = bot
	item.functions.Equip.OnRun(item)
	item.player = nil

	return item
end

local DEFAULTS = {weatherMeanTemperature = 12, weatherSeasonSwing = 6, weatherDaySwing = 5, weatherIndoorTemperature = 15,
	exposureEnabled = true, exposureAdjustTime = 20}

-- An environment from a weather type, hour and month under the defaults, outdoors or under cover.
local function Environment(weather, hour, month, bOutdoors, extra)
	local definition = ix.weather.types[weather]
	local outdoor = ix.weather.ComputeTemperature(hour, month, definition.temperature)
	local env = {
		air = bOutdoors and outdoor or Lerp(ix.weather.INDOOR_DAMPING, outdoor, ix.config.Get("weatherIndoorTemperature", 15)),
		outdoors = bOutdoors,
		precipitation = bOutdoors and definition.precipitation or 0,
		wind = bOutdoors and definition.wind or definition.wind * ix.weather.INDOOR_WIND,
		heat = 0,
		water = 0
	}

	for k, v in pairs(extra or {}) do env[k] = v end

	return env
end

GWH.Check("exposure: comfort band and targets meet the sanity targets under the weather defaults", function(fail)
	local plugin = Plugin("exposure", fail)
	if (!plugin or !ix.weather) then return end

	local detail = {}

	WithConfig(DEFAULTS, function()
		local low, high = plugin:GetComfortBand(0)
		Expect(fail, "unclothed band low", low, 18)
		Expect(fail, "unclothed band high", high, 26)

		local citizen = ix.faction.indices[FACTION_CITIZEN].warmth
		Expect(fail, "citizen faction warmth", citizen, 8)

		low, high = plugin:GetComfortBand(citizen)
		Expect(fail, "citizen band low", low, 10)
		Expect(fail, "citizen band high", high, 22)

		Expect(fail, "no stress inside the band", plugin:GetStress(15, citizen), 0)
		Expect(fail, "cold stress", plugin:GetStress(4, citizen), -6)
		Expect(fail, "heat stress", plugin:GetStress(25, citizen), 3)
		Expect(fail, "12 degrees beyond reaches -100", plugin:GetTarget(-12), -100)
		Expect(fail, "the target is proportional", plugin:GetTarget(6), 50)
		Expect(fail, "the target is clamped", plugin:GetTarget(40), 100)

		local coat = citizen + ix.item.list.winter_coat.warmth + ix.item.list.rain_poncho.warmth
		local cases = {
			{"clear spring noon outdoors", Environment("clear", 12, 4.5, true), 0, citizen, 0, 0},
			{"clear summer 15:00 outdoors", Environment("clear", 15, 7.5, true), 0, citizen, 0, 0},
			{"winter storm 05:00 indoors", Environment("storm", 5, 1.5, false), 0, citizen, 0, 0},
			{"summer 15:00 indoors", Environment("clear", 15, 7.5, false), 0, citizen, 0, 0},
			{"clear winter midnight outdoors", Environment("clear", 0, 1.5, true), 0, citizen, -1, -1},
			{"winter rain noon, soaked, no coat", Environment("rain", 12, 1.5, true), 100, citizen, -3, -2},
			{"winter rain noon, coat and poncho, dry", Environment("rain", 12, 1.5, true), 0, coat, 0, 0},
			{"winter coat, summer 15:00 sun", Environment("clear", 15, 7.5, true), 0, citizen + 10, 2, 4}
		}

		for _, case in ipairs(cases) do
			local name, env, wetness, warmth, lowest, highest = unpack(case)
			local felt = plugin:GetFeltTemperature(env, wetness)
			local target = plugin:GetTarget(plugin:GetStress(felt, warmth))
			local level = ix.exposure.GetLevel(target)

			detail[name] = string.format("air %.1f, felt %.1f, target %.1f (%s)", env.air, felt, target,
				ix.exposure.GetLevelWord(level))

			if (level < lowest or level > highest) then
				fail(name .. ": " .. detail[name] .. ", expected level " .. lowest .. ".." .. highest)
			end
		end

		-- felt temperature parts
		Expect(fail, "felt still air", plugin:GetFeltTemperature({air = 10}, 0), 10)
		Expect(fail, "felt wind outdoors", plugin:GetFeltTemperature({air = 10, outdoors = true, wind = 1}, 0), 10 - ix.exposure.tuning.windChill)
		Expect(fail, "no wind chill indoors", plugin:GetFeltTemperature({air = 10, wind = 1}, 0), 10)
		Expect(fail, "felt sprinting", plugin:GetFeltTemperature({air = 10, sprinting = true}, 0), 10 + ix.exposure.tuning.exertion)
		Expect(fail, "felt soaked in the cold", plugin:GetFeltTemperature({air = 5}, 100), 5 - ix.exposure.tuning.wetChillCold)
		Expect(fail, "felt soaked in the heat", plugin:GetFeltTemperature({air = 30}, 100), 30 - ix.exposure.tuning.wetChillWarm)
	end)

	return detail
end)

GWH.Check("exposure: clothing warmth follows condition, faction base and the sealed faction", function(fail)
	local plugin = Plugin("exposure", fail)
	if (!plugin or !ix.wear) then return end

	Scoped(function(defer)
		local bot, character, inventory = Setup(defer, plugin)

		local bare = plugin:GetClothing(bot)
		Near(fail, "citizen bare warmth", bare.warmth, 8)
		Near(fail, "citizen bare rain protection", bare.waterproof, 0.1)

		local coat = Wear(bot, inventory, "winter_coat")
		Near(fail, "with a new coat", plugin:GetClothing(bot).warmth, 18)

		ix.wear.SetCondition(coat, 30)
		Near(fail, "with a coat at 30 condition", plugin:GetClothing(bot).warmth, 8 + 10 * 0.75)

		ix.wear.SetCondition(coat, 0)
		Near(fail, "with a ruined coat", plugin:GetClothing(bot).warmth, 8)

		ix.wear.SetCondition(coat, 100)
		coat:SetData("equip", nil)

		local poncho = Wear(bot, inventory, "rain_poncho")
		Near(fail, "poncho rain protection", plugin:GetClothing(bot).waterproof, 0.9)

		local cap = Wear(bot, inventory, "wool_cap")
		Near(fail, "poncho and cap", plugin:GetClothing(bot).waterproof, 0.9 + 0.1 * 0.1 * ix.exposure.tuning.headShare)
		cap:SetData("equip", nil)
		poncho:SetData("equip", nil)

		S.Become(bot, FACTION_MPF)
		Near(fail, "MPF base warmth", plugin:GetClothing(bot).warmth, ix.faction.indices[FACTION_MPF].warmth)
		Near(fail, "MPF base rain protection", plugin:GetClothing(bot).waterproof, 0.7)

		if (ix.exposure.IsSealed(bot)) then fail("MPF counts as sealed") end

		S.Become(bot, FACTION_OTA)
		if (!ix.exposure.IsSealed(bot)) then fail("OTA is not climate sealed") end

		character:SetTemperature(-40)
		if (plugin:ExposureTick(bot, character, 60) != nil) then fail("a sealed character was ticked") end
		Expect(fail, "sealed temperature untouched", character:GetTemperature(), -40)
		if (ix.exposure.Applies(bot)) then fail("Applies is true for OTA") end
	end)
end)

GWH.Check("exposure: temperature moves at the configured rate and recovers faster", function(fail)
	local plugin = Plugin("exposure", fail)
	if (!plugin) then return end

	local tuning = ix.exposure.tuning

	WithConfig({exposureAdjustTime = 20}, function()
		local base = 100 / 1200

		Near(fail, "base rate", plugin:GetBaseRate(), base)
		Near(fail, "cooling for a minute", plugin:ApproachTemperature(0, -100, 60), -base * 60, 1e-6)
		Near(fail, "cooling stops at the target", plugin:ApproachTemperature(-10, -12, 600), -12)
		Near(fail, "heating for a minute", plugin:ApproachTemperature(0, 100, 60), base * 60, 1e-6)
		Near(fail, "warming up indoors", plugin:ApproachTemperature(-50, 0, 60), -50 + base * tuning.recovery * 60, 1e-6)
		Near(fail, "warming up by a fire", plugin:ApproachTemperature(-50, 0, 60, 10), -50 + base * tuning.warmup * 60, 1e-6)
		Near(fail, "cooling down from heat", plugin:ApproachTemperature(50, 0, 60), 50 - base * tuning.recovery * 60, 1e-6)

		-- crossing from cold to heat: back to 0 at the fast rate, then on at the base rate
		local fast = base * tuning.recovery
		Near(fail, "crossing zero", plugin:ApproachTemperature(-1, 50, 60), (60 - 1 / fast) * base, 1e-6)

		-- a full swing takes exposureAdjustTime minutes; the way back takes less than half of it
		local temperature, minutes = 0, 0

		while (temperature > -100 and minutes < 100) do
			temperature = plugin:ApproachTemperature(temperature, -100, 60)
			minutes = minutes + 1
		end

		Expect(fail, "minutes from 0 to -100", minutes, 20)

		local back = 0

		while (temperature < 0 and back < 100) do
			temperature = plugin:ApproachTemperature(temperature, 0, 60)
			back = back + 1
		end

		if (back >= minutes / 2) then fail("warming back took " .. back .. " minutes, cooling " .. minutes) end

		ix.config.Set("exposureAdjustTime", 10)
		Near(fail, "faster with a shorter adjust time", plugin:ApproachTemperature(0, -100, 60), -10, 1e-6)
	end)
end)

GWH.Check("exposure: rain wets without a poncho, wading soaks, heat dries faster", function(fail)
	local plugin = Plugin("exposure", fail)
	if (!plugin) then return end

	local tuning = ix.exposure.tuning
	local rain = {air = 6, outdoors = true, precipitation = 0.7, wind = 0.45, heat = 0, water = 0}

	local bare = plugin:UpdateWetness(0, rain, 0.1, 60)
	Near(fail, "a minute of rain in the jumpsuit", bare, tuning.wetRate * 0.7 * 0.9 - (tuning.dryBase + 0.45 * tuning.dryWind), 1e-6)

	if (bare <= 0) then fail("rain does not wet a citizen") end

	Expect(fail, "a minute of rain under a poncho", plugin:UpdateWetness(0, rain, 0.9, 60), 0)

	local soaked = 0

	for _ = 1, 30 do soaked = plugin:UpdateWetness(soaked, rain, 0.1, 60) end

	if (soaked < tuning.soaked) then fail("half an hour of rain leaves wetness at " .. soaked) end

	local storm = {air = 4, outdoors = true, precipitation = 1, wind = 0.9, heat = 0, water = 0}
	local undercover = 0

	for _ = 1, 30 do undercover = plugin:UpdateWetness(undercover, storm, 0.9, 60) end

	if (undercover > 5) then fail("a poncho in a storm still reached " .. undercover) end

	local dry = {air = 15, outdoors = false, precipitation = 0, wind = 0, heat = 0}

	Expect(fail, "feet in water", plugin:UpdateWetness(0, table.Merge(table.Copy(dry), {water = 1}), 0, 5), tuning.wading[1])
	Expect(fail, "waist deep", plugin:UpdateWetness(0, table.Merge(table.Copy(dry), {water = 2}), 0, 5), tuning.wading[2])
	Expect(fail, "under water", plugin:UpdateWetness(0, table.Merge(table.Copy(dry), {water = 3}), 0, 5), 100)

	if (tuning.wading[1] >= tuning.soaked or tuning.wading[2] < tuning.soaked) then
		fail("legs in water should only partly wet, waist deep should soak")
	end

	local indoors = plugin:UpdateWetness(80, dry, 0, 60)
	local byFire = plugin:UpdateWetness(80, table.Merge(table.Copy(dry), {heat = 15}), 0, 60)
	local outside = plugin:UpdateWetness(80, {air = 4, outdoors = true, precipitation = 0, wind = 0.1, heat = 0}, 0, 60)

	if (!(byFire < indoors and indoors < outside and outside < 80)) then
		fail(string.format("drying: fire %.2f, indoors %.2f, cold outdoors %.2f should be in that order below 80", byFire, indoors, outside))
	end

	Expect(fail, "wetness never goes below 0", plugin:UpdateWetness(0.1, dry, 0, 600), 0)
end)

GWH.Check("exposure: heat sources warm by distance, and the registry", function(fail)
	local plugin = Plugin("exposure", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local source = {radius = 200, heat = 20}

	Expect(fail, "heat at the centre", ix.exposure.HeatFrom(source, 0), 20)
	Expect(fail, "heat halfway", ix.exposure.HeatFrom(source, 100), 10)
	Expect(fail, "heat at the radius", ix.exposure.HeatFrom(source, 200), 0)
	Expect(fail, "heat beyond", ix.exposure.HeatFrom(source, 500), 0)

	if (!ix.exposure.heatSources.env_fire) then fail("env_fire is not a heat source") end

	local craft = ix.plugin.list.ixcraft and ix.plugin.list.ixcraft.craft
	local smelters = 0

	for id, station in pairs(craft and craft.stations or {}) do
		if (station.smelting) then
			smelters = smelters + 1

			if (!ix.exposure.heatSources["ix_station_" .. id]) then fail("smelter " .. id .. " is not a heat source") end
		end
	end

	if (smelters == 0) then fail("no smelter stations found to register") end

	Scoped(function(defer)
		local class = "info_target"
		local previous = ix.exposure.heatSources[class]
		local bActive = true

		defer(function() ix.exposure.heatSources[class] = previous end)

		local centre = bot:WorldSpaceCenter()
		local before = ix.exposure.GetHeatAt(centre, bot)
		local entity = ents.Create(class)

		entity:SetPos(centre + Vector(150, 0, 0))
		entity:Spawn()
		defer(function() if (IsValid(entity)) then entity:Remove() end end)

		ix.exposure.RegisterHeatSource(class, {radius = 300, heat = 12, IsActive = function() return bActive end})

		local distance = centre:Distance(entity:WorldSpaceCenter())
		Near(fail, "a registered source at 150 units", ix.exposure.GetHeatAt(centre, bot) - before, 12 * (1 - distance / 300), 1e-3)

		bActive = false
		Near(fail, "an inactive source", ix.exposure.GetHeatAt(centre, bot), before, 1e-3)

		bActive = true
		entity:SetPos(centre + Vector(250, 0, 0))
		distance = centre:Distance(entity:WorldSpaceCenter())
		Near(fail, "the same source further away", ix.exposure.GetHeatAt(centre, bot) - before, 12 * (1 - distance / 300), 1e-3)

		ix.exposure.RegisterHeatSource(class, nil)
		Expect(fail, "unregistered", ix.exposure.heatSources[class], nil)
		Near(fail, "after unregistering", ix.exposure.GetHeatAt(centre, bot), before, 1e-3)

		-- the felt temperature carries the heat
		Expect(fail, "felt with heat", plugin:GetFeltTemperature({air = 0, heat = 10}, 0), 10)
	end)
end)

GWH.Check("exposure: effects at their levels: slowdown, thirst, stamina, damage", function(fail)
	local plugin = Plugin("exposure", fail)
	if (!plugin) then return end

	local tuning = ix.exposure.tuning

	Expect(fail, "speed when cold", ix.exposure.GetSpeedScale(-60), 1)
	Expect(fail, "speed entering freezing", ix.exposure.GetSpeedScale(-75), tuning.slowdown[1])
	Expect(fail, "speed at -100", ix.exposure.GetSpeedScale(-100), tuning.slowdown[2])
	Expect(fail, "speed in heat", ix.exposure.GetSpeedScale(100), 1)

	local levels = {[0] = 0, [-24] = 0, [-25] = -1, [-50] = -2, [-75] = -3, [-92] = -4, [30] = 1, [60] = 2, [80] = 3, [100] = 4}

	for temperature, level in pairs(levels) do
		Expect(fail, "level at " .. temperature, ix.exposure.GetLevel(temperature), level)
	end

	Scoped(function(defer)
		local bot, character = Setup(defer, plugin)
		local health = bot:Health()

		defer(function() if (IsValid(bot)) then bot:SetHealth(health) end end)

		-- SetupMove scales the speed and returns nothing
		character:SetTemperature(-100)

		local speeds = {client = 200, max = 200}
		local moveData = {
			GetMaxClientSpeed = function() return speeds.client end,
			SetMaxClientSpeed = function(_, value) speeds.client = value end,
			GetMaxSpeed = function() return speeds.max end,
			SetMaxSpeed = function(_, value) speeds.max = value end
		}

		if (plugin:SetupMove(bot, moveData) != nil) then fail("SetupMove returned a value") end
		Near(fail, "speed at -100", speeds.client, 200 * tuning.slowdown[2])

		character:SetTemperature(0)
		speeds.client = 200
		plugin:SetupMove(bot, moveData)
		Expect(fail, "speed when comfortable", speeds.client, 200)

		-- heat drains thirst
		if (ix.plugin.list.survivaladditions) then
			local thirst = character:GetThirst()

			defer(function() character:SetThirst(thirst) end)

			WithConfig({hungerthirstEnabled = true, thirstLossTime = 90}, function()
				character:SetThirst(50)
				local result = plugin:ApplyEffects(bot, character, 60, 0, 60, false)
				Near(fail, "thirst when hot", result.thirst, 100 / 5400 * tuning.heatThirst[2] * 60, 1e-4)

				character:SetThirst(50)
				result = plugin:ApplyEffects(bot, character, 30, 0, 60, false)
				Expect(fail, "thirst when only warm", result.thirst, 0)

				ix.config.Set("hungerthirstEnabled", false)
				character:SetThirst(50)
				result = plugin:ApplyEffects(bot, character, 100, 0, 1, false)
				Expect(fail, "thirst with hunger and thirst off", result.thirst, 0)
			end)
		end

		-- overheating drains stamina while moving
		if (bot.ConsumeStamina) then
			bot:SetLocalVar("stm", 100)
			local result = plugin:ApplyEffects(bot, character, 80, 0, 5, true)
			Near(fail, "stamina overheating", result.stamina, tuning.heatStamina[3] * 5, 1e-4)

			bot:SetLocalVar("stm", 100)
			result = plugin:ApplyEffects(bot, character, 80, 0, 5, false)
			Expect(fail, "stamina overheating standing still", result.stamina, 0)

			bot:SetLocalVar("stm", 100)
			result = plugin:ApplyEffects(bot, character, 60, 0, 5, true)
			Expect(fail, "stamina when only hot", result.stamina, 0)
			bot:SetLocalVar("stm", 100)
		end

		-- damage at the worst level, with a floor while not lethal
		WithConfig({exposureDamage = 5, exposureLethal = false}, function()
			bot:SetHealth(50)
			Expect(fail, "damage when freezing", plugin:ApplyEffects(bot, character, -80, 0, 5, false).damage, 0)
			Expect(fail, "damage hypothermic", plugin:ApplyEffects(bot, character, -95, 0, 5, false).damage, 5)
			Expect(fail, "health after one tick", bot:Health(), 45)

			Expect(fail, "damage in heatstroke", plugin:ApplyEffects(bot, character, 95, 0, 5, false).damage, 5)

			bot:SetHealth(12)
			plugin:ApplyEffects(bot, character, -100, 0, 5, false)
			Expect(fail, "stops at the floor", bot:Health(), tuning.healthFloor)
			plugin:ApplyEffects(bot, character, -100, 0, 5, false)
			Expect(fail, "stays at the floor", bot:Health(), tuning.healthFloor)
			if (!bot:Alive()) then fail("non-lethal exposure killed") end

			ix.config.Set("exposureDamage", 0)
			bot:SetHealth(50)
			plugin:ApplyEffects(bot, character, -100, 0, 5, false)
			Expect(fail, "exposureDamage 0", bot:Health(), 50)
		end)

		WithConfig({exposureDamage = 5, exposureLethal = true}, function()
			character:SetTemperature(-100)
			character:SetWetness(90)
			bot:SetHealth(3)
			plugin:ApplyEffects(bot, character, -100, 90, 5, false)

			if (bot:Alive()) then fail("lethal exposure did not kill at 3 health") end

			-- dying puts the body back to comfortable and dry
			Expect(fail, "temperature after dying", character:GetTemperature(), 0)
			Expect(fail, "wetness after dying", character:GetWetness(), 0)
		end)

		ResetBot(bot)
	end)
end)

GWH.Check("exposure: a line in words once per level crossing, and for soaked and dry", function(fail)
	local plugin = Plugin("exposure", fail)
	if (!plugin) then return end

	Scoped(function(defer)
		local bot = Setup(defer, plugin)
		local told = {}

		Replace(defer, plugin, "Tell", function(_, client, phrase)
			if (client == bot) then told[#told + 1] = phrase end
		end)

		local steps = {
			{0, 0, nil}, -- the first call only records
			{-30, 0, "exposureCold1"},
			{-31, 0, nil},
			{-55, 0, "exposureCold2"},
			{-95, 0, "exposureCold4"},
			{-80, 0, "exposureColdBetter3"},
			{-30, 0, "exposureColdBetter1"},
			{0, 0, "exposureColdBetter0"},
			{30, 0, "exposureHeat1"},
			{60, 0, "exposureHeat2"},
			{10, 0, "exposureHeatBetter0"},
			{10, 70, "exposureSoaked"},
			{10, 50, nil},
			{10, 30, nil},
			{10, 10, "exposureDried"},
			{-40, 10, "exposureCold1"}, -- from comfortable straight past nothing to chilly
			{-0.1, 10, "exposureColdBetter0"}, -- a hair below zero is comfortable, not "-0"
			{60, 10, "exposureHeat2"},
			{-0.1, 10, "exposureHeatBetter0"}
		}

		for index, step in ipairs(steps) do
			local count = #told

			plugin:UpdateLines(bot, step[1], step[2])

			local said = #told > count and told[#told] or nil

			if (#told > count + 1) then fail("step " .. index .. " sent " .. (#told - count) .. " lines") end
			if (said != step[3]) then fail("step " .. index .. " (" .. step[1] .. ", " .. step[2] .. "): expected " .. tostring(step[3]) .. ", got " .. tostring(said)) end
		end

		for _, phrase in ipairs(told) do
			if (!ix.lang.stored.english[phrase] or !ix.lang.stored.spanish[phrase]) then fail(phrase .. " is missing a translation") end
		end
	end)

	-- through the immersion plugin's private chat when it is loaded, a notice otherwise
	Scoped(function(defer)
		local bot = GWH.Bot()
		local sent = {}

		Replace(defer, ix.plugin.list, "immersion", {SendPrivate = function(_, client, text) sent[#sent + 1] = {client, text} end})
		plugin:Tell(bot, "exposureCold2")

		if (#sent != 1 or sent[1][1] != bot or sent[1][2] != L("exposureCold2", bot)) then
			fail("Tell did not go through the immersion plugin's SendPrivate: " .. util.TableToJSON(sent))
		end

		ix.plugin.list.immersion = nil

		local seen = Lib.Capture(bot, function() plugin:Tell(bot, "exposureCold2") end)

		if (!string.find(seen.notices, "exposureCold2", 1, true)) then fail("without immersion no notice was sent: " .. seen.notices) end
	end)
end)

GWH.Check("exposure: soaked clothes wear, and boots wear faster in rain", function(fail)
	local plugin = Plugin("exposure", fail)
	if (!plugin or !ix.wear) then return end

	Scoped(function(defer)
		local bot, character, inventory = Setup(defer, plugin)

		WithConfig({wearEnabled = true}, function()
			local coat = Wear(bot, inventory, "winter_coat")
			local poncho = Wear(bot, inventory, "rain_poncho")
			local tuning = ix.exposure.tuning

			local result = plugin:ApplyEffects(bot, character, 0, 80, 3600, false)
			Near(fail, "coat soaked for an hour", 100 - ix.wear.GetCondition(coat), tuning.soakedWearPerHour / coat.durability, 1e-4)
			Expect(fail, "poncho soaked for an hour", ix.wear.GetCondition(poncho), 100)
			Near(fail, "worn total", result.worn, tuning.soakedWearPerHour / coat.durability, 1e-4)

			ix.wear.SetCondition(coat, 100)
			plugin:ApplyEffects(bot, character, 0, 40, 3600, false)
			Expect(fail, "coat damp but not soaked", ix.wear.GetCondition(coat), 100)

			if (ix.wear.modifiers.exposure != ix.exposure.BootsInRain) then fail("the exposure wear modifier is not registered") end

			local boots = Wear(bot, inventory, "work_boots")
			local weather = {outdoors = true, precipitation = 1, wind = 0}

			Replace(defer, ix.weather, "GetExposure", function() return weather end)

			Near(fail, "boots walking in a storm", ix.exposure.BootsInRain(bot, boots, "walk", 1), 1 + tuning.rainBootWear)
			Expect(fail, "boots wearing with time", ix.exposure.BootsInRain(bot, boots, "time", 1), nil)

			weather.precipitation = 0
			Expect(fail, "boots walking in the dry", ix.exposure.BootsInRain(bot, boots, "walk", 1), nil)

			weather.precipitation = 0.5
			Near(fail, "through the modifier chain", ix.wear.ApplyModifiers(bot, boots, "walk", 1), 1 + 0.5 * tuning.rainBootWear)

			ix.config.Set("exposureEnabled", false)
			Expect(fail, "boots with exposure off", ix.exposure.BootsInRain(bot, boots, "walk", 1), nil)
			ix.config.Set("exposureEnabled", true)
		end)
	end)
end)

GWH.Check("exposure: /Feel carries temperature and wetness through a stand-in immersion plugin, wrapped once", function(fail)
	local plugin = Plugin("exposure", fail)
	if (!plugin) then return end

	Scoped(function(defer)
		local bot, character = Setup(defer, plugin)
		local standIn = {
			DescribeCondition = function(_, client, state) return "Base." end
		}

		Replace(defer, ix.plugin.list, "immersion", nil)
		if (plugin:WrapImmersion() != false) then fail("wrapping without the immersion plugin did something") end

		ix.plugin.list.immersion = standIn

		if (plugin:WrapImmersion() != true) then fail("the stand-in was not wrapped") end
		if (plugin:WrapImmersion() != false) then fail("the stand-in was wrapped twice") end

		Expect(fail, "comfortable and dry", standIn:DescribeCondition(bot), "Base.")

		character:SetTemperature(-60)
		character:SetWetness(70)

		local expected = "Base. " .. L("feelExposureCold2", bot) .. " " .. L("feelExposureSoaked", bot)
		Expect(fail, "cold and soaked", standIn:DescribeCondition(bot), expected)
		Expect(fail, "DescribeExposure", plugin:DescribeExposure(bot), L("feelExposureCold2", bot) .. " " .. L("feelExposureSoaked", bot))

		character:SetTemperature(80)
		character:SetWetness(30)
		Expect(fail, "overheating and damp", standIn:DescribeCondition(bot), "Base. " .. L("feelExposureHeat3", bot) .. " " .. L("feelExposureDamp", bot))

		-- a refresh of the immersion plugin defines a new function; it is wrapped again, once
		standIn.DescribeCondition = function(_, client, state) return "Refreshed." end

		if (plugin:WrapImmersion() != true) then fail("the refreshed function was not wrapped") end
		plugin:WrapImmersion()
		Expect(fail, "after a refresh", standIn:DescribeCondition(bot), "Refreshed. " .. L("feelExposureHeat3", bot) .. " " .. L("feelExposureDamp", bot))

		-- "You feel fine." is replaced, not contradicted
		Expect(fail, "replacing feeling fine", plugin:AppendDescription(bot, L("feelFine", bot)), L("feelExposureHeat3", bot) .. " " .. L("feelExposureDamp", bot))

		character:SetTemperature(0)
		character:SetWetness(0)
		if (plugin:DescribeExposure(bot) != nil) then fail("something to say while comfortable and dry") end
	end)
end)

GWH.Check("exposure: /CharSetTemperature and /CharSetWetness need an admin and clamp", function(fail)
	local plugin = Plugin("exposure", fail)
	if (!plugin) then return end

	Scoped(function(defer)
		local bot, character = Setup(defer, plugin)
		local group = bot:GetUserGroup()
		local name = '"' .. character:GetName() .. '"'

		defer(function() bot:SetUserGroup(group) end)

		bot:SetUserGroup("user")
		S.Command(bot, "/CharSetTemperature " .. name .. " -50")
		Expect(fail, "a user set the temperature", character:GetTemperature(), 0)
		S.Command(bot, "/CharSetWetness " .. name .. " 50")
		Expect(fail, "a user set the wetness", character:GetWetness(), 0)

		bot:SetUserGroup("superadmin")
		S.Command(bot, "/CharSetTemperature " .. name .. " -50")
		Expect(fail, "admin set temperature", character:GetTemperature(), -50)
		S.Command(bot, "/CharSetTemperature " .. name .. " -500")
		Expect(fail, "temperature clamps low", character:GetTemperature(), -100)
		S.Command(bot, "/CharSetTemperature " .. name .. " 500")
		Expect(fail, "temperature clamps high", character:GetTemperature(), 100)
		S.Command(bot, "/CharSetWetness " .. name .. " 150")
		Expect(fail, "wetness clamps high", character:GetWetness(), 100)
		S.Command(bot, "/CharSetWetness " .. name .. " -5")
		Expect(fail, "wetness clamps low", character:GetWetness(), 0)
	end)
end)

GWH.Check("exposure: a full tick moves both, and nothing happens in noclip, when disabled or after death", function(fail)
	local plugin = Plugin("exposure", fail)
	if (!plugin) then return end

	Scoped(function(defer)
		local bot, character = Setup(defer, plugin)
		local env = {air = 2, outdoors = true, precipitation = 0.7, wind = 0.45, heat = 0, sprinting = false, water = 0}

		Replace(defer, plugin, "GetEnvironment", function() return table.Copy(env) end)
		Replace(defer, plugin, "Tell", function() end)

		WithConfig({exposureEnabled = true, exposureAdjustTime = 20, exposureTickTime = 5}, function()
			local result = plugin:ExposureTick(bot, character, 60)

			if (!result) then return fail("the tick did nothing for a citizen in the rain") end
			if (character:GetWetness() <= 0) then fail("a minute of rain left the citizen dry") end
			if (character:GetTemperature() >= 0) then fail("a minute of cold rain left the citizen at " .. character:GetTemperature()) end
			Near(fail, "temperature after a minute", character:GetTemperature(), math.max(result.target, -100 / 20), 1e-6)

			-- noclip
			local temperature, wetness = character:GetTemperature(), character:GetWetness()

			bot:SetMoveType(MOVETYPE_NOCLIP)
			if (plugin:ExposureTick(bot, character, 60) != nil) then fail("ticked in noclip") end
			bot:SetMoveType(MOVETYPE_WALK)
			Expect(fail, "temperature in noclip", character:GetTemperature(), temperature)
			Expect(fail, "wetness in noclip", character:GetWetness(), wetness)

			-- disabled: nothing ticks and everyone goes back to comfortable and dry
			ix.config.Set("exposureEnabled", false)
			if (plugin:ExposureTick(bot, character, 60) != nil) then fail("ticked with exposureEnabled off") end
			Expect(fail, "temperature after disabling", character:GetTemperature(), 0)
			Expect(fail, "wetness after disabling", character:GetWetness(), 0)
			ix.config.Set("exposureEnabled", true)

			-- death resets both
			character:SetTemperature(-70)
			character:SetWetness(80)
			bot:Kill()
			Expect(fail, "temperature after death", character:GetTemperature(), 0)
			Expect(fail, "wetness after death", character:GetWetness(), 0)
			ResetBot(bot)
		end)
	end)
end)
