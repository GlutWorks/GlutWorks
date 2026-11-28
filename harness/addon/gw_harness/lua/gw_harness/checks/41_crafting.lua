-- Crafting (ixcraft): recipes only reference items that exist, stations are real entities, every recipe crafts
-- with exactly its requirements and refuses one step short, results that do not fit are dropped with their
-- quantity, nothing is crafted while dead, tied or ragdolled, and a recipe whose result gives nothing is refused.
-- Crafting in the world: the Crafting tab is gone, what a station's panel lists (PLUGIN.craft.GetStationList) and
-- what a greyed recipe says it needs, the panel's ixCraftRecipe refused away from the station and answered with
-- ixCraftResult (a refusal says why, a craft that went through only sounds), and breaking a loose world item
-- down through ixCraftFromItem. The panel itself is client-only and is judged in a play session.
-- Requirements and results are stacks (40_stacking.lua); the helpers here are the same as there.

local Lib = GWH.Lib
local SCRAP, COAL, Fresh = Lib.SCRAP, Lib.COAL, Lib.Fresh
local Fill, NewStack, Quantities, Expect = Lib.Fill, Lib.NewStack, Lib.Quantities, Lib.Expect
local Scoped, Receive, Capture, Split = Lib.Scoped, Lib.ReceiveReads, Lib.Capture, Lib.Split

-- Runs fn and returns the text of the last ixCraftResult it sent ("" for none said) and its success flag (the
-- client plays the craft sound for true, the refusal sound for false), or nil when none was sent.
local function CraftAnswer(fn)
	local said, bSaidSuccess

	Scoped(function(defer)
		local start, write, writeBool = net.Start, net.WriteString, net.WriteBool
		local bResult = false

		Lib.Replace(defer, net, "Start", function(name, ...)
			bResult = name == "ixCraftResult"
			return start(name, ...)
		end)
		Lib.Replace(defer, net, "WriteBool", function(value, ...)
			if (bResult) then bSaidSuccess = value end
			return writeBool(value, ...)
		end)
		Lib.Replace(defer, net, "WriteString", function(text, ...)
			if (bResult) then said = text end
			return write(text, ...)
		end)

		fn()
	end)

	return said, bSaidSuccess
end

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

-- A rested bot: no stored crafting stamina means a full pool (see PLUGIN.craft.GetStamina).
local function Rest(bot)
	local character = bot:GetCharacter()

	if (character) then
		character:SetData("craftStamina", nil)
		character:SetData("craftStaminaAt", nil)
	end
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
		Rest(bot)
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
	Rest(bot)

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
				bot.ixNextCraft = nil
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

-- Every Lua file under a GAME path, with its text.
local function LuaFiles(path, out)
	out = out or {}

	local files, folders = file.Find(path .. "/*", "GAME")

	for _, v in ipairs(files or {}) do
		if (v:EndsWith(".lua")) then
			out[path .. "/" .. v] = file.Read(path .. "/" .. v, "GAME") or ""
		end
	end

	for _, v in ipairs(folders or {}) do
		LuaFiles(path .. "/" .. v, out)
	end

	return out
end

GWH.Check("crafting: there is no Crafting tab and nothing refers to it", function(fail)
	if (file.Exists("gamemodes/ixhl2rp/plugins/ixcraft/derma/cl_crafting.lua", "GAME")) then
		fail("ixcraft/derma/cl_crafting.lua still exists")
	end

	for path, text in SortedPairs(LuaFiles("gamemodes/ixhl2rp")) do
		for _, word in ipairs({"\"ixCrafting\"", "ixCraftingRecipe", "BuildCraftingMenu", "ix.gui.crafting", "tabs[\"crafting\"]"}) do
			if (text:find(word, 1, true)) then
				fail(path .. " mentions " .. word)
			end
		end
	end
end)

