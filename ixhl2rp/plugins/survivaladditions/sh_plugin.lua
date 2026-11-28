
local PLUGIN = PLUGIN

PLUGIN.name = "Survival Additions"
PLUGIN.author = "firehellrain, Oebelysk"
PLUGIN.description = "Hunger and thirst, and the food and drink that restore them."

ix.char.RegisterVar("hunger", {
	field = "hunger",
	fieldType = ix.type.number,
	default = 100,
	isLocal = true,
	bNoDisplay = true
})

ix.char.RegisterVar("thirst", {
	field = "thirst",
	fieldType = ix.type.number,
	default = 100,
	isLocal = true,
	bNoDisplay = true
})

ix.config.Add("hungerthirstEnabled", false, "Toggle hunger and thirst system.", function(oldValue, newValue)
	if (SERVER) then
		PLUGIN:SetupAllTimers()
	end
end, {category = "Hunger and Thirst"})

ix.config.Add("hungerLossTime", 120, "How many minutes it takes a full hunger bar to drain to zero.", nil, {
	data = {min = 1, max = 1440},
	category = "Hunger and Thirst"
})

ix.config.Add("thirstLossTime", 90, "How many minutes it takes a full thirst bar to drain to zero.", nil, {
	data = {min = 1, max = 1440},
	category = "Hunger and Thirst"
})

ix.config.Add("hungerDamage", 2, "Damage taken per tick while hunger is at zero. 0 disables starvation damage.", nil, {
	data = {min = 0, max = 100},
	category = "Hunger and Thirst"
})

ix.config.Add("thirstDamage", 2, "Damage taken per tick while thirst is at zero. 0 disables dehydration damage.", nil, {
	data = {min = 0, max = 100},
	category = "Hunger and Thirst"
})

ix.config.Add("needsTickTime", 5, "Seconds between hunger and thirst updates.", function(oldValue, newValue)
	if (SERVER) then
		PLUGIN:SetupAllTimers()
	end
end, {data = {min = 1, max = 60}, category = "Hunger and Thirst"})

ix.config.Add("needsLowThreshold", 25, "Below this much hunger or thirst, stamina regenerates more slowly.", nil, {
	data = {min = 0, max = 100},
	category = "Hunger and Thirst"
})

ix.config.Add("needsLowStaminaScale", 0.75, "Fraction of normal stamina regeneration while hunger or thirst is low.", nil, {
	data = {min = 0, max = 1, decimals = 2},
	category = "Hunger and Thirst"
})

ix.config.Add("needsRespawnLevel", 50, "Hunger and thirst a character respawns with after dying.", nil, {
	data = {min = 1, max = 100},
	category = "Hunger and Thirst"
})

-- Severity steps for hunger and thirst, best first: above the amount, the phrase applies. Below
-- the last step is the final level. Shared so the immersion plugin's body feedback and /Feel use
-- the same steps as the bars.
PLUGIN.hungerLevels = {
	{80, "hungerHealthy"},
	{70, "hungerSnack"},
	{50, "hungerHungry"},
	{30, "hungerStarving"}
}

PLUGIN.thirstLevels = {
	{80, "thirstHealthy"},
	{70, "thirstBit"},
	{50, "thirstThirsty"},
	{30, "thirstDehydrated"}
}

--- Returns the 1-based step `amount` falls in (1 is best, #levels + 1 is the final level below
-- the last step) and that step's phrase (nil for the final level).
function PLUGIN:GetNeedLevel(levels, amount)
	for k, v in ipairs(levels) do
		if (amount > v[1]) then
			return k, v[2]
		end
	end

	return #levels + 1
end

--- How bad a need is, 0 to 1: 0 above the third step (Hungry/Thirsty), half at the last step,
-- and rising to 1 at zero.
function PLUGIN:GetNeedSeverity(levels, amount)
	local start, worst = levels[3][1], levels[4][1]

	if (amount >= start) then
		return 0
	elseif (amount >= worst) then
		return 0.5 * (start - amount) / (start - worst)
	end

	return 0.5 + 0.5 * (worst - math.max(amount, 0)) / worst
end

function PLUGIN:IsLow(character)
	local threshold = ix.config.Get("needsLowThreshold", 25)

	return character:GetHunger() < threshold or character:GetThirst() < threshold
end

-- Shared so the client's stamina prediction matches the server.
function PLUGIN:AdjustStaminaOffset(client, offset)
	if (offset <= 0 or !ix.config.Get("hungerthirstEnabled", false)) then
		return
	end

	local character = client:GetCharacter()

	if (character and self:IsLow(character)) then
		return offset * ix.config.Get("needsLowStaminaScale", 0.75)
	end
end

ix.util.Include("cl_hooks.lua")
ix.util.Include("sv_hooks.lua")

local function SetNeedCommand(name, setter, noun, phrase)
	ix.command.Add(name, {
		description = "Sets a character's " .. noun .. " (0-100).",
		privilege = "Manage Character Attributes",
		adminOnly = true,
		arguments = {
			ix.type.character,
			ix.type.number
		},
		OnRun = function(self, client, target, value)
			local amount = math.Clamp(math.Round(value), 0, 100)
			target[setter](target, amount)

			for _, v in ipairs(player.GetAll()) do
				if (self:OnCheckAccess(v) or v == target:GetPlayer()) then
					v:NotifyLocalized(phrase, client:GetName(), target:GetName(), amount)
				end
			end
		end
	})
end

SetNeedCommand("CharSetHunger", "SetHunger", "hunger", "setHunger")
SetNeedCommand("CharSetThirst", "SetThirst", "thirst", "setThirst")
