
local PLUGIN = PLUGIN

PLUGIN.name = "Glut Scavenging"
PLUGIN.description = "Scavenging plugin for Glut"
PLUGIN.author = "PhiYerion"

ix.config.Add("scavengeRespawnTime", 1800, "Seconds before a scavenged prop can be scavenged again.", nil, {
	data = {min = 0, max = 86400},
	category = "Scavenging"
})

ix.config.Add("scavengeRichnessFloor", 0.25, "Richness (0-1) below which a scavenge prop stays depleted until it regrows past this.", nil, {
	data = {min = 0, max = 1, decimals = 2},
	category = "Scavenging"
})

ix.config.Add("scavengeRichnessRegen", 3600, "Seconds for a scavenge prop's richness to regrow from empty to full.", nil, {
	data = {min = 1, max = 604800},
	category = "Scavenging"
})

ix.util.Include("sv_hooks.lua")
