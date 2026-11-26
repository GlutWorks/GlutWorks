
local PLUGIN = PLUGIN

PLUGIN.name = "Knockdown"
PLUGIN.description = "Knocks characters down after a bad fall and leaves them unconscious for a while when badly hurt."
PLUGIN.author = "Oebelysk"

ix.config.Add("falloverAfterFallDamage", true, "Whether or not players fall over after taking fall damage.", nil, {
	category = "Knockdown"
})

ix.config.Add("fallDamageBaseTime", 5, "The base time it takes characters to get up after taking fall damage. Time to get up = BaseTime + TimeMultiplier * dmg.", nil, {
	category = "Knockdown",
	data = {min = 0, max = 30}
})

ix.config.Add("fallDamageTimeMultiplier", 0.1, "The additional time it takes characters to get up after taking fall damage, dependent on damage. Time to get up = BaseTime + TimeMultiplier * dmg.", nil, {
	category = "Knockdown",
	data = {min = 0, max = 2, decimals = 1}
})

ix.config.Add("unconsciousHealth", 20, "A hit that leaves a character alive with less health than this knocks them unconscious. 0 disables it.", nil, {
	category = "Knockdown",
	data = {min = 0, max = 100}
})

ix.config.Add("unconsciousTime", 100, "How many seconds a character stays unconscious.", nil, {
	category = "Knockdown",
	data = {min = 1, max = 600}
})

ix.util.Include("sv_plugin.lua")
