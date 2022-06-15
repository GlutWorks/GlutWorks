

local PLUGIN = PLUGIN

PLUGIN.name = "Survival Additions"
PLUGIN.author = "firehellrain, Oebelysk"
PLUGIN.description = "Adaptation of Clockwork Primary Needs plugin to Helix by firehellrain. Modified and localized by Oebelysk."
--[[ Declaration of Variables ]]--

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

--[[ Configurations ]]--

-- [[ Settings ]] --

ix.config.Add ("hungerthirstEnabled", false, "Toggle hunger and thirst system.", function (oldValue, newValue)
	if (newValue) then
		hook.Run ("HungerEnabled")
	else
		hook.Run ("HungerDisabled")
	end
end, {category = "Hunger and Thirst"})

ix.config.Add ("hungerDamage", 2, "Determines how much damage a player takes per tick if starving.", nil, {
	data = {min = 0, max = 100},
	category = "Hunger and Thirst"
})

ix.config.Add ("hungerLossTime", 5, "Determines how many minutes it takes a player to start starving.", nil, {
	data = {min = 0.1, max = 1440, decimals = 1},
	category = "Hunger and Thirst"
})

ix.config.Add ("hungerTickTime", 5, "Determines how much time passes between each check. Use the LossTime command instead.", function (oldValue, newValue)
	if (SERVER) then
		PLUGIN: SetupAllTimers ()
	end
end, {data = {min = 1, max = 60}, category = "Hunger and Thirst"})

ix.config.Add ("thirstDamage", 2, "Determines how much damage a player takes per tick if dehydrated.", nil, {
	data = {min = 0, max = 100},
	category = "Hunger and Thirst"
})

ix.config.Add ("thirstLossTime", 5, "Determines how many minutes it takes a player to become dehydrated.", nil, {
	data = {min = 0.1, max = 1440, decimals = 1},
	category = "Hunger and Thirst"
})

ix.config.Add ("thirstTickTime", 5, "Determines how much time passes between each check. Use the LossTime command instead.", function (oldValue, newValue)
	if (SERVER) then
		PLUGIN: SetupAllTimers ()
	end
end, {data = {min = 1, max = 60}, category = "Hunger and Thirst"})

function PLUGIN:CharacterLoaded(character)
    if (ix.config.Get("hungerthirstEnabled")) then
        hook.Run("HungerEnabled")
    else
        hook.Run("HungerDisabled")
    end
end

function PLUGIN:OnReloaded()
	if (ix.config.Get("hungerthirstEnabled")) then
		hook.Run("HungerEnabled")
	else
		hook.Run("HungerDisabled")
	end
end


ix.util.Include("cl_hooks.lua")
ix.util.Include("sv_hooks.lua")

--[[ Commands ]]--

ix.command.Add("CharSetHunger", {
	description = "Adjusts a player's hunger.",
	privilege = "Manage Character Attributes",
	adminOnly = true,
	arguments = {
		ix.type.character,
		ix.type.number
	},
	OnRun = function(self, client, target, hunger)
		local amount = math.Clamp(math.Round(hunger), 1, 100)
		target:SetHunger(amount)
		
		for _, v in ipairs(player.GetAll()) do
			if (self:OnCheckAccess(v) or v == ply) then
				v:NotifyLocalized("setHunger", client:GetName(), target:GetName(), hunger)
			end
		end
	end
})

ix.command.Add("CharSetThirst", {
	description = "Adjusts a player's thirst.",
	privilege = "Manage Character Attributes",
	adminOnly = true,
	arguments = {
		ix.type.character,
		ix.type.number
	},
	OnRun = function(self, client, target, thirst)
		local amount = math.Clamp(math.Round(thirst), 1, 100)
		target:SetThirst(amount)
		
		for _, v in ipairs(player.GetAll()) do
			if (self:OnCheckAccess(v) or v == ply) then
				v:NotifyLocalized("setThirst", client:GetName(), target:GetName(), thirst)
			end
		end
	end
})

