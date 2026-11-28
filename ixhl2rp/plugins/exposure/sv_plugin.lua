local PLUGIN = PLUGIN

-- The model. Every step takes explicit inputs so a check can run it in one tick:
--   GetEnvironment(client)                      -> env {air, outdoors, precipitation, wind, heat, sprinting, water}
--   GetClothing(client)                         -> {warmth, waterproof}
--   UpdateWetness(wetness, env, waterproof, dt) -> new wetness
--   GetFeltTemperature(env, wetness)            -> °C the body feels
--   GetStress(felt, warmth)                     -> degrees outside the comfort band (cold negative)
--   GetTarget(stress)                           -> where temperature is heading, -100..100
--   ApproachTemperature(current, target, dt, heat) -> new temperature
--   ApplyEffects(client, character, temperature, wetness, dt, moving) -> what the body suffered this tick
-- ExposureTick runs them in that order; the timer at the bottom feeds it.

local tuning = ix.exposure.tuning

-- Anything on fire that has no heat source entry of its own.
ix.exposure.ON_FIRE = {radius = 200, heat = 15}

--- The heat (°C) one source gives at `distance` units: its full heat at the centre, nothing at its radius.
function ix.exposure.HeatFrom(source, distance)
	if (!source or distance >= source.radius) then
		return 0
	end

	return source.heat * (1 - math.max(distance, 0) / source.radius)
end

local function MaxRadius()
	local radius = ix.exposure.ON_FIRE.radius

	for _, source in pairs(ix.exposure.heatSources) do
		radius = math.max(radius, source.radius)
	end

	return radius
end

local function IsActive(source, entity)
	if (!source.IsActive) then
		return true
	end

	local ok, result = pcall(source.IsActive, entity)

	if (!ok) then
		ErrorNoHalt("[exposure] heat source " .. entity:GetClass() .. ": " .. tostring(result) .. "\n")
		return false
	end

	return result == true
end

--- The heat (°C) that every active source near pos adds, capped at tuning.heatMax. `ignore` is skipped (the
-- player being warmed).
function ix.exposure.GetHeatAt(pos, ignore)
	local total = 0

	for _, entity in ipairs(ents.FindInSphere(pos, MaxRadius())) do
		if (entity != ignore and IsValid(entity)) then
			local source = ix.exposure.heatSources[entity:GetClass()]

			if (source and !IsActive(source, entity)) then
				source = nil
			end

			if (!source and !entity:IsPlayer() and entity:IsOnFire()) then
				source = ix.exposure.ON_FIRE
			end

			if (source) then
				total = total + ix.exposure.HeatFrom(source, pos:Distance(entity:WorldSpaceCenter()))
			end
		end
	end

	return math.min(total, tuning.heatMax)
end

--- What the player's body is in now.
function PLUGIN:GetEnvironment(client)
	local env = {air = 15, outdoors = false, precipitation = 0, wind = 0}

	if (ix.weather) then
		local exposure = ix.weather.GetExposure(client)

		env.outdoors = exposure.outdoors
		env.precipitation = exposure.precipitation
		env.wind = exposure.wind
		env.air = ix.weather.GetTemperatureAt(client:EyePos(), exposure.outdoors)
	end

	env.heat = ix.exposure.GetHeatAt(client:WorldSpaceCenter(), client)
	env.sprinting = client:IsSprinting() and client:GetVelocity():Length2D() > client:GetWalkSpeed() + 10
	env.water = client:WaterLevel()

	return env
end

--- The warmth (°C) and rain protection (0..1) of what the player has on: the faction's own outfit plus every
-- worn item, each scaled by its condition. Rain protection is the best of the faction, outer and body garments,
-- with a little more from a head item.
function PLUGIN:GetClothing(client)
	local faction = ix.exposure.GetFaction(client)
	local warmth = faction and tonumber(faction.warmth) or 0
	local best = faction and tonumber(faction.waterproof) or 0
	local head = 0

	if (ix.wear) then
		for _, item in ipairs(ix.wear.GetWorn(client)) do
			local effectiveness = ix.wear.GetEffectiveness(item)
			local waterproof = (tonumber(item.waterproof) or 0) * effectiveness

			warmth = warmth + (tonumber(item.warmth) or 0) * effectiveness

			if (item.wearPart == "outer" or item.wearPart == "body") then
				best = math.max(best, waterproof)
			elseif (item.wearPart == "head") then
				head = math.max(head, waterproof)
			end
		end
	end

	best = math.Clamp(best, 0, 1)

	return {warmth = warmth, waterproof = math.Clamp(best + (1 - best) * head * tuning.headShare, 0, 1)}
