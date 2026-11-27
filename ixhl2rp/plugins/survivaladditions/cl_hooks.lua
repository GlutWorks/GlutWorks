
local PLUGIN = PLUGIN

local function GetLevelText(levels, amount, fallback)
	local _, phrase = PLUGIN:GetNeedLevel(levels, amount)

	return L(phrase or fallback)
end

function PLUGIN:GetHungerText(amount)
	return GetLevelText(PLUGIN.hungerLevels, amount, "hungerDeath")
end

function PLUGIN:GetThirstText(amount)
	return GetLevelText(PLUGIN.thirstLevels, amount, "thirstDeath")
end

-- A bar whose value is false is hidden, so the bars follow the config without being re-added.
local function NeedBar(getter, textFunction)
	return function()
		local character = LocalPlayer():GetCharacter()

		if (!character or !ix.config.Get("hungerthirstEnabled", false)) then
			return false
		end

		local amount = character[getter](character)

		return amount / 100, PLUGIN[textFunction](PLUGIN, amount)
	end
end

ix.bar.Add(NeedBar("GetHunger", "GetHungerText"), Color(241, 117, 15), nil, "hunger")
ix.bar.Add(NeedBar("GetThirst", "GetThirstText"), Color(15, 169, 241), nil, "thirst")
