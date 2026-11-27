-- Fixes from the world review: knockouts decided after the hit, actions refused while downed,
-- dead or tied, station/ore/prop persistence, station reach, poison per character, and
-- ragdollstate keeping Helix's tracebacks. Each check restores the bot afterwards.

-- Runs fn(defer); everything deferred runs afterwards in reverse order, even if fn errors.
local function Scoped(fn)
	local deferred = {}
	local ok, result = xpcall(fn, debug.traceback, function(cleanup)
		deferred[#deferred + 1] = cleanup
	end)

	for i = #deferred, 1, -1 do
		local bCleaned, err = pcall(deferred[i])

		if (!bCleaned) then ErrorNoHalt("52_world_review cleanup: " .. tostring(err) .. "\n") end
	end

	if (!ok) then error(result, 0) end

	return result
end

local function Damage(target, amount, damageType)
	local info = DamageInfo()
		info:SetDamage(amount)
		info:SetDamageType(damageType or DMG_GENERIC)
		info:SetAttacker(game.GetWorld())
		info:SetInflictor(game.GetWorld())
		info:SetDamagePosition(target:GetPos())
	target:TakeDamageInfo(info)
end

-- Alive, on its feet, untied, full health, no armour, standing still.
local function ResetBot(bot)
	if (!bot:Alive()) then
		bot:Spawn()
	end

	if (bot:IsRestricted()) then
		bot:SetRestricted(false)
	end

	if (IsValid(bot.ixRagdoll)) then
		bot.ixRagdoll.ixWeapons = nil
		bot:SetRagdolled(false)
	end

	if (bot:HasGodMode()) then
		bot:GodDisable()
	end

	bot.ixRagdoll = nil
	bot.ixKnockoutGrace = nil
	bot:SetNetVar("deathTime", nil)
	bot:SetHealth(100)
	bot:SetArmor(0)
	bot:SetLocalVelocity(vector_origin)
end

local function Downed(bot)
	return IsValid(bot.ixRagdoll) and !bot.ixRagdoll:IsMarkedForDeletion()
end

-- The steps of Helix's ixEntityMenuSelect receiver for a station (which has no OnSelect<option>).
-- Returns false when Helix's CanPlayerInteractEntity refused it.
local function Select(entity, client, data)
	if (hook.Run("CanPlayerInteractEntity", client, entity, "test", data) == false) then
		return false
	end

	client.ixNextStationAction = 0
	entity:OnOptionSelected(client, "test", data)

	return true
end

local function Fuel(entity)
	return entity.ixSmelting and entity.ixSmelting.fuel or 0
end

local function Coal(inventory)
	return ix.stack.Count(inventory, "coal")
end

local function RemoveAll(inventory, uniqueID)
	for _, v in pairs(inventory:GetItemsByUniqueID(uniqueID)) do
		v:Remove()
	end
end

local function Live(class)
	local result = {}

	for _, v in ipairs(ents.FindByClass(class)) do
		if (!v:IsMarkedForDeletion()) then
			result[#result + 1] = v
		end
	end

	return result
end

GWH.Check("world review: knockout is decided from the health the hit left", function(fail)
	local bot = GWH.Bot()
	if (!bot or !ix.plugin.list.customdamage) then return fail("no bot or customdamage") end

	local threshold = ix.config.Get("unconsciousHealth", 20)
	local detail = {}

	Scoped(function(defer)
		defer(function() ResetBot(bot) end)

		-- armour takes most of an 85 point hit, so the character stays well above the threshold
		ResetBot(bot)
		bot:SetArmor(100)
		Damage(bot, 85)
		detail.armour = {health = bot:Health(), armour = bot:Armor(), downed = Downed(bot)}

		if (bot:Health() <= 100 - 85) then
			fail("armour absorbed nothing (health " .. bot:Health() .. "), so the scenario does not apply")
		elseif (bot:Health() >= threshold and Downed(bot)) then
			fail("an armoured hit leaving " .. bot:Health() .. " health knocked the character out")
		end

		-- god mode (an admin in observer): no damage and no ragdoll
		ResetBot(bot)
		bot:GodEnable()
		Damage(bot, 85)
		detail.god = {health = bot:Health(), downed = Downed(bot), god = bot:HasGodMode()}

		if (Downed(bot)) then fail("a player in god mode was knocked out") end
		if (bot:Health() != 100) then fail("a player in god mode took damage: health " .. bot:Health()) end
		if (!bot:HasGodMode()) then fail("god mode was switched off by the hit") end

		Damage(bot, 40, DMG_FALL)
		if (Downed(bot)) then fail("a player in god mode fell over from fall damage") end

		-- a plain hit that does cross the threshold still knocks out, and falling still falls over
		ResetBot(bot)
		Damage(bot, 85)
		detail.plain = {health = bot:Health(), downed = Downed(bot)}

		if (bot:Health() >= threshold) then
			fail("an unarmoured 85 point hit left " .. bot:Health() .. " health")
		elseif (!Downed(bot) or !bot.ixRagdoll.ixKnockout) then
			fail("a hit leaving " .. bot:Health() .. " health did not knock the character out")
		end

		ResetBot(bot)
		Damage(bot, 30, DMG_FALL)
		detail.fall = {health = bot:Health(), downed = Downed(bot)}

		if (!Downed(bot)) then
			fail("30 fall damage did not make the character fall over")
		elseif (bot.ixRagdoll.ixKnockout) then
			fail("falling at 70 health counted as a knockout")
		end

		-- a hit that kills does not leave a knockout behind
		ResetBot(bot)
		bot:SetHealth(10)
		Damage(bot, 50)
		if (bot:Alive()) then fail("a 50 point hit at 10 health did not kill") end
	end)

	return detail
end)

GWH.Check("world review: /KickDoor refuses a downed, dead or tied player", function(fail)
	local bot = GWH.Bot()
	local kick = ix.plugin.list.kickdoor
	if (!bot or !kick) then return fail("no bot or kickdoor") end

	Scoped(function(defer)
		local team = bot:Team()
		defer(function() bot:SetTeam(team) ResetBot(bot) end)

		ResetBot(bot)

		local door = ents.Create("prop_door_rotating")
		door:SetModel("models/props_c17/door01_left.mdl")
		door:SetKeyValue("hardware", "1")
		door:SetKeyValue("distance", "90")
		door:SetKeyValue("returndelay", "-1")
		door:SetPos(bot:GetPos() + Vector(80, 0, 54))
		door:Spawn()
		door:Activate()
		defer(function() door:Remove() end)

		bot:SetTeam(FACTION_MPF)

		local function Ready()
			bot:SetLocalVar("stm", 100)
			bot.ixNextKick = nil
			bot:SetLocalVelocity(vector_origin)
		end

		Ready()
		local bCanKick, message = kick:CanKick(bot, door)

		if (!bCanKick) then
			return fail("a still Combine bot 80 units from a door cannot kick it: " .. tostring(message))
		end

		bot:SetRagdolled(true)
		Ready()
		if (kick:CanKick(bot, door)) then fail("a knocked-out player can kick a door") end
		ResetBot(bot)

		bot:SetRestricted(true)
		Ready()
		if (kick:CanKick(bot, door)) then fail("a tied player can kick a door") end
		ResetBot(bot)

		local position = bot:GetPos()
		bot:Kill()
		bot:SetPos(position)
		Ready()
		if (kick:CanKick(bot, door)) then fail("a dead player can kick a door") end
	end)
end)

-- Item actions (eat, drink, fill, place a station) go through Helix's CanPlayerInteractItem,
-- which already refuses these states; this confirms nothing in the schema overrides that.
GWH.Check("world review: item actions refuse a downed, dead or tied player", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = bot:GetCharacter():GetInventory()

	Scoped(function(defer)
		defer(function() ResetBot(bot) RemoveAll(inventory, "water") RemoveAll(inventory, "workbench") end)

		for _, state in ipairs({"downed", "tied", "dead"}) do
			ResetBot(bot)
			RemoveAll(inventory, "water")
			RemoveAll(inventory, "workbench")
			inventory:Add("water")
			inventory:Add("workbench")

			local water, workbench = inventory:HasItem("water"), inventory:HasItem("workbench")
			local stations = #Live("ix_station_workbench")

			if (state == "downed") then
				bot:SetRagdolled(true)
			elseif (state == "tied") then
				bot:SetRestricted(true)
			else
				bot:Kill()
			end

			ix.item.PerformInventoryAction(bot, "Drink", water:GetID(), inventory:GetID())
			ix.item.PerformInventoryAction(bot, "place", workbench:GetID(), inventory:GetID())

			if (!inventory:GetItemByID(water:GetID())) then fail("a " .. state .. " player could drink") end
			if (!inventory:GetItemByID(workbench:GetID()) or #Live("ix_station_workbench") != stations) then
				fail("a " .. state .. " player could place a station")
			end
		end
	end)
end)

GWH.Check("world review: station options refuse a downed player", function(fail)
	local bot = GWH.Bot()
	if (!bot or !ix.station) then return fail("no bot or ix.station") end

	local inventory = bot:GetCharacter():GetInventory()

	Scoped(function(defer)
		local home = bot:GetPos()
		defer(function() bot:SetPos(home) end)
		defer(function() ResetBot(bot) RemoveAll(inventory, "coal") end)

		ResetBot(bot)
		RemoveAll(inventory, "coal")
		ix.stack.Give(inventory, "coal", 4)

		local smelter = ix.station.Spawn("smelter", bot:GetPos() + Vector(0, 0, 600), angle_zero, bot:GetCharacter():GetID())
		if (!IsValid(smelter)) then return fail("could not spawn a smelter") end
		defer(function() smelter:Remove() end)

		bot:SetPos(smelter:GetPos() + Vector(60, 0, 0))
		bot:SetRagdolled(true)
		Select(smelter, bot, {action = "fuel", uniqueID = "coal"})
		Select(smelter, bot, {action = "pickup"})

		if (Fuel(smelter) != 0 or Coal(inventory) != 4) then fail("a knocked-out player fuelled the smelter") end
		if (smelter:IsMarkedForDeletion()) then fail("a knocked-out player picked the smelter up") end

		-- the same choices on their feet work, so the refusal was the downed state
		ResetBot(bot)
		bot:SetPos(smelter:GetPos() + Vector(60, 0, 0))
		Select(smelter, bot, {action = "fuel", uniqueID = "coal"})

		if (Fuel(smelter) == 0) then fail("a standing player next to the smelter could not fuel it") end
	end)
end)

GWH.Check("world review: station options reach the whole large smelter", function(fail)
	local bot = GWH.Bot()
	if (!bot or !ix.station) then return fail("no bot or ix.station") end

	local inventory = bot:GetCharacter():GetInventory()
	local detail = {}

	Scoped(function(defer)
		local home = bot:GetPos()
		defer(function() bot:SetPos(home) end)
		defer(function() ResetBot(bot) RemoveAll(inventory, "coal") end)

		ResetBot(bot)
		RemoveAll(inventory, "coal")
		ix.stack.Give(inventory, "coal", 10)

		local smelter = ix.station.Spawn("large_smelter", bot:GetPos() + Vector(0, 0, 800), angle_zero, 0)
		if (!IsValid(smelter)) then return fail("could not spawn a large smelter") end
		defer(function() smelter:Remove() end)

		-- standing at the end of its longest side, close to the wall but over 96 units from the origin
		local mins, maxs = smelter:OBBMins(), smelter:OBBMaxs()
		local center = (mins + maxs) / 2
		local bLong = (maxs.x - mins.x) >= (maxs.y - mins.y)
		local extent = bLong and maxs.x or maxs.y
		local gap = math.max(40, 100 - extent)
		local spot = smelter:LocalToWorld(bLong and Vector(maxs.x + gap, center.y, mins.z) or Vector(center.x, maxs.y + gap, mins.z))

		bot:SetPos(spot)

		local origin = bot:GetPos():Distance(smelter:GetPos())
		local surface = bot:GetShootPos():Distance(smelter:NearestPoint(bot:GetShootPos()))
		detail.size = {maxs - mins}
		detail.origin = math.Round(origin)
		detail.surface = math.Round(surface)

		if (origin <= 96 or surface > 120) then
			return fail("could not stand within reach of the wall and 96+ units from the origin (origin "
				.. math.Round(origin) .. ", surface " .. math.Round(surface) .. ")")
		end

		if (!Select(smelter, bot, {action = "fuel", uniqueID = "coal"})) then
			fail("Helix refused a station option " .. math.Round(surface) .. " units from the smelter's wall")
		elseif (Fuel(smelter) == 0) then
			fail("fuelling from the far end of the large smelter did nothing")
		end

		-- the station's own range check still applies
		local fuel = Fuel(smelter)
		bot:SetPos(spot + (spot - smelter:GetPos()):GetNormalized() * 200)
		Select(smelter, bot, {action = "fuel", uniqueID = "coal"})

		if (Fuel(smelter) != fuel) then fail("a player 200 units further out fuelled the smelter") end

		-- and other entities keep Helix's own distance check
		local prop = ents.Create("prop_physics")
		prop:SetModel("models/props_junk/wood_crate001a.mdl")
		prop:SetPos(bot:GetPos() + Vector(0, 300, 0))
		prop:Spawn()
		defer(function() prop:Remove() end)

		if (hook.Run("CanPlayerInteractEntity", bot, prop, "test", {}) != false) then
			fail("a prop 300 units away passes CanPlayerInteractEntity")
		end
	end)

	return detail
end)

GWH.Check("world review: stations, ore nodes and props are kept out of Helix persistence", function(fail)
	local bot = GWH.Bot()
	local persist = properties.List.persist
	if (!bot or !persist) then return fail("no bot or persist property") end

	Scoped(function(defer)
		local group = bot:GetUserGroup()
		bot:SetUserGroup("superadmin")
		defer(function() bot:SetUserGroup(group) end)

		local classes = {}

		for stationID in SortedPairs(ix.plugin.list.ixcraft.craft.stations) do
			classes[#classes + 1] = "ix_station_" .. stationID
		end

		for _, class in ipairs({"ix_orenode_coal", "ix_orenode_iron", "ix_barrel", "ix_pallet"}) do
			classes[#classes + 1] = class
		end

		for i, class in ipairs(classes) do
			local entity = ents.Create(class)
			entity:SetPos(bot:GetPos() + Vector(i * 150, 0, 600))
			entity:Spawn()

			if (persist:Filter(entity, bot)) then
				fail(class .. " can be marked persistent by Helix's persistence plugin, which would load a second copy")
			end

			entity:Remove()
		end
	end)
end)

GWH.Check("world review: spawn-menu stations, nodes and props are saved", function(fail)
	local bot = GWH.Bot()
	local mining, scavenging = ix.plugin.list.mining, ix.plugin.list.scavenging
	if (!bot or !ix.station or !mining or !scavenging) then return fail("no bot or plugins") end

	local detail = {}

	Scoped(function(defer)
		ResetBot(bot)
		defer(function() ResetBot(bot) end)

		local position = bot:GetPos() + Vector(0, 0, 900)
		local trace = {HitPos = position, HitNormal = Vector(0, 0, 1), Hit = true}
		local workbench

		for _, v in ipairs({{"ix_station_workbench", "ixStationSave"}, {"ix_orenode_iron", "ixMiningSave"}, {"ix_barrel", "ixScavengingSave"}}) do
			timer.Remove(v[2])

			local entity = scripted_ents.Get(v[1]):SpawnFunction(bot, trace, v[1])
			defer(function() if (IsValid(entity)) then entity:Remove() end end)
			workbench = workbench or entity

			if (!IsValid(entity)) then
				fail(v[1] .. ": SpawnFunction made nothing")
			elseif (!timer.Exists(v[2])) then
				fail(v[1] .. ": spawning it from the spawn menu does not save it")
			end

			trace.HitPos = trace.HitPos + Vector(200, 0, 0)
		end

		-- the spawned workbench survives a save and load exactly once
		if (!IsValid(workbench)) then return end

		local spot = workbench:GetPos()

		ix.station.Save()

		local old = {}

		for _, entity in ipairs(Live("ix_station_workbench")) do
			old[entity] = true
			entity:Remove()
		end

		ix.data.stored.glutcraft = nil
		ix.station.Load()

		local copies = 0

		for _, entity in ipairs(Live("ix_station_workbench")) do
			if (!old[entity] and entity:GetPos():Distance(spot) < 1) then
				copies = copies + 1
				defer(function() entity:Remove() end)
			end
		end

		detail.copies = copies

		if (copies != 1) then fail("the spawned workbench came back " .. copies .. " times after a save and load") end
	end)

	ix.station.Save()

	return detail
end)

GWH.Check("world review: records that cannot be spawned are kept on save", function(fail)
	local glutcraft, mining, scavenging = ix.plugin.list.glutcraft, ix.plugin.list.mining, ix.plugin.list.scavenging
	if (!glutcraft or !mining or !scavenging or !ix.station) then return fail("no plugins") end

	local function Has(data, key, value)
		for _, v in ipairs(data) do
			if (istable(v) and v[key] == value) then return true end
		end
	end

	local cases = {
		{plugin = glutcraft, key = "station", value = "gw_renamed_station", load = ix.station.Load, save = ix.station.Save,
			record = {station = "gw_renamed_station", pos = Vector(1, 2, 3), ang = angle_zero, owner = 7, smelter = {fuel = 30}}},
		{plugin = mining, key = "class", value = "ix_orenode_gw_removed", load = function() mining:LoadData() end, save = function() mining:SaveNodes() end,
			record = {class = "ix_orenode_gw_removed", pos = Vector(4, 5, 6), ang = angle_zero, stage = 2}},
		{plugin = scavenging, key = "class", value = "ix_gw_removed_prop", load = function() scavenging:LoadData() end, save = function() scavenging:SaveProps() end,
			record = {class = "ix_gw_removed_prop", pos = Vector(7, 8, 9), ang = angle_zero, damage = 3}}
	}

	for _, case in ipairs(cases) do
		case.plugin:SetData({case.record})
		case.load()
		case.save()

		local saved = case.plugin:GetData()

		if (!Has(saved, case.key, case.value)) then
			fail(case.plugin.uniqueID .. ": the unspawnable record " .. case.value .. " was dropped by the next save")
		end

		-- and again after a second load and save, with its data intact
		ix.data.stored[case.plugin.uniqueID] = nil
		case.load()
		case.save()
		saved = case.plugin:GetData()

		for _, v in ipairs(saved) do
			if (istable(v) and v[case.key] == case.value and (!isvector(v.pos) or v.pos != case.record.pos)) then
				fail(case.plugin.uniqueID .. ": the kept record's position changed to " .. tostring(v.pos))
			end
		end

		if (!Has(saved, case.key, case.value)) then fail(case.plugin.uniqueID .. ": the record was lost on the second save") end

		-- leave no test record behind
		case.plugin:SetData({})
		case.load()
		case.save()
	end
end)

GWH.Check("world review: poison stops when the character changes or dies", function(fail)
	local bot = GWH.Bot()
	local gland = ix.item.list.poison_headcrab_gland
	if (!bot or !gland) then return fail("no bot or poison gland") end

	local name = "ixPoison" .. bot:SteamID64()

	Scoped(function(defer)
		defer(function() timer.Remove(name) ResetBot(bot) end)

		-- keep the tick so it can be run by hand
		local function Eat()
			local create, tick = timer.Create, nil

			timer.Create = function(identifier, delay, repetitions, callback)
				if (identifier == name) then tick = callback end
				return create(identifier, delay, repetitions, callback)
			end

			local ok, err = pcall(gland.OnConsumed, gland, bot)
			timer.Create = create

			if (!ok) then error(err, 0) end

			return tick
		end

		ResetBot(bot)
		local tick = Eat()
		if (!tick) then return fail("eating the gland started no poison timer") end

		tick()
		if (bot:Health() >= 100) then fail("the poison did no damage to the character that ate it") end

		-- switched to another character: the next tick does nothing
		local id = bot:GetNetVar("char")
		defer(function() bot:SetNetVar("char", id) end)

		bot:SetHealth(100)
		bot:SetNetVar("char", nil)
		tick()
		bot:SetNetVar("char", id)

		if (bot:Health() != 100) then fail("the poison hurt the player after they switched character") end
		if (timer.Exists(name)) then fail("the poison timer kept running after a character switch") end

		-- died: the timer is gone at once
		ResetBot(bot)
		Eat()
		bot:Kill()

		if (timer.Exists(name)) then fail("the poison timer survived the character's death") end
	end)
end)

GWH.Check("world review: errors inside Helix's SetRagdolled keep their traceback", function(fail)
	local bot = GWH.Bot()
	if (!bot or !ix.plugin.list.ragdollstate) then return fail("no bot or ragdollstate") end

	local playerMeta = FindMetaTable("Player")
	local createRagdoll, timerCreate = playerMeta.CreateServerRagdoll, timer.Create
	local message

	ResetBot(bot)

	playerMeta.CreateServerRagdoll = function()
		error("gw_harness ragdoll failure")
	end

	local ok, err = pcall(bot.SetRagdolled, bot, true, 5)
	playerMeta.CreateServerRagdoll = createRagdoll
	message = tostring(err)

	if (timer.Create != timerCreate) then
		timer.Create = timerCreate
		fail("timer.Create was not put back after the error")
	end

	if (ok) then
		fail("the error inside SetRagdolled was swallowed")
	else
		if (!string.find(message, "gw_harness ragdoll failure", 1, true)) then fail("the error message was lost: " .. message) end
		if (!string.find(message, "stack traceback", 1, true)) then fail("the error lost its traceback: " .. message) end
	end

	ResetBot(bot)

	return {message = string.Left(message, 300)}
end)
