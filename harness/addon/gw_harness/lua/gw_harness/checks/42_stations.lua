-- Stations workstream: station entities, placing and picking up, the smelter, ore nodes,
-- scavenge props, and persistence of all of them through the plugins' SaveData/LoadData.

local function Near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 0.001)
end

local function ClearItems(inventory, uniqueIDs)
	for _, uniqueID in ipairs(uniqueIDs) do
		for _, item in ipairs(inventory:GetItemsByUniqueID(uniqueID)) do
			item:Remove()
		end
	end
end

-- Total quantity of world items of a kind within radius, ignoring ones already being removed.
local function WorldQuantity(uniqueID, center, radius)
	local total, found = 0, {}

	for _, entity in ipairs(ents.FindInSphere(center, radius)) do
		local item, quantity = ix.stack.FromEntity(entity)

		if (item and item.uniqueID == uniqueID and !entity:IsMarkedForDeletion()) then
			total = total + quantity
			found[#found + 1] = entity
		end
	end

	return math.Round(total, 1), found
end

local function RemoveWorldItems(center, radius)
	for _, entity in ipairs(ents.FindInSphere(center, radius)) do
		if (entity:GetClass() == "ix_item") then
			entity:Remove()
		end
	end
end

local function Damage(entity, amount, attacker)
	local info = DamageInfo()
	info:SetDamage(amount)
	info:SetAttacker(attacker)
	info:SetInflictor(attacker)
	info:SetDamageType(DMG_CLUB)
	info:SetDamagePosition(entity:WorldSpaceCenter())
	entity:TakeDamageInfo(info)
end

-- Bots drift (on gm_construct they end up in the pond), so placing starts from a spawn point.
local function StandOnSpawn(bot)
	local spawn = ents.FindByClass("info_player_start")[1] or ents.FindByClass("info_player_*")[1]

	if (IsValid(spawn)) then
		bot:SetPos(spawn:GetPos())
		bot:SetVelocity(-bot:GetVelocity())
	end
end

-- Places a station the way the item's "Place" action does, trying each direction until one has room.
local function PlaceFromItem(bot, inventory, uniqueID)
	StandOnSpawn(bot)

	for _, yaw in ipairs({0, 90, 180, 270}) do
		local item = inventory:GetItemsByUniqueID(uniqueID)[1]
		bot:SetEyeAngles(Angle(45, yaw, 0))

		if (ix.item.PerformInventoryAction(bot, "place", item.id, inventory:GetID())) then
			return true
		end
	end
end

local function NewestStation(stationID)
	local found = ents.FindByClass("ix_station_" .. stationID)

	for i = #found, 1, -1 do
		if (!found[i]:IsMarkedForDeletion()) then
			return found[i]
		end
	end
end

local function Choose(entity, bot, data)
	bot.ixNextStationAction = 0
	entity:OnOptionSelected(bot, "test", data)
end

GWH.Check("stations: every station is a solid, frozen entity with its model", function(fail)
	local stations = ix.plugin.list.ixcraft.craft.stations
	local count = 0

	for stationID, station in SortedPairs(stations) do
		local entity = ents.Create("ix_station_" .. stationID)
		entity:Spawn()
		count = count + 1

		if (entity:GetClass() != "ix_station_" .. stationID or entity:GetStationID() != stationID) then
			fail(stationID .. ": wrong class or station ID " .. entity:GetClass() .. "/" .. entity:GetStationID())
		end

		if (entity:GetModel() != station:GetModel():lower() and entity:GetModel() != station:GetModel()) then
			fail(stationID .. ": model " .. tostring(entity:GetModel()) .. ", expected " .. station:GetModel())
		end

		local physObj = entity:GetPhysicsObject()

		if (!IsValid(physObj)) then
			fail(stationID .. ": no physics object")
		elseif (physObj:IsMotionEnabled()) then
			fail(stationID .. ": physics is not frozen")
		end

		if (tobool(station.smelting) != tobool(entity.ixSmelting)) then
			fail(stationID .. ": smelting state does not match the definition")
		end

		entity:Remove()
	end

	local base = ents.Create("ix_station")
	base:Spawn()

	if (!base:IsMarkedForDeletion()) then
		fail("the bare ix_station base did not remove itself")
		base:Remove()
	end

	return {stations = count}
end)

GWH.Check("stations: placing from the item and picking up round-trips", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = bot:GetCharacter():GetInventory()
	ClearItems(inventory, {"workbench", "smelter"})
	inventory:Add("workbench")

	if (!PlaceFromItem(bot, inventory, "workbench")) then
		return fail("the bot could not place a workbench in any direction")
	end

	local entity = NewestStation("workbench")

	if (!IsValid(entity)) then return fail("no ix_station_workbench after placing") end
	if (ix.stack.Count(inventory, "workbench") != 0) then fail("placing did not consume the item") end
	if (entity:GetOwnerCharacter() != bot:GetCharacter():GetID()) then fail("placed station is not owned by the placer") end

	-- it is where the bot is looking: in front of it, resting on the floor
	if (entity:GetPos():Distance(bot:GetShootPos()) > 160) then fail("placed station is far from the bot") end

	local floor = util.TraceLine({start = entity:GetPos() + Vector(0, 0, 4), endpos = entity:GetPos() - Vector(0, 0, 16), filter = entity})
	if (!floor.Hit) then fail("placed station is not resting on the floor") end

	-- a player who did not place it cannot pick it up (bots are not admins)
	entity:SetOwnerCharacter(entity:GetOwnerCharacter() + 1)
	Choose(entity, bot, {action = "pickup"})
	if (entity:IsMarkedForDeletion() or ix.stack.Count(inventory, "workbench") != 0) then fail("a non-owner picked the station up") end
	entity:SetOwnerCharacter(bot:GetCharacter():GetID())

	Choose(entity, bot, {action = "pickup"})
	if (!entity:IsMarkedForDeletion()) then fail("the owner could not pick the station up") end
	if (ix.stack.Count(inventory, "workbench") != 1) then fail("picking up gave " .. ix.stack.Count(inventory, "workbench") .. " workbench items, expected 1") end

	-- picking up twice in the same frame must not give two items
	Choose(entity, bot, {action = "pickup"})
	if (ix.stack.Count(inventory, "workbench") != 1) then fail("the station was picked up twice") end

	-- a smelter keeps its contents through pickup and placing again
	inventory:Add("smelter")
	ClearItems(inventory, {"coal"})
	ix.stack.Give(inventory, "coal", 1.5)

	if (!PlaceFromItem(bot, inventory, "smelter")) then
		fail("the bot could not place a smelter")
	else
		local smelter = NewestStation("smelter")
		Choose(smelter, bot, {action = "fuel", uniqueID = "coal"})
		if (smelter.ixSmelting.fuel != 60) then fail("smelter fuel is " .. smelter.ixSmelting.fuel .. " after 1.5 kg coal, expected 60") end

		Choose(smelter, bot, {action = "pickup"})
		local item = inventory:GetItemsByUniqueID("smelter")[1]

		if (!item or !istable(item:GetData("smelter")) or item:GetData("smelter").fuel != 60) then
			fail("the smelter item does not carry its fuel")
		elseif (!PlaceFromItem(bot, inventory, "smelter")) then
			fail("the bot could not place the smelter again")
		else
			local again = NewestStation("smelter")
			if (again.ixSmelting.fuel != 60) then fail("the placed-again smelter has fuel " .. again.ixSmelting.fuel .. ", expected 60") end
			again:Remove()
		end
	end

	ClearItems(inventory, {"workbench", "smelter", "coal"})
end)

GWH.Check("smelter: fuel and ore in, exact resources out, through ix.stack", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = bot:GetCharacter():GetInventory()
	local items = {"coal", "coal_ore", "iron_ore", "copper_ore", "iron4_junk", "iron5_junk", "iron", "copper"}
	ClearItems(inventory, items)

	local smelter = ix.station.Spawn("smelter", bot:GetPos() + bot:GetForward() * 48, angle_zero, 0)
	local state = smelter.ixSmelting
	local config = smelter:GetStationTable().smelting

	ix.stack.Give(inventory, "coal", 2)
	ix.stack.Give(inventory, "coal_ore", 1)
	ix.stack.Give(inventory, "iron_ore", 3.5)
	ix.stack.Give(inventory, "copper_ore", 1)
	ix.stack.Give(inventory, "iron4_junk", 1)
	ix.stack.Give(inventory, "iron5_junk", 2)

	-- through the entity menu path, as a client choice arrives
	Choose(smelter, bot, {action = "fuel", uniqueID = "coal"})
	Choose(smelter, bot, {action = "fuel", uniqueID = "coal_ore"})
	Choose(smelter, bot, {action = "smelt", uniqueID = "iron_ore"})
	Choose(smelter, bot, {action = "smelt", uniqueID = "iron4_junk"})
	Choose(smelter, bot, {action = "smelt", uniqueID = "copper_ore"})
	Choose(smelter, bot, {action = "smelt", uniqueID = "iron5_junk"})

	-- 2 kg coal at 4 operations/kg and 1 kg coal ore at 2/kg, in tenths of an operation
	if (state.fuel != 100) then fail("fuel is " .. state.fuel .. ", expected 100") end
	if (ix.stack.Count(inventory, "coal") != 0 or ix.stack.Count(inventory, "coal_ore") != 0) then fail("fuel was not taken from the inventory") end

	-- whole operations only: 3 of the 3.5 kg iron ore
	if (!Near(ix.stack.Count(inventory, "iron_ore"), 0.5)) then fail("iron ore left is " .. ix.stack.Count(inventory, "iron_ore") .. ", expected 0.5") end
	if (ix.stack.Count(inventory, "iron4_junk") != 0 or ix.stack.Count(inventory, "iron5_junk") != 0) then fail("junk was not taken") end

	local expectedQueue = {{"iron_ore", 3}, {"iron4_junk", 1}, {"copper_ore", 1}, {"iron5_junk", 2}}
	if (util.TableToJSON(state.queue) != util.TableToJSON(expectedQueue)) then fail("queue is " .. util.TableToJSON(state.queue)) end

	-- invalid choices change nothing
	local before = util.TableToJSON(state)
	Choose(smelter, bot, {action = "smelt", uniqueID = "coal"})
	Choose(smelter, bot, {action = "fuel", uniqueID = "iron_ore"})
	Choose(smelter, bot, {action = "smelt", uniqueID = "does_not_exist"})
	Choose(smelter, bot, {action = "smelt"})
	Choose(smelter, bot, "smelt")
	if (util.TableToJSON(state) != before) then fail("an invalid choice changed the smelter") end

	-- out of range
	local position = smelter:GetPos()
	smelter:SetPos(position + Vector(0, 0, 4000))
	ix.stack.Give(inventory, "iron_ore", 1)
	Choose(smelter, bot, {action = "smelt", uniqueID = "iron_ore"})
	if (!Near(ix.stack.Count(inventory, "iron_ore"), 1.5)) then fail("a choice from out of range was accepted") end
	smelter:SetPos(position)
	ClearItems(inventory, {"iron_ore"})

	-- it takes time: a partial operation produces nothing
	if (ix.smelting.Advance(smelter, config.time - 1) != 0 or next(state.output)) then fail("output appeared before an operation finished") end
	if (smelter:GetSmeltEnd() <= CurTime()) then fail("the smelter does not report that it is working") end

	if (ix.smelting.Advance(smelter, 1) != 1 or state.output.iron != 5 or state.fuel != 90) then
		fail("the first operation did not give 0.5 kg iron for one operation of fuel: " .. util.TableToJSON(state))
	end

	ix.smelting.Advance(smelter, config.time + 6)
	if (state.progress != 6) then fail("progress is " .. state.progress .. ", expected 6") end
	if (state.output.iron != 10) then fail("after two operations iron is " .. tostring(state.output.iron) .. " tenths, expected 10") end
	if (state.fuel != 80) then fail("after two operations fuel is " .. state.fuel .. ", expected 80") end

	-- everything else: 1 iron ore, the fridge door, the copper ore, two cans = 5 more operations
	local completed = ix.smelting.Advance(smelter, config.time * 10)
	if (completed != 5) then fail("completed " .. completed .. " operations, expected 5") end

	-- 3 x 0.5 iron + 1.5 (door) + 2 x 0.2 (cans) = 3.4 kg iron; 0.5 kg copper; 7 operations of fuel used
	if (state.output.iron != 34 or state.output.copper != 5) then fail("output is " .. util.TableToJSON(state.output)) end
	if (state.fuel != 30 or #state.queue != 0 or state.progress != 0) then fail("after smelting: " .. util.TableToJSON(state)) end
	if (smelter:GetSmeltEnd() != 0) then fail("an idle smelter reports that it is working") end

	-- without input or fuel nothing happens
	if (ix.smelting.Advance(smelter, 100) != 0) then fail("an empty smelter ran") end

	local queued, output = ix.smelting.Decode(smelter:GetSmeltContents())
	if (#queued != 0 or output.iron != 34 or output.copper != 5) then fail("networked contents are " .. smelter:GetSmeltContents()) end

	Choose(smelter, bot, {action = "collect"})
	if (!Near(ix.stack.Count(inventory, "iron"), 3.4) or !Near(ix.stack.Count(inventory, "copper"), 0.5)) then
		fail("collected iron " .. ix.stack.Count(inventory, "iron") .. ", copper " .. ix.stack.Count(inventory, "copper"))
	end
	if (next(state.output)) then fail("output left after collecting: " .. util.TableToJSON(state.output)) end

	-- capacity: the smelter holds 20 operations of fuel; 30 tenths are in, so 4.25 kg coal fits, taken as 4.2 kg
	ix.stack.Give(inventory, "coal", 10)
	Choose(smelter, bot, {action = "fuel", uniqueID = "coal"})
	if (state.fuel != 198 or !Near(ix.stack.Count(inventory, "coal"), 5.8)) then
		fail("fuel capacity: fuel " .. state.fuel .. ", coal left " .. ix.stack.Count(inventory, "coal"))
	end

	-- a full output store pauses smelting until it is collected
	state.output = {iron = config.output * 10}
	ix.stack.Give(inventory, "iron_ore", 1)
	Choose(smelter, bot, {action = "smelt", uniqueID = "iron_ore"})
	if (ix.smelting.Advance(smelter, 100) != 0) then fail("smelted with a full output store") end

	smelter:Remove()
	ClearItems(inventory, items)

	return {operations = 7}
end)

GWH.Check("ore node: stages give their ore and the node respawns", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local node = ents.Create("ix_orenode_iron")
	node:SetPos(bot:GetPos() + Vector(0, 0, 400))
	node:Spawn()

	local center = node:GetPos()
	local expected = 0

	for stage, yield in ipairs(node.yields) do
		if (node:GetStage() != stage) then fail("node is at stage " .. node:GetStage() .. ", expected " .. stage) end

		Damage(node, node.stageHealth - 1, bot)
		if (node:GetStage() != stage or WorldQuantity("iron_ore", center, 256) != expected) then fail("stage " .. stage .. " broke early") end

		Damage(node, 1, bot)
		expected = expected + yield

		local quantity = WorldQuantity("iron_ore", center, 256)
		if (!Near(quantity, expected)) then fail("after stage " .. stage .. " there is " .. quantity .. " kg ore, expected " .. expected) end
	end

	if (expected != 9) then fail("a node yields " .. expected .. " kg, expected 9") end
	if (!node:IsDepleted() or !node:GetNoDraw()) then fail("the node is not depleted after its last stage") end

	local delay = ix.config.Get("oreNodeRespawnTime")
	if (!node.respawnAt or math.abs(node.respawnAt - (os.time() + delay)) > 2) then fail("respawn time is not the configured delay") end

	Damage(node, 1000, bot)
	if (WorldQuantity("iron_ore", center, 256) != 9) then fail("a depleted node gave more ore") end

	node:Think()
	if (!node:IsDepleted()) then fail("the node respawned early") end

	node.respawnAt = os.time() - 1
	node:Think()
	if (node:IsDepleted() or node:GetStage() != 1 or node:GetNoDraw() or node.nodeHealth != node.stageHealth) then fail("the node did not respawn") end

	RemoveWorldItems(center, 256)
	node:Remove()
end)

GWH.Check("scavenge props: physics, yields and respawn", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	for _, class in ipairs({"ix_barrel", "ix_bench", "ix_chair", "ix_pallet"}) do
		local stored = scripted_ents.Get(class)
		local prop = ents.Create(class)
		prop:SetPos(bot:GetPos() + Vector(0, 0, 400))
		prop:Spawn()

		if (!IsValid(prop:GetPhysicsObject())) then fail(class .. ": no physics") end
		if (stored.PrintName == "test1" or !stored.PrintName:find("Scavengeable")) then fail(class .. ": named " .. stored.PrintName) end

		local center = prop:WorldSpaceCenter()
		Damage(prop, prop.scavengeHealth - 1, bot)

		for uniqueID in pairs(prop.yields) do
			if (WorldQuantity(uniqueID, center, 256) != 0) then fail(class .. ": yielded before breaking") end
		end

		Damage(prop, 1, bot)

		for uniqueID, quantity in pairs(prop.yields) do
			local found = WorldQuantity(uniqueID, center, 256)
			if (!Near(found, quantity)) then fail(class .. ": " .. found .. " " .. uniqueID .. ", expected " .. quantity) end
		end

		if (!prop:IsDepleted()) then fail(class .. ": not depleted after scavenging") end

		prop.respawnAt = os.time() - 1
		prop:Think()
		if (prop:IsDepleted() or prop:GetNoDraw() or prop.damage != 0) then fail(class .. ": did not respawn") end

		RemoveWorldItems(center, 256)
		prop:Remove()
	end
end)

GWH.Check("persistence: stations, smelter contents, nodes and props survive save and load", function(fail)
	local bot = GWH.Bot()
	local origin = (IsValid(bot) and bot:GetPos() or vector_origin) + Vector(0, 0, 600)
	local glutcraft, mining, scavenging = ix.plugin.list.glutcraft, ix.plugin.list.mining, ix.plugin.list.scavenging

	local workbench = ix.station.Spawn("workbench", origin, Angle(0, 90, 0), 1234)
	local smelter = ix.station.Spawn("smelter", origin + Vector(100, 0, 0), Angle(0, 45, 0), 5678)
	ix.smelting.Restore(smelter, {fuel = 37, queue = {{"iron_ore", 2}, {"iron4_junk", 1}}, output = {iron = 15}, progress = 4})

	local node = ents.Create("ix_orenode_copper")
	node:SetPos(origin + Vector(200, 0, 0))
	node:Spawn()
	node:SetStage(3)
	node:ApplyStage()
	node.nodeHealth = 50

	local depleted = ents.Create("ix_orenode_coal")
	depleted:SetPos(origin + Vector(300, 0, 0))
	depleted:Spawn()
	depleted:Deplete(os.time() + 777)

	local barrel = ents.Create("ix_barrel")
	barrel:SetPos(origin + Vector(400, 0, 0))
	barrel:Spawn()
	barrel:Deplete(os.time() + 555)

	local expected = {
		{workbench, "ix_station_workbench"}, {smelter, "ix_station_smelter"}, {node, "ix_orenode_copper"},
		{depleted, "ix_orenode_coal"}, {barrel, "ix_barrel"}
	}

	for _, v in ipairs(expected) do v[3] = v[1]:GetPos() end

	glutcraft:SaveData()
	mining:SaveData()
	scavenging:SaveData()

	-- remove everything that was saved, then read the files back from disk as after a restart
	local old = {}

	for _, entity in ents.Iterator() do
		if (entity.IsStation or entity.IsOreNode or entity.IsScavengeable) then
			old[entity] = true
			entity:Remove()
		end
	end

	for _, key in ipairs({"glutcraft", "mining", "scavenging"}) do
		ix.data.stored[key] = nil
	end

	glutcraft:LoadData()
	mining:LoadData()
	scavenging:LoadData()

	local restored = {}

	for _, v in ipairs(expected) do
		for _, entity in ipairs(ents.FindByClass(v[2])) do
			if (!old[entity] and !entity:IsMarkedForDeletion() and entity:GetPos():Distance(v[3]) < 1) then
				restored[v[2]] = entity
			end
		end

		if (!restored[v[2]]) then fail(v[2] .. " was not restored at its position") end
	end

	local w, s = restored.ix_station_workbench, restored.ix_station_smelter

	if (w and (w:GetOwnerCharacter() != 1234 or math.abs(w:GetAngles().y - 90) > 1)) then fail("workbench owner or angle not restored") end

	if (s) then
		local state = s.ixSmelting
		local json = util.TableToJSON({state.fuel, state.queue, state.output, state.progress})

		if (json != util.TableToJSON({37, {{"iron_ore", 2}, {"iron4_junk", 1}}, {iron = 15}, 4})) then fail("smelter contents restored as " .. json) end
		if (s:GetOwnerCharacter() != 5678) then fail("smelter owner not restored") end
		if (!ix.smelting.entities[s]) then fail("restored smelter is not ticking") end
	end

	local n = restored.ix_orenode_copper
	if (n and (n:GetStage() != 3 or n.nodeHealth != 50 or n:IsDepleted())) then fail("ore node stage/health not restored") end

	local d = restored.ix_orenode_coal
	if (d and (!d:IsDepleted() or math.abs(d.respawnAt - (os.time() + 777)) > 2 or !d:GetNoDraw())) then fail("depleted node not restored as depleted") end

	local b = restored.ix_barrel
	if (b and (!b:IsDepleted() or math.abs(b.respawnAt - (os.time() + 555)) > 2)) then fail("scavenged barrel not restored as scavenged") end

	for _, entity in ents.Iterator() do
		if (!old[entity] and (entity.IsStation or entity.IsOreNode or entity.IsScavengeable)) then
			entity:Remove()
		end
	end
end)
