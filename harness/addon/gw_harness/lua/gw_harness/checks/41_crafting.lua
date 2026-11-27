-- Crafting (ixcraft): recipes only reference items that exist, stations are real entities, every recipe crafts
-- with exactly its requirements and refuses one step short, results that do not fit are dropped with their
-- quantity, nothing is crafted while dead, tied or ragdolled, and a recipe whose result gives nothing is refused.
-- Requirements and results are stacks (40_stacking.lua); the helpers here are the same as there.

local Lib = GWH.Lib
local SCRAP, COAL, Fresh = Lib.SCRAP, Lib.COAL, Lib.Fresh
local Fill, NewStack, Quantities, Expect = Lib.Fill, Lib.NewStack, Lib.Quantities, Lib.Expect
local Scoped, Receive, Capture, Split = Lib.Scoped, Lib.ReceiveReads, Lib.Capture, Lib.Split

-- Gives the bot exactly what the recipe consumes (with the first interchangeable option), less `short` steps
-- of one requirement when given.
local function GiveRequirements(inventory, recipe, shortID)
	local needs = {}

	for uniqueID, amount in pairs(recipe.requirements or {}) do
		needs[uniqueID] = (needs[uniqueID] or 0) + amount
	end

	for uniqueID, amount in SortedPairs(recipe.interchangeable_req or {}) do
		needs[uniqueID] = (needs[uniqueID] or 0) + amount
		break
	end

	for _, uniqueID in ipairs(recipe.tools or {}) do
		needs[uniqueID] = (needs[uniqueID] or 0) + 1
	end

	for uniqueID, amount in pairs(needs) do
		if (uniqueID == shortID) then
			amount = amount - ix.stack.GetStep(uniqueID)
		end

		if (amount > 0 and !ix.stack.Give(inventory, uniqueID, amount)) then
			return false
		end
	end

	return needs
end

local function Snapshot(inventory, ids)
	local counts = {}

	for uniqueID in pairs(ids) do
		counts[uniqueID] = ix.stack.Count(inventory, uniqueID)
	end

	return counts
end

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

