
PLUGIN.name = "UI Fonts"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Uses Times New Roman for the Helix title font."

-- Plugins load before the framework config file adds "font", so this becomes its default.
-- Admins can still change it in the config menu.
ix.config.SetDefault("font", "Times New Roman")
