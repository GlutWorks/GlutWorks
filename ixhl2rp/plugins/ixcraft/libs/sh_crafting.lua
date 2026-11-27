
local PLUGIN = PLUGIN

PLUGIN.craft = PLUGIN.craft or {}
PLUGIN.craft.recipes = PLUGIN.craft.recipes or {}
PLUGIN.craft.stations = PLUGIN.craft.stations or {}

function PLUGIN.craft.LoadFromDir(directory, pathType)
	for _, v in ipairs(file.Find(directory.."/sh_*.lua", "LUA")) do
		local niceName = v:sub(4, -5)

		if (pathType == "recipe") then
			RECIPE = setmetatable({
				uniqueID = niceName
			}, PLUGIN.meta.recipe)
				ix.util.Include(directory.."/"..v, "shared")

				PLUGIN.craft.recipes[niceName] = RECIPE
			RECIPE = nil
		elseif (pathType == "station") then
			STATION = setmetatable({
				uniqueID = niceName
			}, PLUGIN.meta.station)
				ix.util.Include(directory.."/"..v, "shared")

				local class = "ix_station_"..niceName
				local stationEntity = scripted_ents.Get(class)

				if (stationEntity) then
					stationEntity.uniqueID = niceName
					stationEntity.name = STATION.name
					stationEntity.description = STATION.description
					stationEntity.model = STATION.model
					stationEntity.Type = "anim"
					stationEntity.PrintName = STATION.name
					stationEntity.Category = "Helix"
					stationEntity.AdminOnly = true
					stationEntity.Spawnable = true

					scripted_ents.Register(stationEntity, class)
				else
					ErrorNoHalt("[ixcraft] Station '"..niceName.."' has no entity class "..class.."\n")
				end

				PLUGIN.craft.stations[niceName] = STATION
			STATION = nil
		end
	end
end

