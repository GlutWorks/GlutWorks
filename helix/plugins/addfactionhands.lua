local PLUGIN = PLUGIN

PLUGIN.name = "Additional Faction Viewmodel Hands"
PLUGIN.author = "Oebelysk"
PLUGIN.description = "Adds hands viewmodels for additional models."

player_manager.AddValidModel( "nemezpolice", "models/police_nemez.mdl" )
player_manager.AddValidHands( "nemezpolice", "models/weapons/c_arms_combine.mdl", 0, "0000000" )