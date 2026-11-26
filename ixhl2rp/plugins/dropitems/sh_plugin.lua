
local PLUGIN = PLUGIN

PLUGIN.name = "Drop Weapons on Death"
PLUGIN.description = "Drops a dying character's equipped weapons on the ground."
PLUGIN.author = "pedro.santos53"

ix.config.Add("dropWeaponOnDeath", true, "Whether or not players drop their equipped weapons on death.", nil, {
	category = "Death"
})

ix.util.Include("sv_plugin.lua")