GWH.Check("crafting: a station lists its own recipes, then the ones needing no station", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft.GetStationList) then return fail("no PLUGIN.craft.GetStationList") end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local craft = plugin.craft

	Scoped(function(defer)
		defer(function() Fresh(bot) Rest(bot) end)
		Fresh(bot)
		Rest(bot)

		local counts = {}

		for stationID in SortedPairs(craft.stations) do
			local list = craft.GetStationList(bot, stationID)
			local bByHand = false
			local seen = {}

			counts[stationID] = 0

			for i, entry in ipairs(list) do
				if (entry.heading) then
					if (!isstring(entry.heading) or entry.heading == "") then fail(stationID .. ": heading " .. i .. " has no text") end
					if (bByHand and !entry.heading:find(", by hand", 1, true)) then
						fail(stationID .. ": station heading '" .. entry.heading .. "' after the by-hand ones")
					end
					bByHand = bByHand or entry.heading:find(", by hand", 1, true) != nil
				else
					local recipe = entry.recipe
					counts[stationID] = counts[stationID] + 1
					seen[entry.uniqueID] = true

					if (i == 1 or !recipe) then fail(stationID .. ": entry " .. i .. " is not under a heading") end
					if (recipe and recipe.station and recipe.station != stationID) then
						fail(stationID .. ": lists " .. entry.uniqueID .. ", made at " .. recipe.station)
					end
					if (recipe and !recipe.station and !bByHand) then
						fail(stationID .. ": lists " .. entry.uniqueID .. " (no station) before the by-hand heading")
					end
					-- an empty inventory can make nothing, and the reason says so in words
					if (entry.bCanCraft) then fail(stationID .. ": " .. entry.uniqueID .. " craftable with nothing") end
					if (!isstring(entry.reason) or entry.reason == "" or entry.reason:sub(1, 1) == "@") then
						fail(stationID .. ": " .. entry.uniqueID .. " has no readable reason: " .. tostring(entry.reason))
					end
				end
			end

			for recipeID, recipe in pairs(craft.recipes) do
				local bOffered = !craft.stations[stationID].smelting and (recipe.station == nil or recipe.station == stationID)

				if (bOffered != (seen[recipeID] == true)) then
					fail(stationID .. ": " .. recipeID .. (bOffered and " is missing" or " should not be listed"))
				end
			end
		end

		Expect(fail, "the smelter lists nothing", counts.smelter, 0)

		-- what can be made is marked so, as the inventory changes
		ix.stack.Give(Fresh(bot), "iron1_junk", 1)

		for _, entry in ipairs(craft.GetStationList(bot, "workbench")) do
			if (entry.uniqueID == "metal_bd") then
				Expect(fail, "metal_bd with iron junk held", entry.bCanCraft, true)
				Expect(fail, "metal_bd reason when makeable", entry.reason, nil)
			end
		end

		-- what a recipe needs, and what is missing, in words
		local needs = craft.DescribeNeeds(bot, craft.recipes.pipe_shotgun)

		for _, part in ipairs({"Pipe Shotgun makes", "Blowtorch", "Workbench", "You are missing"}) do
			if (!needs:find(part, 1, true)) then fail("pipe_shotgun's needs lack '" .. part .. "': " .. needs) end
		end

		return counts
	end)
end)

GWH.Check("crafting: the station panel's request is refused away from the station and answered privately", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin) then return fail("ixcraft not loaded") end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local recipe = plugin.craft.recipes.makarov
	if (!recipe) then return {skipped = "no makarov recipe"} end

	Scoped(function(defer)
		local moved = {}
		local stationClass = "ix_station_" .. recipe.station

		defer(function()
			for entity, position in pairs(moved) do
				if (IsValid(entity)) then entity:SetPos(position) end
			end

			Fresh(bot)
			Rest(bot)
		end)

		Rest(bot)

		-- every station of the makarov's kind far away
		for _, entity in ipairs(ents.FindByClass(stationClass)) do
			moved[entity] = entity:GetPos()
			entity:SetPos(entity:GetPos() + Vector(0, 0, 5000))
		end

		local inventory = Fresh(bot)
		GiveRequirements(inventory, recipe)

		local seen
		local said = CraftAnswer(function()
			seen = Capture(bot, function()
				bot.ixNextCraft = nil
				Receive("ixCraftRecipe", bot, {ReadString = {"makarov"}})
			end)
		end)

		Expect(fail, "away: no makarov", ix.stack.Count(inventory, "makarov"), 0)
		Expect(fail, "away: the refusal says why", (said or "") != "", true)
		Expect(fail, "away: scrap kept", ix.stack.Count(inventory, SCRAP), 2)
		Expect(fail, "away: answered with ixCraftResult", seen.nets:find("ixCraftResult", 1, true) != nil, true)
		Expect(fail, "away: no notice on screen", seen.texts .. seen.notices, "")

		-- beside its station it is made
		local bench = ents.Create(stationClass)
		bench:SetPos(bot:GetPos() + Vector(60, 0, 0))
		bench:Spawn()
		defer(function() if (IsValid(bench)) then bench:Remove() end end)

		said = CraftAnswer(function()
			seen = Capture(bot, function()
				bot.ixNextCraft = nil
				Receive("ixCraftRecipe", bot, {ReadString = {"makarov"}})
			end)
		end)

		Expect(fail, "near: makarov made", ix.stack.Count(inventory, "makarov"), 1)
		Expect(fail, "near: a craft that went through is heard, not said", said, "")
		Expect(fail, "near: scrap used", ix.stack.Count(inventory, SCRAP), 0)
		Expect(fail, "near: answered with ixCraftResult", seen.nets:find("ixCraftResult", 1, true) != nil, true)
	end)
