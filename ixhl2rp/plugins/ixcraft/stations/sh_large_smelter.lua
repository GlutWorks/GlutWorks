STATION.name = "Large Smelter"
STATION.description = "This is quite a large smelter. You can smelt a lot with this."
STATION.model = Model("models/props_mining/oiltank01.mdl")

-- See sh_smelter.lua.
STATION.smelting = {time = 6, fuel = 60, input = 60, output = 60,
	-- the fire glows in the outlet under the tank (fractions of the model's bounds; see glutcraft's cl_smelting.lua)
	effects = {mouth = Vector(0.72, 0.5, 0.2)}}