-- How far (from the eyes to the station's surface) a station's world panel stays open: within the reach a
-- station recipe is made at (RECIPE.stationRange), so whoever has the panel open can make what it offers.
PLUGIN.craft.panelReach = 120

function PLUGIN.craft.FindByName(recipe)
	recipe = recipe:lower()
	local uniqueID

	for k, v in pairs(PLUGIN.craft.recipes) do
		if (recipe:find(v.name:lower(), 1, true)) then
			uniqueID = k

			break
		end
	end

	return uniqueID
end

-- A language phrase for `client`, in either realm (Helix's L takes the player only on the server).
local function Phrase(client, key, ...)
	if (SERVER) then
		return L(key, client, ...)
	end

	return L(key, ...)
end

PLUGIN.craft.Phrase = Phrase

--- Turns what OnCanCraft returned on refusal ("@phrase" and its arguments, or plain text) into text.
function PLUGIN.craft.FormatReason(client, reason, ...)
	if (!isstring(reason)) then
		return nil
	end

	if (reason:sub(1, 1) == "@") then
		return Phrase(client, reason:sub(2), ...)
	end

	return reason
end

--- The name of a recipe, as shown.
function PLUGIN.craft.GetRecipeName(recipe)
	return recipe.GetName and recipe:GetName() or recipe.name
end

--- Whether a recipe is offered at a station: one made at that station, or one that needs none.
function PLUGIN.craft.IsOfferedAt(recipe, stationID)
	return recipe.station == nil or recipe.station == stationID
end

--- What a player is offered at a station, in the order a world panel lists it: the station's own recipes,
-- one group per category, then the recipes that need no station, one group per category ("Breakdown, by
-- hand"). Recipes the player may not see (OnCanSee) are left out. Each entry is `{heading = text}` or
-- `{recipe = recipeTable, uniqueID = id, bCanCraft = bool, reason = text or nil}`; `reason` is why it cannot be
-- made now, in the player's language. A smelter offers nothing.
-- @player client Who is at the station
-- @string stationID The station's ID (`entity:GetStationID()`)
-- @treturn table Entries in order
function PLUGIN.craft.GetStationList(client, stationID)
	local station = PLUGIN.craft.stations[stationID]
	local groups = {}
	local list = {}

	if (!station or station.smelting) then
		return list
	end

	for uniqueID, recipe in pairs(PLUGIN.craft.recipes) do
		if (PLUGIN.craft.IsOfferedAt(recipe, stationID) and recipe:OnCanSee(client)) then
			local category = recipe.category or "Crafting"
			local bHere = recipe.station != nil
			local key = (bHere and "1" or "2") .. category
			local group = groups[key]

			if (!group) then
				group = {
					title = bHere and Phrase(client, category) or Phrase(client, "craftByHand", Phrase(client, category)),
					recipes = {}
				}
				groups[key] = group
			end

			group.recipes[#group.recipes + 1] = {uniqueID = uniqueID, recipe = recipe, name = PLUGIN.craft.GetRecipeName(recipe)}
		end
	end

	for _, group in SortedPairs(groups) do
		list[#list + 1] = {heading = group.title}

		table.SortByMember(group.recipes, "name", true)

		for _, entry in ipairs(group.recipes) do
			local result = {entry.recipe:OnCanCraft(client)}

			list[#list + 1] = {
				recipe = entry.recipe,
				uniqueID = entry.uniqueID,
				bCanCraft = result[1] == true,
				reason = result[1] != true and PLUGIN.craft.FormatReason(client, result[2], unpack(result, 3, 6)) or nil
			}
		end
	end

	return list
end

--- The recipes needing no station that use an item as an ingredient (a requirement or one of the
-- interchangeable ones), sorted by name: what a loose world item of that kind can be made into.
function PLUGIN.craft.GetRecipesUsing(client, uniqueID)
	local found = {}

	for recipeID, recipe in pairs(PLUGIN.craft.recipes) do
		if (!recipe.station and ((recipe.requirements and recipe.requirements[uniqueID]) or
			(recipe.interchangeable_req and recipe.interchangeable_req[uniqueID])) and recipe:OnCanSee(client)) then
			found[#found + 1] = {uniqueID = recipeID, recipe = recipe, name = PLUGIN.craft.GetRecipeName(recipe)}
		end
	end

	table.SortByMember(found, "name", true)

	return found
end

-- "Metal Scrap (2 kg)", "Box of Gears (2 gears)", "Pipe", "2x Pipe", "1-3x Bolt".
local function DescribeAmount(uniqueID, amount)
	local itemTable = ix.item.list[uniqueID]
	local name = itemTable and itemTable.name or uniqueID

	if (itemTable and itemTable.stackUnit) then
		local quantity = isnumber(amount) and ix.stack.Format(itemTable, amount) or (amount .. " " .. itemTable.stackUnit)

		return name .. " (" .. quantity .. ")"
	end

	if (amount == 1) then
		return name
	end

	return amount .. "x " .. name
end

--- What a recipe needs and makes, as lists of text: `tools`, `requirements`, `interchangeable` (any one of)
-- and `results`.
function PLUGIN.craft.GetRecipeParts(recipe)
	local parts = {tools = {}, requirements = {}, interchangeable = {}, results = {}}

	for _, uniqueID in ipairs(recipe.tools or {}) do
		local itemTable = ix.item.list[uniqueID]

		parts.tools[#parts.tools + 1] = itemTable and itemTable.name or uniqueID
	end

	for uniqueID, amount in SortedPairs(recipe.requirements or {}) do
		parts.requirements[#parts.requirements + 1] = DescribeAmount(uniqueID, amount)
	end

	for uniqueID, amount in SortedPairs(recipe.interchangeable_req or {}) do
		parts.interchangeable[#parts.interchangeable + 1] = DescribeAmount(uniqueID, amount)
	end

	for uniqueID, amount in SortedPairs(recipe.results or {}) do
		if (istable(amount)) then
			amount = (amount["min"] or amount[1]) .. "-" .. (amount["max"] or amount[#amount])
		end

		parts.results[#parts.results + 1] = DescribeAmount(uniqueID, amount)
	end

	return parts
end

--- What a recipe needs and makes, and what the player lacks, in a sentence or two:
-- "Pipe Shotgun makes 1x Pipe Shotgun from 2.0 kg Metal Scrap, 1x Pipe, with a Blowtorch, at a Workbench. You are
-- missing: Pipe."
function PLUGIN.craft.DescribeNeeds(client, recipe)
	local parts = PLUGIN.craft.GetRecipeParts(recipe)
	local needs = {}

	if (#parts.requirements > 0) then
		needs[#needs + 1] = table.concat(parts.requirements, ", ")
	end

	if (#parts.interchangeable > 0) then
		needs[#needs + 1] = Phrase(client, "craftAnyOf", table.concat(parts.interchangeable, ", or "))
	end

	local text = Phrase(client, "craftNeeds", PLUGIN.craft.GetRecipeName(recipe), table.concat(parts.results, ", "),
		table.concat(needs, ", "))

	if (#parts.tools > 0) then
		text = text .. " " .. Phrase(client, "craftNeedsTools", table.concat(parts.tools, ", "))
	end

	if (recipe.station) then
		local station = PLUGIN.craft.stations[recipe.station]

		text = text .. " " .. Phrase(client, "craftNeedsStation", station and station.name or recipe.station)
	end

	local result = {recipe:OnCanCraft(client)}

	if (result[1] != true) then
		local reason = PLUGIN.craft.FormatReason(client, result[2], unpack(result, 3, 6))

		if (reason) then
			text = text .. " " .. reason
		end
	end

	return text
end

if (SERVER) then
	util.AddNetworkString("ixCraftRecipe")
	util.AddNetworkString("ixCraftRefresh")
	util.AddNetworkString("ixCraftResult")
	util.AddNetworkString("ixCraftFromItem")

	--- Whether the player is in a state to craft at all: alive, not tied and not ragdolled.
	function PLUGIN.craft.CanPlayerCraft(client)
		return IsValid(client) and client:GetCharacter() != nil and client:Alive() and !client:IsRestricted() and
			!IsValid(client.ixRagdoll)
	end

	--- Crafts a recipe for a player, checking everything first. What happened is told to the player: by
	-- `Tell(text, bSuccess)` when given, otherwise as a notice.
	-- @treturn bool Whether it was crafted
	-- @treturn[opt] string What the player was told
	function PLUGIN.craft.CraftRecipe(client, uniqueID, Tell)
		local recipeTable = PLUGIN.craft.recipes[uniqueID]

		Tell = Tell or function(text)
			client:Notify(text)
		end

		if (!PLUGIN.craft.CanPlayerCraft(client)) then
			if (IsValid(client)) then
				local text = L("notNow", client)

				Tell(text, false)

				return false, text
			end

			return false
		end

		if (recipeTable) then
			local bCanCraft, failString, c, d, e, f = recipeTable:OnCanCraft(client)

			if (!bCanCraft) then
				failString = PLUGIN.craft.FormatReason(client, failString, c, d, e, f)

				if (failString) then
					Tell(failString, false)
				end

				return false, failString
			end

			local success, craftString, c2, d2, e2, f2 = recipeTable:OnCraft(client)

			craftString = PLUGIN.craft.FormatReason(client, craftString, c2, d2, e2, f2)

			if (craftString) then
				Tell(craftString, success == true)
			end

			return success, craftString
		end

		return false
	end

	-- The answer to a craft asked for from a world panel: a private line and a sound on the client.
	local function Answer(client, text, bSuccess)
		net.Start("ixCraftResult")
			net.WriteBool(bSuccess == true)
			net.WriteString(text or "")
		net.Send(client)
	end

	local function Refresh(client)
		timer.Simple(0.2, function()
			if (IsValid(client)) then
				net.Start("ixCraftRefresh")
				net.Send(client)
			end
		end)
	end

	-- One craft request a player may make in this time, from a panel or a world item.
	PLUGIN.craft.requestInterval = 0.3

	local function RateLimited(client)
		if ((client.ixNextCraft or 0) > CurTime()) then
			return true
		end

		client.ixNextCraft = CurTime() + PLUGIN.craft.requestInterval
	end

	-- Chosen from a station's world panel. The recipe's own checks decide, the station included (OnCanCraft:
	-- within reach of an entity of the recipe's station, IsNearStation), exactly as for /CraftRecipe.
	net.Receive("ixCraftRecipe", function(length, client)
		if (RateLimited(client)) then
			return
		end

		PLUGIN.craft.CraftRecipe(client, net.ReadString(), function(text, bSuccess)
			Answer(client, text, bSuccess)
		end)

		Refresh(client)
	end)

	-- Runs fn with every notice for `client` held back; returns what they said, joined, or nil.
	local function HoldNotices(client, fn)
		local said = {}
		local notify, notifyLocalized = ix.util.Notify, ix.util.NotifyLocalized

		ix.util.Notify = function(message, recipient, ...)
			if (recipient != client) then
				return notify(message, recipient, ...)
			end

			said[#said + 1] = tostring(message)
		end

		ix.util.NotifyLocalized = function(message, recipient, ...)
			if (recipient != client) then
				return notifyLocalized(message, recipient, ...)
			end

			said[#said + 1] = L(message, client, ...)
		end

		local bSuccess, result = xpcall(fn, debug.traceback)

		ix.util.Notify, ix.util.NotifyLocalized = notify, notifyLocalized

		if (!bSuccess) then
			error(result, 0)
		end

		return #said > 0 and table.concat(said, " ") or nil, result
	end

	--- Makes a recipe that needs no station from a loose world item that is one of its ingredients: the item is
	-- taken into the inventory the way Use takes it (Helix's "take", with every rule that applies to it: a stack
	-- may merge into one already held, or only part of it may fit), then, if the player now holds more of it than
	-- before, the recipe is crafted as from a station. If the craft is refused what was taken stays taken. What the
	-- pickup and the craft say goes to `Tell(text, bSuccess)` (as for CraftRecipe), together; a request refused
	-- before anything was taken tells nothing.
	-- @treturn bool Whether it was crafted
	function PLUGIN.craft.CraftFromItem(client, entity, recipeID, Tell)
		local recipe = PLUGIN.craft.recipes[recipeID]
		local itemTable = IsValid(entity) and entity:GetClass() == "ix_item" and entity.GetItemTable and entity:GetItemTable()

		Tell = Tell or function(text)
			client:Notify(text)
		end

		if (!recipe or recipe.station or !itemTable or !PLUGIN.craft.CanPlayerCraft(client) or !recipe:OnCanSee(client)) then
			return false
		end

		local uniqueID = itemTable.uniqueID

		if (!((recipe.requirements and recipe.requirements[uniqueID]) or
			(recipe.interchangeable_req and recipe.interchangeable_req[uniqueID]))) then
			return false
		end

		local interaction = ix.plugin.list.interaction

		if (interaction and interaction.CanUseEntity) then
			if (!interaction:CanUseEntity(client, entity)) then
				return false
			end
		elseif (client:GetShootPos():DistToSqr(entity:NearestPoint(client:GetShootPos())) > 112 * 112) then
			return false
		end

		local inventory = client:GetCharacter():GetInventory()
		local before = ix.stack.Count(inventory, uniqueID)

		-- the stack's own pickup returns false for a merged or partial pickup that did take something, so what is
		-- held decides, not its answer
		local pickupSaid = HoldNotices(client, function()
			ix.item.PerformInventoryAction(client, "take", entity)
		end)

		if (ix.stack.Count(inventory, uniqueID) <= before) then
			-- nothing was taken (no room, or refused): what the pickup said, privately
			Tell(pickupSaid or L("craftCannotTake", client), false)

			return false
		end

		local craftSaid
		local bCrafted = PLUGIN.craft.CraftRecipe(client, recipeID, function(text)
			craftSaid = text
		end)

		local parts = {}

		if (pickupSaid) then
			parts[#parts + 1] = pickupSaid
		end

		if (craftSaid) then
			parts[#parts + 1] = craftSaid
		end

		if (#parts > 0) then
			Tell(table.concat(parts, " "), bCrafted == true)
		end

		return bCrafted == true
	end

	net.Receive("ixCraftFromItem", function(length, client)
		if (RateLimited(client)) then
			return
		end

		local entity = net.ReadEntity()
		local recipeID = net.ReadString()
		local bTold = false

		PLUGIN.craft.CraftFromItem(client, entity, recipeID, function(text, bSuccess)
			bTold = true
			Answer(client, text, bSuccess)
		end)

		-- refused before anything was taken: only the refusal sound
		if (!bTold) then
			Answer(client, "", false)
		end

		Refresh(client)
	end)
end

do
	local COMMAND = {}
	COMMAND.arguments = ix.type.string
	COMMAND.description = "@cmdCraftRecipe"

	function COMMAND:OnRun(client, recipe)
		PLUGIN.craft.CraftRecipe(client, PLUGIN.craft.FindByName(recipe))
	end

	ix.command.Add("CraftRecipe", COMMAND)
end

hook.Add("DoPluginIncludes", "ixCraftPaths", function(path, pluginTable)
	if (!PLUGIN.paths) then
		PLUGIN.paths = {}
	end

	table.insert(PLUGIN.paths, path)
end)