end)

GWH.Check("crafting: a loose world item breaks down through ixCraftFromItem", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft.recipes.metal_bd) then return {skipped = "no metal_bd recipe"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Expect(fail, "iron junk is broken down by", (plugin.craft.GetRecipesUsing(bot, "iron1_junk")[1] or {}).uniqueID, "metal_bd")
	Expect(fail, "metal scrap breaks into nothing", #plugin.craft.GetRecipesUsing(bot, SCRAP), 0)

	Scoped(function(defer)
		local home = bot:GetPos()
		defer(function() bot:SetPos(home) end)
		defer(function() Lib.ResetBotFully(bot) Fresh(bot) end)

		Lib.ResetBotFully(bot)
		Lib.StandOnSpawn(bot)
		bot:SetEyeAngles(Angle(20, 0, 0))

		local inventory = Fresh(bot)

		local function SpawnJunk()
			local spawned

			ix.stack.Spawn("iron1_junk", bot:GetShootPos() + bot:GetAimVector() * 30, 1, angle_zero, function(_, entity)
				spawned = entity
			end)

			if (IsValid(spawned)) then
				local physics = spawned:GetPhysicsObject()
				if (IsValid(physics)) then physics:EnableMotion(false) end

				defer(function() if (IsValid(spawned)) then spawned:Remove() end end)
				Lib.ClearAround(bot, spawned)
			end

			return spawned
		end

		local function Ask(entity, recipeID)
			bot.ixNextCraft = nil

			return Capture(bot, function()
				Receive("ixCraftFromItem", bot, {ReadEntity = {entity}, ReadString = {recipeID}})
			end)
		end

		-- not a recipe for this item, or one made at a station: nothing is taken
		local junk = SpawnJunk()
		if (!IsValid(junk)) then return fail("could not spawn iron junk") end

		Ask(junk, "plastic_bd")
		Ask(junk, "makarov")
		Expect(fail, "wrong recipe: the item stays in the world", IsValid(junk) and !junk:IsMarkedForDeletion(), true)
		Expect(fail, "wrong recipe: nothing taken", ix.stack.Count(inventory, "iron1_junk"), 0)

		-- too far: nothing is taken
		local position = junk:GetPos()
		junk:SetPos(position + Vector(0, 0, 3000))
		Ask(junk, "metal_bd")
		Expect(fail, "too far: nothing taken", ix.stack.Count(inventory, "iron1_junk") + ix.stack.Count(inventory, SCRAP), 0)
		junk:SetPos(position)

		-- in reach: taken and broken down, answered as a success (the craft sound, not the refusal one)
		local seen
		local said, bSuccess = CraftAnswer(function() seen = Ask(junk, "metal_bd") end)
		Expect(fail, "broken down: scrap", ix.stack.Count(inventory, SCRAP), 1)
		Expect(fail, "broken down: junk used", ix.stack.Count(inventory, "iron1_junk"), 0)
		Expect(fail, "broken down: the world item is gone", !IsValid(junk) or junk:IsMarkedForDeletion(), true)
		Expect(fail, "broken down: answered with ixCraftResult", seen.nets:find("ixCraftResult", 1, true) != nil, true)
		Expect(fail, "broken down: answered as a success", bSuccess, true)
		Expect(fail, "broken down: nothing said", said, "")
	end)
end)

GWH.Check("crafting: whoever can keep a station's panel open can craft there, and no farther", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft.recipes.makarov) then return {skipped = "no makarov recipe"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local recipe = plugin.craft.recipes.makarov
	local range = recipe.stationRange
	local interaction = ix.plugin.list.interaction

	-- the panel opens within the tap's reach and closes before the station's reach ends
	if (plugin.craft.panelReach > range) then
		fail("the panel stays open to " .. plugin.craft.panelReach .. ", beyond the crafting reach " .. range)
	end

	if (interaction and interaction.reach > plugin.craft.panelReach) then
		fail("the panel opens from " .. interaction.reach .. ", beyond where it stays open (" .. plugin.craft.panelReach .. ")")
	end

	-- and the reach is one a person could use a bench from
	if (range > 140) then fail("a station recipe can be made from " .. range .. " units away") end

	Scoped(function(defer)
		local home = bot:GetPos()
		local moved = {}

		defer(function()
			bot:SetPos(home)

			for entity, position in pairs(moved) do
				if (IsValid(entity)) then entity:SetPos(position) end
			end

			Fresh(bot)
			Rest(bot)
		end)

		local stationClass = "ix_station_" .. recipe.station

		for _, entity in ipairs(ents.FindByClass(stationClass)) do
			moved[entity] = entity:GetPos()
			entity:SetPos(entity:GetPos() + Vector(0, 0, 5000))
		end

		Lib.ResetBotFully(bot)
		Lib.StandOnSpawn(bot)

		local bench = ents.Create(stationClass)
		bench:SetPos(bot:GetPos() + Vector(150, 0, 0))
		bench:Spawn()
		defer(function() if (IsValid(bench)) then bench:Remove() end end)

		-- puts the bot's eyes `distance` from the bench's surface, along the line between them
		local function StandAt(distance)
			for _ = 1, 4 do
				local eyes = bot:GetShootPos()
				local nearest = bench:NearestPoint(eyes)
				local away = eyes - nearest
				away.z = 0

				local now = (eyes - nearest):Length()

				if (away:LengthSqr() < 1) then away = Vector(-1, 0, 0) end

				bot:SetPos(bot:GetPos() + away:GetNormalized() * (distance - now))
			end

			return bot:GetShootPos():Distance(bench:NearestPoint(bot:GetShootPos()))
		end

		local function Try(distance)
			Rest(bot)
			local inventory = Fresh(bot)
			GiveRequirements(inventory, recipe)

			local actual = StandAt(distance)
			local bCan = recipe:OnCanCraft(bot)

			bot.ixNextCraft = nil
			Receive("ixCraftRecipe", bot, {ReadString = {"makarov"}})

			return bCan == true, ix.stack.Count(inventory, "makarov") == 1, actual
		end

		local bCan, bMade, actual = Try(plugin.craft.panelReach)
		if (!bCan or !bMade) then fail("at the panel's reach (" .. math.Round(actual, 1) .. ") the makarov was not made") end

		bCan, bMade, actual = Try(range + 12)
		if (bCan or bMade) then fail("beyond the crafting reach (" .. math.Round(actual, 1) .. ") the makarov was made") end
	end)
end)

GWH.Check("crafting: breaking down a world stack that merges or does not fit", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin) then return fail("ixcraft not loaded") end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		local recipeID = "gwh_world_stack"
		local home = bot:GetPos()

		plugin.craft.recipes[recipeID] = setmetatable({uniqueID = recipeID, name = "GWH Stack", category = "Breakdown",
			requirements = {[SCRAP] = 2}, results = {[COAL] = 1}}, plugin.meta.recipe)

		defer(function() plugin.craft.recipes[recipeID] = nil end)
		defer(function() bot:SetPos(home) Lib.ResetBotFully(bot) Fresh(bot) end)

		Lib.ResetBotFully(bot)
		Lib.StandOnSpawn(bot)
		bot:SetEyeAngles(Angle(20, 0, 0))

		local function SpawnScrap(quantity)
			local spawned

			ix.stack.Spawn(SCRAP, bot:GetShootPos() + bot:GetAimVector() * 30, quantity, angle_zero, function(_, entity)
				spawned = entity
			end)

			if (IsValid(spawned)) then
				local physics = spawned:GetPhysicsObject()
				if (IsValid(physics)) then physics:EnableMotion(false) end

				defer(function() if (IsValid(spawned)) then spawned:Remove() end end)
				Lib.ClearAround(bot, spawned)
			end

			return spawned
		end

		local function Ask(entity)
			bot.ixNextCraft = nil

			return Capture(bot, function()
				Receive("ixCraftFromItem", bot, {ReadEntity = {entity}, ReadString = {recipeID}})
			end)
		end

		-- 1 kg held, 1.5 kg on the floor merges into it: then 2 kg are made into coal and 0.5 kg is left
		local inventory = Fresh(bot)
		NewStack(inventory, SCRAP, 1)

		local scrap = SpawnScrap(1.5)
		if (!IsValid(scrap)) then return fail("could not spawn a stack of scrap") end

		local seen
		local _, bSuccess = CraftAnswer(function() seen = Ask(scrap) end)
		Expect(fail, "merged: crafted", ix.stack.Count(inventory, COAL), 1)
		Expect(fail, "merged: answered as a success", bSuccess, true)
		Expect(fail, "merged: scrap left", ix.stack.Count(inventory, SCRAP), 0.5)
		Expect(fail, "merged: world stack gone", !IsValid(scrap) or scrap:IsMarkedForDeletion(), true)
		Expect(fail, "merged: answered privately", seen.nets:find("ixCraftResult", 1, true) != nil, true)
		Expect(fail, "merged: no notice on screen", seen.texts .. seen.notices, "")

		-- not enough even after taking it: taken, nothing crafted, nothing lost
		inventory = Fresh(bot)
		scrap = SpawnScrap(1)
		_, bSuccess = CraftAnswer(function() seen = Ask(scrap) end)
		Expect(fail, "too little: taken", ix.stack.Count(inventory, SCRAP), 1)
		Expect(fail, "too little: answered as a refusal", bSuccess, false)
		Expect(fail, "too little: nothing made", ix.stack.Count(inventory, COAL), 0)
		Expect(fail, "too little: no notice on screen", seen.texts .. seen.notices, "")

		-- a full inventory: nothing taken, refused privately
		inventory = Fresh(bot)
		Fill(inventory, 0)
		scrap = SpawnScrap(3)
		_, bSuccess = CraftAnswer(function() seen = Ask(scrap) end)
		Expect(fail, "full: answered as a refusal", bSuccess, false)
		Expect(fail, "full: world stack stays", IsValid(scrap) and !scrap:IsMarkedForDeletion(), true)
		Expect(fail, "full: nothing made", ix.stack.Count(inventory, COAL), 0)
		Expect(fail, "full: answered privately", seen.nets:find("ixCraftResult", 1, true) != nil, true)
		Expect(fail, "full: no notice on screen", seen.texts .. seen.notices, "")
	end)
