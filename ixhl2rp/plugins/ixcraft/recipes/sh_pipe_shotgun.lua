
RECIPE.name = "Pipe Shotgun"
RECIPE.description = "Craft a pipe shotgun."
RECIPE.model = "models/weapons/darky_m/rust/w_waterpipe.mdl"
RECIPE.category = "Salvaged Weapons"
RECIPE.requirements = {
	["metal_scrap"] = 2,
	["wooden_scrap"] = 1,
	["pipe"] = 1,
	["box_of_gear"] = 2,
	["box_of_screw"] = 1,
	["duct_tape"] = 1
}
RECIPE.interchangeable_req = {

}

RECIPE.results = {
	["waterpipe"] = 1
}
RECIPE.tools = {
	["blowtorch"] = 1
}


RECIPE:PostHook("OnCanCraft", function(recipeTable, client)
	for _, v in pairs(ents.FindByClass("ix_station_workbench")) do
		if (client:GetPos():DistToSqr(v:GetPos()) < 100 * 100) then
			return true
		end
	end

	return false, "You need to be near a workbench."
end)