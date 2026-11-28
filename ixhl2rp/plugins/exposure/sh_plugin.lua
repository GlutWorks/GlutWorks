local PLUGIN = PLUGIN

PLUGIN.name = "Exposure"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Body temperature and wetness from the weather, shelter, nearby heat and what is worn, told through the body."
PLUGIN.readme = [[
Two character vars: `temperature` (-100 hypothermic .. 0 comfortable .. +100 heatstroke) and `wetness`
(0 dry .. 100 soaked). The server moves them every `exposureTickTime` seconds through
`PLUGIN:ExposureTick(client, character, delta)`, which is split into steps that take explicit inputs
(GetFeltTemperature, GetStress, GetTarget, ApproachTemperature, UpdateWetness, ApplyEffects).
Nothing is drawn as a bar, icon or number: the player feels it (shivering, breath vapour, screen tint,
slower legs, coughing others hear) and `/Feel` (immersion plugin, when loaded) says it in words.

Factions may set `FACTION.warmth` (°C), `FACTION.waterproof` (0..1) and `FACTION.bClimateSealed`.
Other plugins add heat sources with `ix.exposure.RegisterHeatSource(class, {radius, heat, IsActive})`.
]]

ix.exposure = ix.exposure or {}
ix.exposure.heatSources = ix.exposure.heatSources or {}

ix.char.RegisterVar("temperature", {
	field = "temperature",
	fieldType = ix.type.number,
	default = 0,
	isLocal = true,
	bNoDisplay = true
})

ix.char.RegisterVar("wetness", {
	field = "wetness",
	fieldType = ix.type.number,
	default = 0,
	isLocal = true,
	bNoDisplay = true
})

ix.config.Add("exposureEnabled", true, "Whether characters get cold, hot and wet. Off puts everyone back to comfortable and dry.", function(oldValue, newValue)
	if (SERVER) then
		PLUGIN:OnEnabledChanged(newValue)
	end
end, {category = "Exposure"})

ix.config.Add("exposureTickTime", 5, "Seconds between body temperature and wetness updates.", function(oldValue, newValue)
	if (SERVER) then
		PLUGIN:StartTimer()
	end
end, {data = {min = 1, max = 60}, category = "Exposure"})

ix.config.Add("exposureAdjustTime", 20, "Minutes the body takes to go from comfortable to the worst cold or heat. Recovering is faster.", nil, {
	data = {min = 1, max = 240},
	category = "Exposure"
})

ix.config.Add("exposureDamage", 1, "Damage per tick while hypothermic or in heatstroke. 0 disables it.", nil, {
	data = {min = 0, max = 50},
	category = "Exposure"
})

ix.config.Add("exposureLethal", false, "Whether exposure alone can kill. When off it never takes a player below a little health.", nil, {
	category = "Exposure"
})