end)

GWH.Check("crafting: materials are priced, still not business-buyable, and CWU pay is below price", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local pricedBases = {base_resources = true, base_components = true, base_singular_components = true,
		base_tools = true, base_ore = true}
	local junkBases = {base_misc_junk = true, base_smeltable_junk = true}
	local counts = {}

	for uniqueID, itemTable in SortedPairs(ix.item.list) do
		if (itemTable.isBase) then continue end

		if (pricedBases[itemTable.base]) then
			counts[itemTable.base] = (counts[itemTable.base] or 0) + 1

			if (!isnumber(itemTable.price) or !(itemTable.price > 0)) then
				fail(uniqueID .. " (" .. itemTable.base .. ") has no positive price: " .. tostring(itemTable.price))
			end

			-- price alone must not open Business: no gate field was added, and the schema refuses it
			for _, field in ipairs({"factions", "classes", "permit", "flag"}) do
				if (itemTable[field] != nil) then fail(uniqueID .. " gained a Business gate field: " .. field) end
			end

			if (hook.Run("CanPlayerUseBusiness", bot, uniqueID) != false) then
				fail("priced material " .. uniqueID .. " is business-buyable without a gate")
			end
		elseif (junkBases[itemTable.base]) then
			counts[itemTable.base] = (counts[itemTable.base] or 0) + 1

			if (itemTable.noBusiness != true) then fail("junk " .. uniqueID .. " is not marked noBusiness") end
		end
	end

	for base in pairs(pricedBases) do
		if (!counts[base]) then fail("no items found on " .. base) end
	end

	-- delivering to the city is a discount sale, never an arbitrage
	local city = ix.plugin.list.cityeconomy

	if (city and city.wanted) then
		for uniqueID, wanted in SortedPairs(city.wanted) do
			local itemTable = ix.item.list[uniqueID]

			if (itemTable and isnumber(itemTable.price) and wanted.pay >= itemTable.price) then
				fail("CWU pay " .. wanted.pay .. " for " .. uniqueID .. " is not below its price " .. itemTable.price)
			end
		end

		for _, uniqueID in ipairs({"metal_scrap", "wooden_scrap", "plastic_scrap", "coal_ore", "copper_ore",
			"iron_ore", "tin_ore", "gold_ore"}) do
			local itemTable = ix.item.list[uniqueID]

			if (!itemTable or !isnumber(itemTable.price) or !(city.wanted[uniqueID].pay < itemTable.price)) then
				fail("CWU good " .. uniqueID .. " is not priced above its pay")
			end
		end
	else
		fail("cityeconomy wanted table not loaded")
	end

	return counts
end)

