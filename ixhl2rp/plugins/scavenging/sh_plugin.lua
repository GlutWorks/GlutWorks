
local PLUGIN = PLUGIN

PLUGIN.name = "Glut Scavenging"
PLUGIN.description = "Scavenging plugin for Glut"
PLUGIN.author = "PhiYerion"

ix.config.Add("scavengeRespawnTime", 1800, "Seconds before a scavenged prop can be scavenged again.", nil, {
	data = {min = 0, max = 86400},
	category = "Scavenging"
})

ix.util.Include("sv_hooks.lua")