--- Every number of the model, in one place. Temperatures are °C, rates per minute unless said otherwise.
ix.exposure.tuning = {
	-- unclothed, a body is comfortable between these air temperatures
	comfortLow = 18,
	comfortHigh = 26,
	-- in heat, clothing counts against the wearer at this share of its warmth
	heatClothingShare = 0.5,
	-- degrees of stress beyond the band that make the target ±100
	stressFull = 12,
	-- felt degrees removed per unit of wind (0..1) outdoors
	windChill = 4,
	-- felt degrees removed at full wetness: in cold air (at or under wetColdAir) and in warm air (at or over wetWarmAir)
	wetChillCold = 3,
	wetChillWarm = 1.5,
	wetColdAir = 10,
	wetWarmAir = 25,
	-- felt degrees added while sprinting
	exertion = 3,
	-- the most warmth all heat sources together can add
	heatMax = 30,
	-- moving back toward comfortable is this many times faster than moving away; next to a heat source, warmup
	recovery = 2.5,
	warmup = 4,
	-- wetness points per minute at full precipitation with no protection
	wetRate = 12,
	-- drying, points per minute: always, extra under cover, per °C of air above dryWarmFrom, per unit of wind
	-- outdoors, per degree of heat from a source
	dryBase = 1.5,
	dryIndoors = 3,
	dryWarmFrom = 10,
	dryPerDegree = 0.25,
	dryWind = 2,
	dryPerHeat = 0.6,
	-- a head item adds this share of its rain protection on top of the best body or outer garment
	headShare = 0.2,
	-- wading: the wetness a water level brings at least (1 feet, 2 waist, 3 under)
	wading = {[1] = 25, [2] = 80, [3] = 100},
	-- wetness from which the body is "soaked" (and clothes wear), and under which it has dried off again
	soaked = 60,
	damp = 25,
	dry = 20,
	-- condition points per hour every worn item that is not waterproof loses while soaked
	soakedWearPerHour = 3,
	soakedWearUntil = 0.5, -- items at least this waterproof do not wear from being soaked
	-- boots wear this much faster per unit of precipitation on the wearer
	rainBootWear = 0.5,
	-- at "freezing", speed is scaled from the first to the second value as temperature goes to -100
	slowdown = {0.9, 0.75},
	-- extra thirst drain, as a share of the normal drain, at hot, overheating and heatstroke
	heatThirst = {[2] = 0.5, [3] = 1, [4] = 1.5},
	-- stamina per second while moving, at overheating and heatstroke
	heatStamina = {[3] = 3, [4] = 5},
	-- stamina regeneration multiplier by signed temperature level (hot, overheating/freezing, heatstroke/hypothermic)
	staminaRegenScale = {[-4] = 0.30, [-3] = 0.50, [2] = 0.70, [3] = 0.50, [4] = 0.30},
	-- exposure alone never takes health below this while exposureLethal is off
	healthFloor = 10,
	-- seconds at "cold" or worse before coughing, and seconds between coughs
	coughAfter = 60,
	coughInterval = {20, 60},
	-- air at or under this makes breath visible
	breathBelow = 5
}

-- Levels by how far temperature is from 0: index 1..4 are the four words, cold (negative) or heat (positive).
-- The signed level is -4..4, 0 comfortable.
ix.exposure.LEVELS = {25, 50, 75, 92}
ix.exposure.COLD_WORDS = {"chilly", "cold", "freezing", "hypothermic"}
ix.exposure.HEAT_WORDS = {"warm", "hot", "overheating", "heatstroke"}

ix.exposure.coughSounds = {
	"ambient/voices/cough1.wav",
	"ambient/voices/cough2.wav",
	"ambient/voices/cough3.wav",
	"ambient/voices/cough4.wav"
}

--- The signed level (-4..4) for a temperature.
function ix.exposure.GetLevel(temperature)
	local magnitude = math.abs(temperature or 0)
	local level = 0

	for index, threshold in ipairs(ix.exposure.LEVELS) do
		if (magnitude >= threshold) then
			level = index
		end
	end

	-- never -0: the level is concatenated into phrase names
	if (level == 0) then
		return 0
	end

	return temperature < 0 and -level or level
end

--- The word for a signed level ("comfortable", "chilly" .. "heatstroke").
function ix.exposure.GetLevelWord(level)
	if (level < 0) then
		return ix.exposure.COLD_WORDS[-level]
	elseif (level > 0) then
		return ix.exposure.HEAT_WORDS[level]
	end

	return "comfortable"
end

--- The faction table of a player's character, or nil.
function ix.exposure.GetFaction(client)
	local character = IsValid(client) and client:GetCharacter()

	return character and ix.faction.indices[character:GetFaction()] or nil
end

--- Whether the player's faction wears a climate-sealed suit and so stays out of the system.
function ix.exposure.IsSealed(client)
	local faction = ix.exposure.GetFaction(client)

	return faction != nil and faction.bClimateSealed == true
end

