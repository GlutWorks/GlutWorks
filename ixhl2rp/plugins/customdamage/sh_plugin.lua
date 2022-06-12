
local PLUGIN = PLUGIN

PLUGIN.name = "Fallover After Fall Damage"
PLUGIN.description = "Causes characters to fall over after taking fall damage."
PLUGIN.author = "Oebelysk"

ix.config.Add("falloverAfterFallDamage", true, "Whether or not players fall over after taking fall damage.", nil, {
	category = "Fallover After Fall Damage"
})

ix.config.Add("fallDamageBaseTime", 5, "The base time it takes characters to get up after taking fall damage. Time to get up = BaseTime + TimeMultiplier * dmg.", nil, {
	category = "Fallover After Fall Damage",
	data = { min = 0, max = 30 }
})

ix.config.Add("fallDamageTimeMultiplier", 0.1, "The additional time it takes characters to get up after taking fall damage, dependent on damage. Time to get up = BaseTime + TimeMultiplier * dmg.", nil, {
	category = "Fallover After Fall Damage",
	data = { min = 0, max = 2, decimals = 1 }
})

ix.util.Include("sv_plugin.lua")