GWH.Check("crafting: component recipes and the rebuilt guns need components, tools and their stations", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft) then return {skipped = "ixcraft not loaded"} end

	local craft = plugin.craft
	local components = {box_of_gears = true, box_of_screws = true, box_of_springs = true, pipe = true,
		cable_spool = true, duct_tape = true, junk_weapon_components = true, large_gear = true}
	local componentRecipes = {gears = "box_of_gears", screws = "box_of_screws", springs = "box_of_springs",
		scrap_pipe = "pipe", cable = "cable_spool", duct_tape_roll = "duct_tape",
		weapon_components = "junk_weapon_components", large_gear_part = "large_gear"}

	for recipeID, resultID in SortedPairs(componentRecipes) do
		local recipe = craft.recipes[recipeID]

		if (!recipe) then
			fail("missing component recipe " .. recipeID)
			continue
		end

		if (!(recipe.results and recipe.results[resultID])) then fail(recipeID .. " does not make " .. resultID) end
		if (recipe.station != "workbench" and recipe.station != "advanced_workbench") then
			fail(recipeID .. " is made at " .. tostring(recipe.station) .. ", not a bench")
		end
		Expect(fail, recipeID .. " stamina", craft.GetStaminaCost(recipe), 5)
	end

	local guns = {makarov = "machinery", spectre = "advanced_workbench", nailgun = "workbench"}

	for recipeID, station in SortedPairs(guns) do
		local recipe = craft.recipes[recipeID]

		if (!recipe) then
			fail("missing gun recipe " .. recipeID)
			continue
		end

		Expect(fail, recipeID .. " station", recipe.station, station)
		Expect(fail, recipeID .. " stamina", craft.GetStaminaCost(recipe), 20)

		local bComponent = false

		for uniqueID in pairs(recipe.requirements or {}) do
			if (components[uniqueID]) then bComponent = true end
		end

		if (!bComponent) then fail(recipeID .. " needs no crafted component") end
		if (!table.HasValue(recipe.tools or {}, "blowtorch")) then fail(recipeID .. " needs no blowtorch at hand") end
	end

	for _, recipeID in ipairs({"metal_bd", "plastic_bd", "wood_bd"}) do
		Expect(fail, recipeID .. " stamina", craft.GetStaminaCost(craft.recipes[recipeID]), 2)
	end

	-- the low tier stays low
	Expect(fail, "pipe_shotgun station", craft.recipes.pipe_shotgun.station, "workbench")
