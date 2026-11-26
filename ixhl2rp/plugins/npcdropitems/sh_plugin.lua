local PLUGIN = PLUGIN

PLUGIN.name = "NPC Drop Items"
PLUGIN.description = "Makes certain NPCs drop items."
PLUGIN.author = "Oebelysk"

-- NPC class -> list of {item ID, chance}. Each entry rolls on its own.
PLUGIN.drops = {
	["npc_headcrab"] = {
		{"headcrab_meat_chunk", 1 / 3}
	},
	["npc_headcrab_black"] = {
		{"poison_headcrab_gland", 0.25}
	},
	["npc_antlion"] = {
		{"antlion_meat_chunk", 0.25}
	},
	-- the headcrab riding a zombie, and what is left of the host's clothes
	["npc_zombie"] = {
		{"headcrab_meat_chunk", 0.25},
		{"fabric1_junk", 0.2}
	}
}

ix.util.Include("sv_plugin.lua")
