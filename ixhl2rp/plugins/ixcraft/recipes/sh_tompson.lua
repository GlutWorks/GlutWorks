
RECIPE.name = "Thompson"
RECIPE.description = "Craft a Thompson."
RECIPE.model = "models/weapons/darky_m/rust/w_thompson.mdl"
RECIPE.category = "Salvaged Weapons"
RECIPE.requirements = {
	["metal_scrap"] = 3,
	["wooden_scrap"] = 1
}
RECIPE.interchangeable_req = {

}

RECIPE.results = {
	["thompson"] = 1
}
RECIPE.tools = {

}

RECIPE:PostHook("OnCanCraft", function(recipeTable, client)
	for _, v in pairs(ents.FindByClass("ix_station_workbench")) do
		if (client:GetPos():DistToSqr(v:GetPos()) < 100 * 100) then
			return true
		end
	end

	return false, "You need to be near a workbench."
end)
