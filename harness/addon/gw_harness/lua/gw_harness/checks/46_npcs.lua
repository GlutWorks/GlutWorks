-- NPCs (npcspawner, npcdropitems): every spawn group spawns, old spawn points load, and the drop tables only
-- produce existing items.

local Lib = GWH.Lib
local Plugin = Lib.Plugin

GWH.Check("survival: every NPC spawner group spawns", function(fail)
	local plugin = Plugin("npcspawner", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local position = bot:GetPos() + Vector(0, 0, 120)
	local spawned = {}
	local height = 0

	if (!plugin.spawngroups.blackheadcrab) then fail("no black headcrab group") end

	-- removed NPCs linger until the end of the frame, so each spawn gets its own spot
	local function NextPosition()
		height = height + 100
		return position + Vector(0, 0, height)
	end

	for group, classes in SortedPairs(plugin.spawngroups) do
		local npc = plugin:SpawnAt({NextPosition(), group})

		if (!IsValid(npc)) then
			fail(group .. ": nothing spawned")
		else
			if (!table.HasValue(classes, npc:GetClass())) then fail(group .. ": spawned " .. npc:GetClass()) end

			spawned[group] = npc:GetClass()
			npc:Remove()
		end
	end

	-- a point saved with a group that no longer exists falls back instead of erroring
	local npc = plugin:SpawnAt({NextPosition(), "no_such_group"})

	if (!IsValid(npc)) then
		fail("a point with an unknown group spawned nothing")
	else
		npc:Remove()
	end

	-- saves from before this fix can have holes and missing groups
	local points, getData = plugin.spawnpoints, plugin.GetData
	plugin.GetData = function() return {[1] = {position, "zombie"}, [3] = {position}} end
	plugin:LoadData()
	plugin.GetData = getData

	local groups = {}

	for _, v in ipairs(plugin.spawnpoints) do groups[v[2]] = true end

	if (#plugin.spawnpoints != 2 or !groups.zombie or !groups[plugin.defaultGroup]) then
		fail("LoadData did not compact old spawn points and default their groups")
	end

	plugin.spawnpoints = points

	return spawned
end)

GWH.Check("survival: NPC drop tables only produce existing items", function(fail)
	local plugin = Plugin("npcdropitems", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local detail = {}
	local height = 120

	for class, drops in SortedPairs(plugin.drops) do
		local rolled = {}

		for _ = 1, 500 do
			for _, uniqueID in ipairs(plugin:RollDrops(class)) do
				rolled[uniqueID] = (rolled[uniqueID] or 0) + 1
			end
		end

		for uniqueID in pairs(rolled) do
			if (!ix.item.list[uniqueID]) then fail(class .. " drops unknown item " .. uniqueID) end
		end

		if (!next(rolled)) then fail(class .. " dropped nothing in 500 kills") end

		-- one real kill with every drop forced
		local forced = {}

		for _, v in ipairs(drops) do forced[#forced + 1] = {v[1], 1} end

		local npc = ents.Create(class)
		height = height + 150
		npc:SetPos(bot:GetPos() + Vector(0, 0, height))
		npc:Spawn()

		local position = npc:GetPos()
		plugin.drops[class] = forced
		npc:TakeDamage(100000, game.GetWorld(), game.GetWorld())
		plugin.drops[class] = drops

		local found = {}

		for _, v in ipairs(ents.FindInSphere(position, 96)) do
			if (v:GetClass() == "ix_item" and v:GetItemTable()) then
				found[v:GetItemTable().uniqueID] = true
				v:Remove()
			end
		end

		for _, v in ipairs(forced) do
			if (!found[v[1]]) then fail("killing " .. class .. " did not drop " .. v[1]) end
		end

		if (IsValid(npc)) then npc:Remove() end

		detail[class] = rolled
	end

	for _, class in ipairs({"npc_zombie", "npc_headcrab_black"}) do
		if (!plugin.drops[class]) then fail(class .. " has no drops") end
	end

	return detail
end)
