
PLUGIN.name = "Additional Faction Viewmodel Hands"
PLUGIN.author = "Oebelysk"
PLUGIN.description = "Adds viewmodel hands for faction models that do not register their own."

player_manager.AddValidModel("nemezpolice", "models/police_nemez.mdl")
player_manager.AddValidHands("nemezpolice", "models/weapons/c_arms_combine.mdl", 0, "0000000")