end)

GWH.Check("crafting: stamina drains, refuses when tired without going negative, and regains with time", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft or !plugin.craft.GetStamina) then return fail("no PLUGIN.craft.GetStamina") end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local craft = plugin.craft
	local maximum = ix.config.Get("craftStaminaMax", 100)

	Scoped(function(defer)
		local recipeID = "gwh_stamina"

		craft.recipes[recipeID] = setmetatable({uniqueID = recipeID, name = "GWH Stamina", stamina = 20,
			requirements = {[SCRAP] = 1}, results = {[COAL] = 1}}, plugin.meta.recipe)
		defer(function() craft.recipes[recipeID] = nil Fresh(bot) Rest(bot) end)

		local recipe = craft.recipes[recipeID]
		local character = bot:GetCharacter()
		local inventory = Fresh(bot)

		-- a character that has never crafted is rested, and an unset cost defaults to 5
		Rest(bot)
		Expect(fail, "fresh: full pool", craft.GetStamina(bot), maximum)
		Expect(fail, "default cost", craft.GetStaminaCost({}), 5)
		Expect(fail, "fresh: can craft", recipe:OnCanCraft(bot), false) -- no scrap yet, but not for tiredness

		ix.stack.Give(inventory, SCRAP, 20)
		Expect(fail, "fresh with scrap: can craft", recipe:OnCanCraft(bot), true)

		for i = 1, 5 do
			Expect(fail, "craft " .. i, craft.CraftRecipe(bot, recipeID), true)

			if (craft.GetStamina(bot) < 0) then fail("pool went negative after craft " .. i) end
		end

		Expect(fail, "drained: coal made", ix.stack.Count(inventory, COAL), 5)

		-- the next one is refused for tiredness, says so, and takes nothing
		local held = ix.stack.Count(inventory, SCRAP)
		local bCan, reason = recipe:OnCanCraft(bot)
		Expect(fail, "tired: OnCanCraft refused", bCan, false)
		Expect(fail, "tired: reason", reason, "@CraftTooTired")

		local seen = Capture(bot, function()
			Expect(fail, "tired: CraftRecipe refused", craft.CraftRecipe(bot, recipeID), false)
		end)

		if (!seen.texts:find("too tired", 1, true)) then fail("tired refusal did not say so: '" .. seen.texts .. "'") end
		Expect(fail, "tired: scrap kept", ix.stack.Count(inventory, SCRAP), held)
		if (craft.GetStamina(bot) < 0 or craft.GetStamina(bot) >= 20) then
			fail("tired: pool is " .. craft.GetStamina(bot) .. ", expected 0 up to a second of regen")
		end

		-- just short refuses; exactly enough crafts and lands on (never below) zero
		craft.SetStamina(bot, 19)
		Expect(fail, "19 of 20: refused", (recipe:OnCanCraft(bot)), false)
		craft.SetStamina(bot, 20)
		Expect(fail, "20 of 20: can craft", recipe:OnCanCraft(bot), true)
		Expect(fail, "20 of 20: crafted", craft.CraftRecipe(bot, recipeID), true)
		if (craft.GetStamina(bot) < 0) then fail("pool went negative at exactly enough") end

		-- regen is time since the pool was stamped: two minutes back is 10 at the default 5 a minute
		craft.SetStamina(bot, 0)
		character:SetData("craftStaminaAt", os.time() - 120)

		local regained = craft.GetStamina(bot)
		local expected = 2 * ix.config.Get("craftStaminaRegen", 5)

		if (math.abs(regained - expected) > 1) then fail("regen after 2 minutes is " .. regained .. ", expected " .. expected) end
		Expect(fail, "regen: still tired for 20", (recipe:OnCanCraft(bot)), false)

		character:SetData("craftStaminaAt", os.time() - 100000)
		Expect(fail, "regen: capped at the maximum", craft.GetStamina(bot), maximum)
		Expect(fail, "rested by time: can craft", recipe:OnCanCraft(bot), true)
	end)
