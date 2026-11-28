STATION.name = "Smelter"
STATION.description = "A conventional smeltery."
STATION.model = Model("models/props_forest/furnace01.mdl")

-- Makes this station a smelter (ix.smelting in the glutcraft plugin): seconds per operation, and how
-- much fuel (operations), queued input (operations) and finished output (kg) it holds at once.
STATION.smelting = {time = 10, fuel = 20, input = 20, output = 20,
	-- where the glow and the smoke come from, as fractions of the model's bounds (glutcraft's cl_smelting.lua):
	-- this model's stack stands to one side
	effects = {chimney = Vector(0.4, 0.75, 1)}}
