local pad = ix.datapad

local function HealthWord(hp, hasOpenWound, hasAnyWound)
	if (hp < 0.20) then
		return "Barely standing"
	elseif (hp < 0.40) then
		return "Badly hurt"
	elseif (hp < 0.65) then
		return "Hurting"
	elseif (hp < 0.90) then
		return "Sore"
	elseif (hasOpenWound) then
		return "Wounded"
	elseif (hasAnyWound) then
		return "Recovering"
	end

	return "Steady"
end

local function BreathingWord(stamina, exhausted, carryBand, speed)
	if (exhausted or stamina < 15) then
		return "Gasping"
	elseif (stamina < 35) then
		return "Winded"
	elseif (stamina < 60 or (carryBand >= 3 and speed > 40)) then
		return "Laboured"
	end

	return "Even"
end

local function ThirstWord(thirst)
	if (thirst < 20) then
		return "Parched"
	elseif (thirst < 40) then
		return "Thirsty"
	elseif (thirst < 70) then
		return "Dry"
	end

	return "Sufficient"
end

local function HungerWord(hunger)
	if (hunger < 20) then
		return "Starving"
	elseif (hunger < 40) then
		return "Hungry"
	elseif (hunger < 70) then
		return "Peckish"
	end

	return "Sated"
end

-- Reads only what the viewer could actually tell about `client`:
-- - Ordinary self-inspection: qualitative self-felt impressions and dressing location.
-- - Frisking an ordinary subject: externally observable signs only (no hidden hunger/thirst/HP).
-- - Sealed Combine suit (`ix.body.HasBiomonitor`): real biomedical telemetry.
function pad.ReadBody(client, viewer)
	if (!IsValid(client)) then
		return {}
	end

	local char = client:GetCharacter()

	if (!char) then
		return {}
	end

	local isSelf = (!IsValid(viewer) or viewer == client)
	local biomonitor = ix.body and isfunction(ix.body.HasBiomonitor) and ix.body.HasBiomonitor(client) or false
	local observableOnly = (!isSelf and !biomonitor)

	local hp = client:Health() / math.max(client:GetMaxHealth(), 1)
	local stamina = client:GetLocalVar("stm", 100)
	local exhausted = client:GetNetVar("brth", false)
	local carryBand = math.max(client:GetLocalVar("carryBand", 1), client:GetNetVar("carryBand", 1))
	local speed = client:GetVelocity():Length2D()

	local wetnessRaw = char.GetWetness and char:GetWetness() or client:WaterLevel() * 33
	local soakedAt = ix.exposure and ix.exposure.tuning and ix.exposure.tuning.soaked or 60
	local dampAt = ix.exposure and ix.exposure.tuning and ix.exposure.tuning.damp or 25
	local clothingWord = wetnessRaw >= soakedAt and "Soaked" or wetnessRaw >= dampAt and "Damp" or "Dry"
	local coarseWetness = clothingWord == "Soaked" and 80 or (clothingWord == "Damp" and 35 or 0)

	local rawWounds = ix.body and ix.body.GetWounds and ix.body.GetWounds(client) or {}
	local wounds = {}
	local hasOpenWound, hasAnyWound = false, false
	local openWoundCount = 0

	for region, w in pairs(rawWounds) do
		if (istable(w)) then
			hasAnyWound = true

			if (w.state == "open") then
				hasOpenWound = true
				openWoundCount = openWoundCount + 1
			end

			wounds[region] = {
				kind = w.kind,
				region = region,
				state = w.state,
				severityWord = ix.body and ix.body.GetWoundSeverityWord and ix.body.GetWoundSeverityWord(w.severity) or "minor",
				severity = biomonitor and math.Round(tonumber(w.severity) or 0) or nil
			}
		end
	end

	local effects = client:GetNetVar("bodyWoundEffects")
	local limping = istable(effects) and isnumber(effects.legs) and effects.legs > 0 or false
	local armInjured = istable(effects) and isnumber(effects.arms) and effects.arms > 0 or false
	local shivering = client:GetNetVar("ixShivering") == true
	local mark = hp < 1 and client:GetNetVar("datapadHit") or nil

	if (observableOnly) then
		local audiblyWinded = exhausted or stamina < 35
			or (pad.ShouldEmitHeavyBreath and pad.ShouldEmitHeavyBreath(carryBand, stamina, speed))

		return {
			biomonitor = false,
			observableOnly = true,
			wounds = wounds,
			mark = mark,
			clothingWord = clothingWord,
			wetness = coarseWetness,
			shivering = shivering,
			cold = shivering,
			limping = limping,
			armInjured = armInjured,
			breathingWord = audiblyWinded and BreathingWord(stamina, exhausted, carryBand, speed) or nil
		}
	end

	local dressingInfo

	if (isSelf and ix.body and isfunction(ix.body.FindDressing)) then
		local dressing = ix.body.FindDressing(client)

		if (dressing) then
			dressingInfo = {
				placeName = dressing.placeName,
				accessTime = dressing.accessTime or 0
			}
		end
	end

	local body = {
		biomonitor = biomonitor,
		observableOnly = false,
		healthWord = HealthWord(hp, hasOpenWound, hasAnyWound),
		breathingWord = BreathingWord(stamina, exhausted, carryBand, speed),
		clothingWord = clothingWord,
		wetness = math.Round(wetnessRaw),
		shivering = shivering,
		limping = limping,
		armInjured = armInjured,
		mark = mark,
		wounds = wounds,
		dressing = dressingInfo
	}

	if (ix.exposure and char.GetTemperature) then
		local level = ix.exposure.GetLevel(char:GetTemperature())
		local tempWord = ix.exposure.GetLevelWord(level)

		body.temperature = tempWord
		body.temperatureWord = tempWord
		body.cold = level < 0
		body.hot = level > 0
	end

	if (ix.config.Get("hungerthirstEnabled", false) and char.GetThirst) then
		local thirstVal = char:GetThirst()
		local hungerVal = char:GetHunger()

		body.thirstWord = ThirstWord(thirstVal)
		body.hungerWord = HungerWord(hungerVal)
		body.thirsty = thirstVal < 40
		body.hungry = hungerVal < 40
	end

	if (biomonitor) then
		local pulse = 68 + (100 - math.Clamp(stamina, 0, 100)) * 0.45 + (1 - math.Clamp(hp, 0, 1)) * 45 + openWoundCount * 18
		local coreTemp = math.Round((37.0 - (1 - math.Clamp(hp, 0, 1)) * 0.4 + (100 - math.Clamp(stamina, 0, 100)) * 0.004) * 10) / 10

		body.biometrics = {
			vitality = math.Round(math.Clamp(hp, 0, 1) * 100),
			pulse = math.Clamp(math.Round(pulse), 64, 160),
			oxygen = math.Round(math.Clamp(stamina, 0, 100)),
			coreTemp = coreTemp,
			suitSeal = hasOpenWound and "BREACHED" or "SEALED"
		}
	end

	return body
end
