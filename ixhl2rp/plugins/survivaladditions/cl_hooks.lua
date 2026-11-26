
local PLUGIN = PLUGIN

local hungerLevels = {
	{80, "hungerHealthy"},
	{70, "hungerSnack"},
	{50, "hungerHungry"},
	{30, "hungerStarving"}
}

local thirstLevels = {
	{80, "thirstHealthy"},
	{70, "thirstBit"},
	{50, "thirstThirsty"},
	{30, "thirstDehydrated"}
}

local function GetLevelText(levels, amount, fallback)
	for _, v in ipairs(levels) do
		if (amount > v[1]) then
			return L(v[2])
		end
	end

	return L(fallback)
end

function PLUGIN:GetHungerText(amount)
	return GetLevelText(hungerLevels, amount, "hungerDeath")
end

function PLUGIN:GetThirstText(amount)
	return GetLevelText(thirstLevels, amount, "thirstDeath")
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