end

--- The new wetness after `delta` seconds in env with this rain protection.
function PLUGIN:UpdateWetness(wetness, env, waterproof, delta)
	local wet = tuning.wetRate * (env.precipitation or 0) * (1 - math.Clamp(waterproof or 0, 0, 1))
	local dry = tuning.dryBase +
		(env.outdoors and (env.wind or 0) * tuning.dryWind or tuning.dryIndoors) +
		math.max((env.air or 15) - tuning.dryWarmFrom, 0) * tuning.dryPerDegree +
		(env.heat or 0) * tuning.dryPerHeat

	local new = math.Clamp(wetness + (wet - dry) * delta / 60, 0, 100)
	local wading = tuning.wading[env.water or 0]

	if (wading) then
		new = math.max(new, wading)
	end

	return new
end

--- The temperature (°C) the body feels in env while this wet: the air, plus heat and exertion, less wind chill
-- outdoors and wet chill (much worse in the cold).
function PLUGIN:GetFeltTemperature(env, wetness)
	local air = env.air or 15
	local felt = air + (env.heat or 0)

	if (env.sprinting) then
		felt = felt + tuning.exertion
	end

	if (env.outdoors) then
		felt = felt - (env.wind or 0) * tuning.windChill
	end

	local coldness = math.Clamp((tuning.wetWarmAir - air) / (tuning.wetWarmAir - tuning.wetColdAir), 0, 1)
	local chill = Lerp(coldness, tuning.wetChillWarm, tuning.wetChillCold)

	return felt - chill * math.Clamp(wetness or 0, 0, 100) / 100
end

--- The comfort band for this much warmth: {low, high} in °C.
function PLUGIN:GetComfortBand(warmth)
	warmth = warmth or 0

	return tuning.comfortLow - warmth, tuning.comfortHigh - warmth * tuning.heatClothingShare
end

--- Degrees the felt temperature is outside the comfort band for this warmth: negative below it, positive above.
function PLUGIN:GetStress(felt, warmth)
	local low, high = self:GetComfortBand(warmth)

	if (felt < low) then
		return felt - low
	elseif (felt > high) then
		return felt - high
	end

	return 0
end

--- The temperature the body heads for under this stress.
function PLUGIN:GetTarget(stress)
	return math.Clamp(stress / tuning.stressFull * 100, -100, 100)
end

--- Points per second a body moves away from comfortable (exposureAdjustTime minutes for 0 to 100).
function PLUGIN:GetBaseRate()
	return 100 / (math.max(ix.config.Get("exposureAdjustTime", 20), 0.01) * 60)
end

--- Moves temperature toward target over `delta` seconds. The part of the way back toward 0 goes
-- tuning.recovery times faster, tuning.warmup times when getting warm by a heat source.
function PLUGIN:ApproachTemperature(current, target, delta, heat)
	local base = self:GetBaseRate()

	if ((current < 0 and target > current) or (current > 0 and target < current)) then
		local fast = base * ((current < 0 and (heat or 0) > 0) and tuning.warmup or tuning.recovery)
		local stop = current < 0 and math.min(target, 0) or math.max(target, 0)
		local needed = math.abs(stop - current) / fast

		if (needed >= delta) then
			return math.Approach(current, stop, fast * delta)
		end

		delta = delta - needed
		current = stop
	end

	return math.Approach(current, target, base * delta)
end