end)

GWH.Check("crafting: resources make components, and components make a nailgun", function(fail)
	local plugin = ix.plugin.list.ixcraft
	if (!plugin or !plugin.craft) then return {skipped = "ixcraft not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local craft = plugin.craft

	Scoped(function(defer)
		defer(function() Fresh(bot) Rest(bot) end)
		Rest(bot)

		local bench = ents.Create("ix_station_workbench")
		bench:SetPos(bot:GetPos() + Vector(40, 0, 0))
		bench:Spawn()
		defer(function() if (IsValid(bench)) then bench:Remove() end end)

		local inventory = Fresh(bot)
		ix.stack.Give(inventory, "iron", 1)
		ix.stack.Give(inventory, SCRAP, 3)
		ix.stack.Give(inventory, "wooden_scrap", 1)
		ix.stack.Give(inventory, "blowtorch", 1)

		Expect(fail, "springs crafted", craft.CraftRecipe(bot, "springs"), true)
		Expect(fail, "screws crafted", craft.CraftRecipe(bot, "screws"), true)
		Expect(fail, "springs held", ix.stack.Count(inventory, "box_of_springs"), 2)
		Expect(fail, "nailgun crafted", craft.CraftRecipe(bot, "nailgun"), true)
		Expect(fail, "nailgun held", ix.stack.Count(inventory, "nailgun"), 1)
		Expect(fail, "tool kept", ix.stack.Count(inventory, "blowtorch"), 1)
		Expect(fail, "springs left", ix.stack.Count(inventory, "box_of_springs"), 1)

		-- 5 + 5 + 20 spent from a full pool
		local stamina = craft.GetStamina(bot)

		if (math.abs(stamina - (ix.config.Get("craftStaminaMax", 100) - 30)) > 1) then
			fail("stamina after the chain is " .. stamina .. ", expected 30 spent")
		end
	end)
end)