GWH.Check("stacking: every recipe crafts with exactly its requirements", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft) then return {skipped = "ixcraft not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local craft = plugin.craft
	local crafted = 0
	local stations = {}

	local function Station(id)
		if (!stations[id]) then
			local entity = ents.Create("ix_station_" .. id)

			if (IsValid(entity)) then
				entity:SetPos(bot:GetPos() + Vector(40, 0, 0))
				entity:Spawn()
				stations[id] = entity
			end
		end

		return stations[id]
	end

	for recipeID, recipe in SortedPairs(craft.recipes) do
		local inventory = Fresh(bot)

		if (recipe.station and !IsValid(Station(recipe.station))) then
			fail(recipeID .. ": could not spawn station " .. recipe.station)
		end

		local needs = GiveRequirements(inventory, recipe)

		if (!needs) then
			fail(recipeID .. ": requirements do not fit the bot's inventory")
			continue
		end

		local watched = table.Copy(needs)

		for uniqueID in pairs(recipe.results or {}) do
			watched[uniqueID] = true
		end

		local before = Snapshot(inventory, watched)
		local canCraft, reason = recipe:OnCanCraft(bot)

		if (!canCraft) then
			fail(recipeID .. ": cannot craft with exactly its requirements: " .. tostring(reason))
			continue
		end

		if (!craft.CraftRecipe(bot, recipeID)) then
			fail(recipeID .. ": CraftRecipe failed with exactly its requirements")
			continue
		end

		crafted = crafted + 1

		local after = Snapshot(inventory, watched)
		local consumed = {}

		for uniqueID, amount in pairs(recipe.requirements or {}) do
			consumed[uniqueID] = (consumed[uniqueID] or 0) + amount
		end

		for uniqueID, amount in SortedPairs(recipe.interchangeable_req or {}) do
			consumed[uniqueID] = (consumed[uniqueID] or 0) + amount
			break
		end

		for uniqueID in pairs(watched) do
			local result = recipe.results and recipe.results[uniqueID]
			local gained = isnumber(result) and result or 0
			local expected = ix.stack.Normalize(uniqueID, before[uniqueID] - (consumed[uniqueID] or 0) + gained)

			if (istable(result)) then
				local low, high = result["min"] or result[1], result["max"] or result[#result]
				local delta = after[uniqueID] - before[uniqueID] + (consumed[uniqueID] or 0)

				if (delta < low or delta > high) then
					fail(recipeID .. ": " .. uniqueID .. " result " .. delta .. " outside " .. low .. "-" .. high)
				end
			elseif (after[uniqueID] != expected) then
				fail(recipeID .. ": " .. uniqueID .. " is " .. tostring(after[uniqueID]) .. " after crafting, expected " ..
					tostring(expected))
			end
		end

		-- one step short of each requirement: refused, nothing consumed
		local short = {}

		for uniqueID in pairs(recipe.requirements or {}) do short[uniqueID] = true end
		for uniqueID in SortedPairs(recipe.interchangeable_req or {}) do short[uniqueID] = true break end
		for _, uniqueID in ipairs(recipe.tools or {}) do short[uniqueID] = true end

		for shortID in SortedPairs(short) do
			inventory = Fresh(bot)

			if (!GiveRequirements(inventory, recipe, shortID)) then
				fail(recipeID .. ": short requirements do not fit")
				continue
			end

			local held = Snapshot(inventory, needs)

			if (recipe:OnCanCraft(bot) or craft.CraftRecipe(bot, recipeID)) then
				fail(recipeID .. ": crafted while one step short of " .. shortID)
			end

			for uniqueID, amount in pairs(Snapshot(inventory, needs)) do
				if (amount != held[uniqueID]) then
					fail(recipeID .. ": refused craft changed " .. uniqueID .. " from " .. held[uniqueID] .. " to " .. amount)
				end
			end
		end

		-- the station is required
		if (recipe.station) then
			inventory = Fresh(bot)
			GiveRequirements(inventory, recipe)

			-- earlier checks may have left their own station entities nearby, so move all of them away
			local moved = {}

			for _, entity in ipairs(ents.FindByClass("ix_station_" .. recipe.station)) do
				moved[entity] = entity:GetPos()
				entity:SetPos(entity:GetPos() + Vector(0, 0, 5000))
			end

			if (recipe:OnCanCraft(bot)) then
				fail(recipeID .. ": craftable away from its station")
			end

			for entity, position in pairs(moved) do
				entity:SetPos(position)
			end
		end
	end

	for _, entity in pairs(stations) do
		if (IsValid(entity)) then entity:Remove() end
	end

	Fresh(bot)

	return {recipes = table.Count(craft.recipes), crafted = crafted}
end)

GWH.Check("stacking: crafting results that do not fit are dropped with their quantity", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft or !plugin.craft.recipes.plastic_bd) then return {skipped = "plastic_bd missing"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = Fresh(bot)
	local dropped = {}

	ix.stack.Give(inventory, "plastic1_junk", 1)
	Fill(inventory, 0)

	-- Refuse plastic_scrap in the inventory so the result cannot go in even after the junk frees its slot.
	hook.Add("CanTransferItem", "gwh_stacking", function(item, oldInv, newInv)
		if (item.uniqueID == "plastic_scrap" and newInv == inventory) then return false end
	end)

	hook.Add("OnItemSpawned", "gwh_stacking", function(entity)
		dropped[#dropped + 1] = entity
	end)

	local bSuccess = plugin.craft.CraftRecipe(bot, "plastic_bd")

	hook.Remove("CanTransferItem", "gwh_stacking")
	hook.Remove("OnItemSpawned", "gwh_stacking")

	Expect(fail, "breakdown crafted", bSuccess, true)
	Expect(fail, "junk consumed", ix.stack.Count(inventory, "plastic1_junk"), 0)
	Expect(fail, "nothing in the inventory", ix.stack.Count(inventory, "plastic_scrap"), 0)
	Expect(fail, "one item dropped", #dropped, 1)

	if (IsValid(dropped[1])) then
		local item, quantity = ix.stack.FromEntity(dropped[1])

		Expect(fail, "dropped item", item and item.uniqueID, "plastic_scrap")
		Expect(fail, "dropped quantity", quantity, 0.1)
		dropped[1]:Remove()
	end

	Fresh(bot)
end)

GWH.Check("stacking review: no crafting or splitting while dead, tied or ragdolled", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft) then return {skipped = "ixcraft not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		local recipeID = "gwh_review_state"

		plugin.craft.recipes[recipeID] = setmetatable({uniqueID = recipeID, name = "GWH State",
			requirements = {[SCRAP] = 1}, results = {[COAL] = 1}}, plugin.meta.recipe)
		defer(function() plugin.craft.recipes[recipeID] = nil end)
		defer(function() Fresh(bot) end)

		local ragdoll

		local states = {
			{"dead", function() bot:KillSilent() end, function() bot:Spawn() end},
			{"tied", function() bot:SetNetVar("restricted", true) end, function() bot:SetNetVar("restricted", nil) end},
			{"ragdolled", function()
				ragdoll = ents.Create("prop_physics")
				ragdoll:SetModel("models/props_junk/wood_crate001a.mdl")
				ragdoll:SetPos(bot:GetPos() + Vector(0, 0, 4000))
				ragdoll:Spawn()
				bot.ixRagdoll = ragdoll
			end, function()
				bot.ixRagdoll = nil
				ragdoll:Remove()
			end}
		}

		for _, state in ipairs(states) do
			local label, enter, leave = state[1], state[2], state[3]
			local inventory = Fresh(bot)
			local stack = NewStack(inventory, SCRAP, 5)

			enter()

			local ok, fault = pcall(function()
				Expect(fail, label .. ": CraftRecipe refused", plugin.craft.CraftRecipe(bot, recipeID), false)
				Receive("ixCraftRecipe", bot, {ReadString = {recipeID}})
				Expect(fail, label .. ": ingredients untouched", Quantities(inventory, SCRAP), "5")
				Expect(fail, label .. ": nothing crafted", Quantities(inventory, COAL), "")
				Expect(fail, label .. ": CanAccess refused", ix.stack.CanAccess(bot, stack), false)
				Expect(fail, label .. ": Split refused", (ix.stack.Split(bot, stack, "1")), false)
				Split(bot, stack, "2")
				Expect(fail, label .. ": split answer refused", Quantities(inventory, SCRAP), "5")
			end)

			leave()

			if (!ok) then fail(label .. ": " .. tostring(fault)) end
		end

		-- and both work again once the player is back on their feet
		local inventory = Fresh(bot)
		local stack = NewStack(inventory, SCRAP, 5)

		Expect(fail, "alive: CraftRecipe works", plugin.craft.CraftRecipe(bot, recipeID), true)
		Split(bot, stack, "2")
		Expect(fail, "alive: crafted and split", Quantities(inventory, SCRAP) .. "/" .. Quantities(inventory, COAL), "2,2/1")
	end)
end)

GWH.Check("stacking review: a recipe result that gives nothing leaves the ingredients alone", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft) then return {skipped = "ixcraft not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		local recipes = {
			gwh_review_unregistered = {[COAL] = 1, gwh_no_such_item = 1},
			gwh_review_substep = {[COAL] = 0.04},
			gwh_review_zero = {[COAL] = {0}}
		}

		for recipeID, results in pairs(recipes) do
			plugin.craft.recipes[recipeID] = setmetatable({uniqueID = recipeID, name = recipeID,
				requirements = {[SCRAP] = 2}, results = results}, plugin.meta.recipe)
		end

		defer(function()
			for recipeID in pairs(recipes) do plugin.craft.recipes[recipeID] = nil end
			Fresh(bot)
		end)

		for recipeID in SortedPairs(recipes) do
			local inventory = Fresh(bot)
			local result

			NewStack(inventory, SCRAP, 5)

			local seen = Capture(bot, function()
				result = plugin.craft.CraftRecipe(bot, recipeID)
			end)

			Expect(fail, recipeID .. ": refused", result, false)
			Expect(fail, recipeID .. ": ingredients untouched", Quantities(inventory, SCRAP), "5")
			Expect(fail, recipeID .. ": nothing given", Quantities(inventory, COAL), "")

			if (!seen.texts:find("broken", 1, true)) then
				fail(recipeID .. ": no notice saying the recipe is broken, got '" .. seen.texts .. "'")
			end
		end
	end)
end)