--- Sends a private line in words: through the immersion plugin's private chat when it is loaded, otherwise as
-- a notice.
function PLUGIN:Tell(client, phrase, ...)
	local immersion = ix.plugin.Get("immersion")

	if (immersion and isfunction(immersion.SendPrivate)) then
		immersion:SendPrivate(client, L(phrase, client, ...))
	else
		client:NotifyLocalized(phrase, ...)
	end
end

--- Forgets the last level and soaked state, so the next tick notes them again without telling.
function PLUGIN:ResetTracking(client)
	client.ixExposureLevel = nil
	client.ixExposureSoaked = nil
	client.ixExposureColdTime = 0
	client.ixExposureNextCough = nil
end

--- The phrase for moving from one signed level to another, or nil.
function PLUGIN:GetLevelPhrase(old, new)
	if (old == new) then
		return
	end

	if (new < 0 and new < old) then
		return "exposureCold" .. -new
	elseif (new > 0 and new > old) then
		return "exposureHeat" .. new
	elseif (old < 0) then
		return "exposureColdBetter" .. math.abs(new)
	else
		return "exposureHeatBetter" .. new
	end
end

--- Tells the player when their temperature crosses into another level, and when they get soaked or dry off.
-- The first call after a reset only records.
function PLUGIN:UpdateLines(client, temperature, wetness)
	local level = ix.exposure.GetLevel(temperature)
	local old = client.ixExposureLevel

	client.ixExposureLevel = level

	if (old != nil and old != level) then
		local phrase = self:GetLevelPhrase(old, level)

		if (phrase) then
			self:Tell(client, phrase)
		end
	end

	local bWasSoaked = client.ixExposureSoaked
	local bSoaked = bWasSoaked

	if (wetness >= tuning.soaked) then
		bSoaked = true
	elseif (wetness < tuning.dry or bSoaked == nil) then
		bSoaked = false
	end

	client.ixExposureSoaked = bSoaked

	if (bWasSoaked != nil and bSoaked != bWasSoaked) then
		self:Tell(client, bSoaked and "exposureSoaked" or "exposureDried")
	end
end

--- Exposure damage for one tick at the worst level. Stops at tuning.healthFloor unless exposureLethal; with it,
-- kills with a notice. Returns the health taken.
function PLUGIN:ExposureDamage(client, level)
	local damage = ix.config.Get("exposureDamage", 1)

	if (damage <= 0) then
		return 0
	end

	local health = client:Health()

	if (ix.config.Get("exposureLethal", false)) then
		if (health - damage <= 0) then
			client:NotifyLocalized(level < 0 and "exposureDiedCold" or "exposureDiedHeat")
			client:Kill()

			return health
		end

		client:SetHealth(health - damage)

		return damage
	end

	local new = math.max(health - damage, tuning.healthFloor)

	if (new >= health) then
		return 0
	end

	client:SetHealth(new)

	return health - new
end