--- Whether the system applies to the player now: enabled, alive with a character, not in noclip or observing,
-- not climate-sealed.
function ix.exposure.Applies(client)
	if (!ix.config.Get("exposureEnabled", true) or !IsValid(client) or !client:GetCharacter() or !client:Alive()) then
		return false
	end

	if (client:GetMoveType() == MOVETYPE_NOCLIP or client:GetObserverMode() != OBS_MODE_NONE) then
		return false
	end

	return !ix.exposure.IsSealed(client)
end

--- The speed multiplier for a temperature: 1 above "freezing", then down to tuning.slowdown[2] at -100.
function ix.exposure.GetSpeedScale(temperature)
	local freezing = ix.exposure.LEVELS[3]

	if (!temperature or temperature > -freezing) then
		return 1
	end

	local fraction = math.Clamp((-temperature - freezing) / (100 - freezing), 0, 1)
	local slowdown = ix.exposure.tuning.slowdown

	return Lerp(fraction, slowdown[1], slowdown[2])
end

--- Stamina regeneration multiplier for a temperature: 1 when comfortable or mild, lower when hot,
-- overheating, freezing, hypothermic or in heatstroke.
function ix.exposure.GetStaminaRegenScale(temperature)
	if (!isnumber(temperature)) then
		return 1
	end

	local level = ix.exposure.GetLevel(temperature)

	return ix.exposure.tuning.staminaRegenScale[level] or 1
end

--- Registers a heat source by entity class: radius (units), heat (°C at its centre, falling off linearly to
-- nothing at the radius) and IsActive(entity) (optional; without it the entity always counts). Registering
-- a class again replaces it; nil removes it.
function ix.exposure.RegisterHeatSource(class, info)
	if (info == nil) then
		ix.exposure.heatSources[class] = nil
		return
	end

	ix.exposure.heatSources[class] = {
		radius = tonumber(info.radius) or 200,
		heat = tonumber(info.heat) or 10,
		IsActive = info.IsActive
	}
end

-- Shared so the client predicts the same speed. Scales and never returns, so other SetupMove users
-- (the stamina plugin's exhausted walk) still run.
function PLUGIN:SetupMove(client, moveData)
	if (!ix.exposure.Applies(client)) then
		return
	end

	local scale = ix.exposure.GetSpeedScale(client:GetCharacter():GetTemperature())

	if (scale < 1) then
		moveData:SetMaxClientSpeed(moveData:GetMaxClientSpeed() * scale)
		moveData:SetMaxSpeed(moveData:GetMaxSpeed() * scale)
	end
end

ix.util.Include("sv_plugin.lua")
ix.util.Include("cl_plugin.lua")

-- Built-in heat sources. A smelter's station class is added at InitializedPlugins (sv_plugin.lua).
ix.exposure.RegisterHeatSource("env_fire", {
	radius = 256,
	heat = 20,
	IsActive = function(entity)
		local enabled = entity:GetInternalVariable("m_bEnabled")

		return enabled == nil or enabled == true
	end
})

local function SetCommand(name, setter, low, high, phrase)
	ix.command.Add(name, {
		description = "@cmd" .. name,
		privilege = "Manage Character Attributes",
		adminOnly = true,
		arguments = {
			ix.type.character,
			ix.type.number
		},
		OnRun = function(self, client, target, value)
			local amount = math.Clamp(math.Round(value), low, high)
			target[setter](target, amount)

			local targetClient = target:GetPlayer()

			if (IsValid(targetClient)) then
				PLUGIN:ResetTracking(targetClient)
			end

			for _, v in ipairs(player.GetAll()) do
				if (self:OnCheckAccess(v) or v == targetClient) then
					v:NotifyLocalized(phrase, client:GetName(), target:GetName(), amount)
				end
			end
		end
	})
end

SetCommand("CharSetTemperature", "SetTemperature", -100, 100, "exposureSetTemperature")
SetCommand("CharSetWetness", "SetWetness", 0, 100, "exposureSetWetness")
