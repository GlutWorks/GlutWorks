local pad = ix.datapad

-- This is a reading of the character at the time of inspection. Only existing conditions are shown.
function pad.ReadBody(client)
	local char = client:GetCharacter()
	local hp = client:Health() / math.max(client:GetMaxHealth(), 1)
	local wetness = char.GetWetness and char:GetWetness() or client:WaterLevel() * 33
	local body = {
		health = math.Round(hp * 100), stamina = math.Round(client:GetLocalVar("stm", 100)),
		wetness = math.Round(wetness), mark = hp < 1 and client:GetNetVar("datapadHit") or nil
	}
	if (ix.exposure and char.GetTemperature) then
		local level = ix.exposure.GetLevel(char:GetTemperature())
		body.temperature = ix.exposure.GetLevelWord(level)
		body.cold = level < 0
		body.hot = level > 0
	end
	if (ix.config.Get("hungerthirstEnabled", false) and char.GetThirst) then
		body.thirst = math.Round(char:GetThirst())
		body.hunger = math.Round(char:GetHunger())
	end
	return body
end