--- Plays a cough from the player that everyone nearby hears.
function PLUGIN:Cough(client)
	local sounds = ix.exposure.coughSounds

	client:EmitSound(sounds[math.random(#sounds)], 70, math.random(94, 106), 0.7)
end

--- What a body at this temperature and wetness suffers over `delta` seconds: thirst and stamina in heat, damage
-- at the worst level, coughing after a while in the cold, clothes wearing while soaked. Returns what it did:
-- {thirst, stamina, damage, coughed, worn}. `bMoving` defaults to whether the player is moving now.
function PLUGIN:ApplyEffects(client, character, temperature, wetness, delta, bMoving)
	local result = {thirst = 0, stamina = 0, damage = 0, coughed = false, worn = 0}
	local level = ix.exposure.GetLevel(temperature)

	-- heat: thirst
	local thirstShare = level > 0 and tuning.heatThirst[level]
	local survival = ix.plugin.Get("survivaladditions")

	if (thirstShare and survival and ix.config.Get("hungerthirstEnabled", false) and character.GetThirst) then
		local perSecond = 100 / (math.max(ix.config.Get("thirstLossTime", 90), 1) * 60)
		local old = character:GetThirst()
		local new = math.max(old - perSecond * thirstShare * delta, 0)

		if (new != old) then
			character:SetThirst(new)
			result.thirst = old - new
		end
	end

	-- heat: stamina while moving
	local stamina = level > 0 and tuning.heatStamina[level]

	if (bMoving == nil) then
		bMoving = client:GetVelocity():Length2D() > 10
	end

	if (stamina and client.ConsumeStamina and bMoving) then
		local before = client:GetLocalVar("stm", 0)

		client:ConsumeStamina(stamina * delta)
		result.stamina = before - client:GetLocalVar("stm", 0)
	end

	-- the worst level hurts
	if (math.abs(level) >= #ix.exposure.LEVELS) then
		result.damage = self:ExposureDamage(client, level)

		if (!client:Alive()) then
			return result
		end
	end

	-- coughing others can hear, once cold for a while
	if (level <= -2) then
		client.ixExposureColdTime = (client.ixExposureColdTime or 0) + delta

		local now = CurTime()

		if (client.ixExposureColdTime >= tuning.coughAfter and now >= (client.ixExposureNextCough or 0)) then
			self:Cough(client)
			client.ixExposureNextCough = now + math.Rand(tuning.coughInterval[1], tuning.coughInterval[2])
			result.coughed = true
		end
	else
		client.ixExposureColdTime = 0
	end

	-- soaked clothes that are not waterproof wear faster
	if (wetness >= tuning.soaked and ix.wear) then
		local amount = tuning.soakedWearPerHour * delta / 3600

		for _, item in ipairs(ix.wear.GetWorn(client)) do
			if ((tonumber(item.waterproof) or 0) < tuning.soakedWearUntil) then
				result.worn = result.worn + ix.wear.Damage(item, amount, "soaked", client)
			end
		end
	end

	return result
end

-- Seen by other players: drips fall from a soaked body.
local function SetSoakedNetVar(client, bSoaked)
	local value = bSoaked or nil

	if (client:GetNetVar("ixSoaked") != value) then
		client:SetNetVar("ixSoaked", value)
	end
end

--- One step of the body for `delta` seconds. Does nothing where ix.exposure.Applies is false. Returns the
-- environment, clothing, felt temperature, target and effects, for checks.
function PLUGIN:ExposureTick(client, character, delta)
	if (!ix.exposure.Applies(client) or client:GetCharacter() != character) then
		return
	end

	local env = self:GetEnvironment(client)
	local clothing = self:GetClothing(client)
	local wetness = self:UpdateWetness(character:GetWetness(), env, clothing.waterproof, delta)
	local felt = self:GetFeltTemperature(env, wetness)
	local target = self:GetTarget(self:GetStress(felt, clothing.warmth))
	local temperature = self:ApproachTemperature(character:GetTemperature(), target, delta, env.heat)

	if (wetness != character:GetWetness()) then
		character:SetWetness(wetness)
	end

	if (temperature != character:GetTemperature()) then
		character:SetTemperature(temperature)
	end

	SetSoakedNetVar(client, wetness >= tuning.soaked)
	self:UpdateLines(client, temperature, wetness)

	local effects = self:ApplyEffects(client, character, temperature, wetness, delta)

	return {env = env, clothing = clothing, felt = felt, target = target, temperature = temperature,
		wetness = wetness, effects = effects}
end

--- Puts a character back to comfortable and dry.
function PLUGIN:ResetBody(client, character)
	character = character or (IsValid(client) and client:GetCharacter())

	if (character) then
		character:SetTemperature(0)
		character:SetWetness(0)
	end

	if (IsValid(client)) then
		self:ResetTracking(client)
		SetSoakedNetVar(client, false)
	end
end

--- The sentences /Feel adds for the player's temperature and wetness, in their language, or nil when they are
-- comfortable and dry.
function PLUGIN:DescribeExposure(client)
	local character = IsValid(client) and client:GetCharacter()

	if (!character or !ix.exposure.Applies(client)) then
		return
	end

	local sentences = {}
	local level = ix.exposure.GetLevel(character:GetTemperature())

	if (level < 0) then
		sentences[#sentences + 1] = L("feelExposureCold" .. -level, client)
	elseif (level > 0) then
		sentences[#sentences + 1] = L("feelExposureHeat" .. level, client)
	end

	local wetness = character:GetWetness()

	if (wetness >= tuning.soaked) then
		sentences[#sentences + 1] = L("feelExposureSoaked", client)
	elseif (wetness >= tuning.damp) then
		sentences[#sentences + 1] = L("feelExposureDamp", client)
	end

	if (#sentences > 0) then
		return table.concat(sentences, " ")
	end
end

--- Adds DescribeExposure's sentences to a /Feel text. "You feel fine." is replaced rather than contradicted.
function PLUGIN:AppendDescription(client, text)
	local extra = self:DescribeExposure(client)

	if (!extra) then
		return text
	end

	if (!isstring(text) or text == "" or text == L("feelFine", client)) then
		return extra
	end

	return text .. " " .. extra
end

--- Wraps the immersion plugin's DescribeCondition once so /Feel also describes temperature and wetness.
-- Nothing happens without that plugin; a refresh of either plugin wraps the current function exactly once.
function PLUGIN:WrapImmersion()
	local immersion = ix.plugin.Get("immersion")

	if (!immersion or !isfunction(immersion.DescribeCondition)) then
		return false
	end

	if (immersion.DescribeCondition == immersion.ixExposureWrapper) then
		return false
	end

	local original = immersion.DescribeCondition
	local function wrapper(this, client, ...)
		local text = original(this, client, ...)
		local exposure = ix.plugin.Get("exposure")

		if (!exposure or !IsValid(client)) then
			return text
		end

		return exposure:AppendDescription(client, text)
	end

	immersion.ixExposureOriginal = original
	immersion.ixExposureWrapper = wrapper
	immersion.DescribeCondition = wrapper

	return true
end

--- Registers every smelter station's entity class as a heat source while it is running.
function PLUGIN:RegisterSmelters()
	local craft = ix.plugin.list.ixcraft and ix.plugin.list.ixcraft.craft
	local stations = craft and craft.stations

	if (!istable(stations)) then
		return
	end

	for id, station in pairs(stations) do
		if (istable(station) and station.smelting) then
			ix.exposure.RegisterHeatSource("ix_station_" .. id, {
				radius = station.exposureRadius or 160,
				heat = station.exposureHeat or 18,
				IsActive = function(entity)
					return ix.smelting != nil and entity.ixSmelting != nil and ix.smelting.CanRun(entity)
				end
			})
		end
	end
end

local function BootsInRain(client, item, cause, amount)
	if (cause != "walk" or !IsValid(client) or !ix.weather or !ix.exposure.Applies(client)) then
		return
	end

	local precipitation = ix.weather.GetExposure(client).precipitation

	if (precipitation > 0) then
		return amount * (1 + precipitation * tuning.rainBootWear)
	end
end

ix.exposure.BootsInRain = BootsInRain

function PLUGIN:InitializedPlugins()
	self:RegisterSmelters()
	self:WrapImmersion()

	if (ix.wear) then
		ix.wear.AddModifier("exposure", BootsInRain)
	end

	self:StartTimer()
end

function PLUGIN:StartTimer()
	local delay = ix.config.Get("exposureTickTime", 5)

	timer.Create("ixExposure", delay, 0, function()
		if (!ix.config.Get("exposureEnabled", true)) then
			return
		end

		for _, client in player.Iterator() do
			local character = client:GetCharacter()

			if (character) then
				self:ExposureTick(client, character, delay)
			end
		end
	end)
end

function PLUGIN:OnEnabledChanged(bEnabled)
	if (bEnabled) then
		return
	end

	for _, client in player.Iterator() do
		if (client:GetCharacter()) then
			self:ResetBody(client)
		end
	end
end

function PLUGIN:PlayerLoadedCharacter(client, character, lastCharacter)
	self:ResetTracking(client)
	SetSoakedNetVar(client, false)
end

function PLUGIN:PlayerDeath(client)
	self:ResetBody(client)
end

-- A Lua refresh keeps the timer; restart it with this load's functions.
if (timer.Exists("ixExposure")) then
	PLUGIN:StartTimer()
end
