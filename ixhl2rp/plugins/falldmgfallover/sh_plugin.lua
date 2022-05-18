
local PLUGIN = PLUGIN

PLUGIN.name = "Fallover After Fall Damage"
PLUGIN.description = "Causes characters to fall over after taking fall damage."
PLUGIN.author = "Oebelysk"

ix.config.Add("falloverAfterFallDamage", true, "Whether or not players fallover after taking fall damage.", nil, {
	category = "Fallover After Fall Damage"
})

ix.util.Include("sv_plugin.lua")

