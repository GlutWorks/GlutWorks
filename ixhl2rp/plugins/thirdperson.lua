
-- Extends the bundled third person plugin (helix/plugins/thirdperson.lua, which shares this
-- uniqueID): third person is allowed by default, and each player's thirdpersonEnabled option is
-- networked so server code (kickdoor) can read it with ix.option.Get(client, "thirdpersonEnabled").

-- The bundled plugin registered the config as off, and re-adding a config keeps the first default,
-- so change the stored entry. Saved values are applied over this later by ix.config.Load.
local config = ix.config.stored["thirdperson"]

if (config) then
	if (config.value == config.default) then
		config.value = true
	end

	config.default = true
end

-- Registered in both realms with bNetworked so the server knows the option and receives its value.
-- On the client this replaces the bundled registration, so it repeats the hidden and OnChanged fields.
ix.option.Add("thirdpersonEnabled", ix.type.bool, false, {
	category = "thirdperson",
	bNetworked = true,
	hidden = function()
		return !ix.config.Get("thirdperson")
	end,
	OnChanged = function(oldValue, value)
		hook.Run("ThirdPersonToggled", oldValue, value)
	end
})
