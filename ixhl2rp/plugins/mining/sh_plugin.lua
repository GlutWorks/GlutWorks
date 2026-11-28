local PLUGIN = PLUGIN

PLUGIN.name = "Mining Additions"
PLUGIN.author = "Oebelysk"
PLUGIN.description = "Introduces a mining system that allows players to break down ore nodes for materials."

ix.config.Add("oreNodeRespawnTime", 1800, "Seconds before a mined-out ore node grows back.", nil, {
	data = {min = 0, max = 86400},
	category = "Mining"
})

ix.config.Add("oreRichnessFloor", 0.25, "Richness (0-1) below which an ore node stays depleted until it regrows past this.", nil, {
	data = {min = 0, max = 1, decimals = 2},
	category = "Mining"
})

ix.config.Add("oreRichnessRegen", 7200, "Seconds for an ore node's richness to regrow from empty to full.", nil, {
	data = {min = 1, max = 604800},
	category = "Mining"
})

ix.util.Include("sv_hooks.lua")
