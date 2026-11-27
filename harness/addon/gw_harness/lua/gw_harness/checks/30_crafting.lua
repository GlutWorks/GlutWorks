-- Crafting checks: recipes only reference items that exist, and stations are real entities.

GWH.Check("recipes reference existing items", function(fail)
	local craft = ix.plugin.list.ixcraft and ix.plugin.list.ixcraft.craft
	if (!craft) then return {skipped = "ixcraft not loaded"} end

	local count = 0

	for recipeID, recipe in SortedPairs(craft.recipes or {}) do
		count = count + 1

		for _, field in ipairs({"requirements", "interchangeable_req", "results"}) do
			for uniqueID in pairs(recipe[field] or {}) do
				if (!ix.item.list[uniqueID]) then
					fail(recipeID .. ": " .. field .. " names unknown item '" .. tostring(uniqueID) .. "'")
				end
			end
		end

		-- The recipe code iterates tool values, so tools must be a list of item ids.
		for key, uniqueID in pairs(recipe.tools or {}) do
			if (!isnumber(key) or !ix.item.list[uniqueID]) then
				fail(recipeID .. ": tools entry [" .. tostring(key) .. "] = " .. tostring(uniqueID) .. " is not a list of item ids")
			end
		end

		if (!next(recipe.results or {})) then fail(recipeID .. ": no results") end
	end

	return {recipes = count}
end)

GWH.Check("stations have a working entity", function(fail)
	local craft = ix.plugin.list.ixcraft and ix.plugin.list.ixcraft.craft
	if (!craft) then return {skipped = "ixcraft not loaded"} end

	local count = 0

	for stationID in SortedPairs(craft.stations or {}) do
		local class = "ix_station_" .. stationID
		count = count + 1

		if (!scripted_ents.GetStored(class)) then
			fail(stationID .. ": no entity class " .. class)
		else
			local entity = ents.Create(class)

			if (IsValid(entity)) then
				entity:Spawn()

				local model = entity:GetModel()
				if (!model or model == "" or model == "models/error.mdl") then
					fail(stationID .. ": " .. class .. " spawns without a model")
				end

				if (!IsValid(entity:GetPhysicsObject())) then
					fail(stationID .. ": " .. class .. " spawns without physics")
				end

				entity:Remove()
			end
		end
	end

	return {stations = count}
end)
