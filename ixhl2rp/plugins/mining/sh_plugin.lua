local PLUGIN = PLUGIN

PLUGIN.name = "Mining Additions"
PLUGIN.author = "Oebelysk"
PLUGIN.description = "Introduces a mining system that allows players to break down ore nodes for materials."

ix.config.Add("oreNodeRespawnTime", 1800, "Seconds before a mined-out ore node grows back.", nil, {
	data = {min = 0, max = 86400},
	category = "Mining"
})

ix.util.Include("sv_hooks.lua")
