-- Plugin hygiene: receivers refuse what a sender may not touch, and door ownership and
-- child dispensers survive a restart.

local nextCharacterID = 900000000

-- A second player, for "someone else". Bot characters are created during the join itself.
local function OtherBot()
	if (!IsValid(GWH.hygieneBot)) then
		GWH.hygieneBot = player.CreateNextBot("GWH Hygiene")
	end

	local bot = GWH.hygieneBot

	if (!IsValid(bot) or !bot:GetCharacter()) then
		error("could not create a second bot with a character")
	end

	return bot
end

--- Runs fn, then every cleanup in reverse order, whether or not fn threw. One cleanup failing does not skip the
-- rest, so a broken check cannot leave the bots in a state that fails later ones.
local function Scoped(fn)
	local cleanups = {}
	local ok, result = xpcall(fn, debug.traceback, function(cleanup)
		cleanups[#cleanups + 1] = cleanup
	end)

	for i = #cleanups, 1, -1 do
		local bCleaned, fault = xpcall(cleanups[i], debug.traceback)

		if (!bCleaned and ok) then
			ok, result = false, fault
		end
	end

	if (!ok) then error(result, 0) end

	return result
end

local function Replace(defer, target, key, value)
	local original = target[key]
	target[key] = value
	defer(function() target[key] = original end)
end

--- Calls a net receiver as though `client` had sent `values`, in read order.
local function Receive(receiver, client, values)
	Scoped(function(defer)
		local index = 0

		for _, name in ipairs({"ReadEntity", "ReadUInt", "ReadString", "ReadTable"}) do
			Replace(defer, net, name, function()
				index = index + 1
				return values[index]
			end)
		end

		receiver(0, client)
	end)
end

local function MakeAdmin(defer, client)
	local group = client:GetUserGroup()
	client:SetUserGroup("superadmin")
	defer(function() client:SetUserGroup(group) end)
end

local function NewCharacter(client)
	nextCharacterID = nextCharacterID + 1

	local current = client:GetCharacter()
	local id = nextCharacterID
	local character = ix.char.New({
		name = "Hygiene " .. id,
		faction = ix.faction.indices[current:GetFaction()].uniqueID,
		model = current:GetModel()
	}, id, client, client:SteamID64())
	character.isBot = true

	local inventory = ix.inventory.Create(ix.config.Get("inventoryWidth"), ix.config.Get("inventoryHeight"), id)
	inventory:SetOwner(id)
	inventory.noSave = true
	character.vars.inv = {inventory}
	ix.char.loaded[id] = character

	return character
end

-- The same steps as Helix's ixCharacterChoose receiver. The character is changed even if a hook throws.
local function Switch(client, character)
	local previous = client:GetCharacter()
	local bBefore, beforeFault = xpcall(hook.Run, debug.traceback, "PrePlayerLoadedCharacter", client, character, previous)

	character:Setup(true)
	client:Spawn()
	hook.Run("PlayerLoadedCharacter", client, character, previous)

	if (!bBefore) then error(beforeFault, 0) end
end

local function GiveItem(inventory, uniqueID)
	local before = {}

	for item in inventory:Iter() do before[item.id] = true end

	local x, fault = inventory:Add(uniqueID)

	if (!x) then error("could not add " .. uniqueID .. ": " .. tostring(fault)) end

	for item in inventory:Iter() do
		if (!before[item.id] and item.uniqueID == uniqueID) then return item end
	end

	error(uniqueID .. " was added but is not in the inventory")
end

local function ItemEntities()
	local result = {}

	for _, v in ipairs(ents.FindByClass("ix_item")) do result[v] = true end

	return result
end

local function NewItemEntities(before)
	local result = {}

	for _, v in ipairs(ents.FindByClass("ix_item")) do
		if (!before[v]) then result[#result + 1] = v end
	end

	return result
end

-- gm_construct has no doors, so stand-ins are given map creation IDs.
local function DoorWorld(defer)
	local entityMeta = FindMetaTable("Entity")
	local originalID, originalLookup = entityMeta.MapCreationID, ents.GetMapCreatedEntity
	local ids, doors = {}, {}

	Replace(defer, entityMeta, "MapCreationID", function(self) return ids[self] or originalID(self) end)
	Replace(defer, ents, "GetMapCreatedEntity", function(id)
		if (doors[id] != nil) then return doors[id] end
		return originalLookup(id)
	end)

	defer(function()
		for _, v in pairs(doors) do
			if (IsValid(v)) then v:Remove() end
		end
	end)

	return function(id)
		if (IsValid(doors[id])) then doors[id]:Remove() end

		local door = ents.Create("prop_door_rotating")
		door:SetModel("models/props_c17/door01_left.mdl")
		door:SetPos(Vector(0, 0, 400 + (id % 10) * 128))
		door:Spawn()
		door:SetNetVar("ownable", true)
		door:SetNetVar("price", 0)

		ids[door], doors[id] = id, door

		return door
	end
end

local function DoorSaver(defer)
	local plugin = ix.plugin.list.door_saver

	for _, key in ipairs({"DOORS_BUFFER", "DOORS_ACCESS_BUFFER", "DOORS_TITLES_BUFFER"}) do
		Replace(defer, plugin, key, {})
	end

	defer(function()
		plugin:SetData({})
	end)

	return plugin
end

local function DoorCommand(defer, name, client, door)
	return Scoped(function(inner)
		Replace(inner, util, "TraceLine", function() return {Entity = door} end)
		return ix.command.list[name]:OnRun(client)
	end)
end

-- Throws away everything in memory, as a server restart would, and loads the save.
local function Restart(plugin, makeDoor, id)
	plugin.DOORS_BUFFER, plugin.DOORS_ACCESS_BUFFER, plugin.DOORS_TITLES_BUFFER = {}, {}, {}
	ix.data.stored.door_saver = nil

	local door = makeDoor(id)
	plugin:LoadData()

	if (plugin.PostLoadData) then
		plugin:PostLoadData()
	end

	return door
end

GWH.Check("hygiene: door ownership and access survive a restart", function(fail)
	return Scoped(function(defer)
		local owner, guest = GWH.Bot(), OtherBot()
		local ownerChar, guestChar = owner:GetCharacter(), guest:GetCharacter()
		local makeDoor = DoorWorld(defer)
		local plugin = DoorSaver(defer)
		local ID = 90001

		defer(function()
			if (owner:GetCharacter() != ownerChar) then Switch(owner, ownerChar) end
		end)
		defer(function()
			if (guest:GetCharacter() != guestChar) then Switch(guest, guestChar) end
		end)

		local function Expect(condition, message)
			if (!condition) then fail(message) end
		end

		local door = makeDoor(ID)
		DoorCommand(defer, "doorbuy", owner, door)

		Expect(door:GetDTEntity(0) == owner, "buying did not make the bot the owner")
		Expect(plugin.DOORS_BUFFER[ID] == ownerChar:GetID(), "the purchase was not recorded")

		-- the owner grants tenant access through the doors plugin's own receiver
		Receive(net.Receivers.ixdoorpermission, owner, {door, guest, DOOR_TENANT})
		Expect(door.ixAccess[guest] == DOOR_TENANT, "granting access had no effect")

		plugin:SaveData()

		local ownerAlt, guestAlt = NewCharacter(owner), NewCharacter(guest)
		Switch(guest, guestAlt)
		Expect((door.ixAccess[guest] or 0) == 0, "another character of the guest inherited their access")

		Switch(owner, ownerAlt)
		Expect(!IsValid(door:GetDTEntity(0)), "the door is still held after the owner switched character")
		Expect(!door:GetNetVar("ownable"), "an offline owner's door can be bought")

		door = Restart(plugin, makeDoor, ID)

		Expect(plugin.DOORS_BUFFER[ID] == ownerChar:GetID(), "ownership was not loaded")
		Expect(!door:GetNetVar("ownable"), "a loaded door can be bought before its owner returns")
		Expect(!IsValid(door:GetDTEntity(0)), "a loaded door is held although the owner's character is not played")

		Switch(owner, ownerChar)
		Expect(door:GetDTEntity(0) == owner, "the owner did not get the door back")
		Expect(door:GetNetVar("ownable") == true, "the returned door was not marked ownable")
		Expect(door.ixAccess and door.ixAccess[owner] == DOOR_OWNER, "the owner has no owner access")
		Expect(door.ixAccess and (door.ixAccess[guest] or 0) == 0, "the wrong character of the guest got access")

		Switch(guest, guestChar)
		Expect(door.ixAccess and door.ixAccess[guest] == DOOR_TENANT, "access did not return with the guest's character")

		Switch(guest, guestAlt)
		Switch(guest, guestChar)
		Expect(door.ixAccess and door.ixAccess[guest] == DOOR_TENANT, "access was lost by switching away and back")

		-- hook order is undefined: the doors plugin may strip the door before door_saver sees the disconnect
		ix.plugin.list.doors:PlayerDisconnected(owner)
		plugin:PlayerDisconnected(owner)
		Expect(!door:GetNetVar("ownable"), "the door can be bought after its owner disconnected")

		door = Restart(plugin, makeDoor, ID)
		Expect(door:GetDTEntity(0) == owner, "a load with the owner connected (map cleanup) did not return the door")
		Expect(door.ixAccess and door.ixAccess[guest] == DOOR_TENANT, "access was lost across a disconnect")

		-- revoking sticks
		Receive(net.Receivers.ixdoorpermission, owner, {door, guest, DOOR_NONE})
		Switch(owner, ownerAlt)
		Switch(owner, ownerChar)
		Expect((door.ixAccess[guest] or 0) == 0, "revoked access came back")

		Receive(net.Receivers.ixdoorpermission, owner, {door, guest, DOOR_GUEST})
		plugin:SaveData()
		plugin:CharacterDeleted(guest, guestChar:GetID())
		Expect(!(plugin.DOORS_ACCESS_BUFFER[ID] or {})[guestChar:GetID()], "a deleted character keeps saved access")

		DoorCommand(defer, "doorsell", owner, door)
		Expect(plugin.DOORS_BUFFER[ID] == nil, "selling did not forget the door")
		Expect(plugin.DOORS_ACCESS_BUFFER[ID] == nil, "selling kept the access list")
		Expect(door:GetNetVar("ownable") == true, "a sold door cannot be bought")

		DoorCommand(defer, "doorbuy", owner, door)
		Switch(owner, ownerAlt)
		plugin:CharacterDeleted(owner, ownerChar:GetID())
		Expect(plugin.DOORS_BUFFER[ID] == nil, "a deleted character still owns a door")
		Expect(door:GetNetVar("ownable") == true, "a deleted character's door cannot be bought")
	end)
end)

GWH.Check("hygiene: old door save loads without errors", function(fail)
	return Scoped(function(defer)
		local owner = GWH.Bot()
		local ownerChar = owner:GetCharacter()
		local makeDoor = DoorWorld(defer)
		local plugin = DoorSaver(defer)
		local ID = 90002

		defer(function()
			if (owner:GetCharacter() != ownerChar) then Switch(owner, ownerChar) end
		end)

		local alt = NewCharacter(owner)
		Switch(owner, alt)

		for _, access in ipairs({
			string.format([[{"%d":{"Player [1][Bot01]":3}}]], ID),
			string.format([[{"%d":[]}]], ID)
		}) do
			local path = ix.data.Set("door_saver", {})
			file.Write(path .. "door_saver.txt", string.format(
				[=[[{"doors_buff":{"%d":%d},"doors_acc_buff":%s,"titles":{"%d":"Old"}}]]=],
				ID, ownerChar:GetID(), access, ID))

			local door = Restart(plugin, makeDoor, ID)

			if (plugin.DOORS_BUFFER[ID] != ownerChar:GetID()) then fail("ownership from the old save was lost") end

			Switch(owner, ownerChar)
			if (door:GetDTEntity(0) != owner) then fail("the owner did not get the door from the old save") end

			Switch(owner, alt)
		end
	end)
end)

GWH.Check("hygiene: paper can only be written by someone who can reach it", function(fail)
	return Scoped(function(defer)
		local writer, other = GWH.Bot(), OtherBot()
		local edit = netstream.stored.ixWritingEdit
		local paper = GiveItem(writer:GetCharacter():GetInventory(), "paper")
		defer(function() paper:Remove() end)

		local function Text() return paper:GetData("text", "") end

		edit(other, paper:GetID(), "stolen")
		if (Text() != "") then fail("someone else wrote on paper in the writer's inventory") end

		edit(writer, {}, "x")
		edit(writer, paper:GetID(), {})
		edit(writer, paper:GetID())
		edit(writer, "paper", "x")
		if (Text() != "") then fail("a malformed payload changed the paper") end

		-- the net var behind IsRestricted; SetRestricted also strips weapons, which the sandbox cannot give back
		writer:SetNetVar("restricted", true)
		edit(writer, paper:GetID(), "tied")
		writer:SetNetVar("restricted", nil)
		if (Text() != "") then fail("a tied player wrote on paper") end

		edit(writer, paper:GetID(), string.rep("a", 4000))
		local maxLength = ix.plugin.list.writing.maxLength
		if (#Text() != maxLength) then fail("own paper: expected " .. maxLength .. " characters, got " .. #Text()) end
		if (paper:GetData("owner") != writer:GetCharacter():GetID()) then fail("the writer was not recorded") end

		edit(writer, paper:GetID(), "second draft")
		if (Text() != "second draft") then fail("the writer could not rewrite their paper") end

		-- lying in the world: reachable from close by only
		local world
		ix.item.Spawn("paper", writer:GetShootPos() + Vector(0, 0, 2000), function(item) world = item end)
		defer(function()
			local entity = world:GetEntity()
			if (IsValid(entity)) then entity:Remove() end
		end)

		edit(writer, world:GetID(), "from afar")
		if (world:GetData("text", "") != "") then fail("paper was written from out of reach") end

		world:GetEntity():SetPos(writer:GetShootPos() + Vector(40, 0, 0))
		edit(writer, world:GetID(), "up close")
		if (world:GetData("text", "") != "up close") then fail("paper within reach could not be written") end

		edit(other, world:GetID(), "overwrite")
		if (world:GetData("text", "") != "up close") then fail("someone overwrote another character's writing") end
	end)
end)

GWH.Check("hygiene: admin context receivers check permission and target", function(fail)
	return Scoped(function(defer)
		local sender, target = GWH.Bot(), OtherBot()
		local character = target:GetCharacter()
		local description = character:GetDescription()
		defer(function() character:SetDescription(description) end)

		local prop = ents.Create("prop_physics")
		prop:SetModel("models/props_junk/watermelon01.mdl")
		prop:Spawn()
		prop:SetHealth(7)
		defer(function() prop:Remove() end)

		local function Run(name, entity, value)
			local property = properties.List[name]
			Receive(function(length, client) property:Receive(length, client) end, sender, {entity, value})
		end

		local names = {"ixviewplayerproperty", "ixsethealthproperty", "ixsetarmorproperty", "ixsetdescriptionproperty"}

		target:Spawn()
		target:SetHealth(80)
		target:SetArmor(5)
		sender.ixStrReqs = {}

		for _, name in ipairs(names) do Run(name, target, 25) end

		if (target:Health() != 80) then fail("a non-admin changed health") end
		if (target:Armor() != 5) then fail("a non-admin changed armor") end
		if (!table.IsEmpty(sender.ixStrReqs)) then fail("a non-admin was asked for a new description") end

		MakeAdmin(defer, sender)

		for _, name in ipairs(names) do
			Run(name, prop, 25)
			Run(name, NULL, 25)
			Run(name, game.GetWorld(), 25)
		end

		if (prop:Health() != 7) then fail("a prop's health was changed") end
		if (!table.IsEmpty(sender.ixStrReqs)) then fail("a description was requested for a non-player") end

		Run("ixviewplayerproperty", target)
		Run("ixsethealthproperty", target, 25)
		Run("ixsetarmorproperty", target, 255)
		if (target:Health() != 25) then fail("an admin could not set health") end
		if (target:Armor() != 100) then fail("armor was not capped at 100, got " .. target:Armor()) end

		Run("ixsetdescriptionproperty", target)
		local _, callback = next(sender.ixStrReqs)
		if (!callback) then return fail("an admin was not asked for a description") end

		callback("short")
		if (character:GetDescription() != description) then fail("an invalid description was accepted") end

		callback("A person of entirely unremarkable appearance.")
		if (character:GetDescription() != "A person of entirely unremarkable appearance.") then
			fail("an admin could not set a description")
		end

		defer(function() Switch(target, character) end)
		Switch(target, NewCharacter(target))
		callback("This arrives after the target changed character.")
		if (character:GetDescription() != "A person of entirely unremarkable appearance.") then
			fail("a description was applied after the target switched character")
		end
	end)
end)

GWH.Check("hygiene: bodygroup and item spawn receivers", function(fail)
	return Scoped(function(defer)
		local sender, target = GWH.Bot(), OtherBot()
		local character = target:GetCharacter()
		local groups = character:GetData("groups")
		defer(function() character:SetData("groups", groups) end)
		character:SetData("groups", nil)

		local setGroups = net.Receivers.ixbodygrouptableset
		local spawnItem = net.Receivers.spawnmenuspawnitem
		local before = ItemEntities()
		defer(function()
			for _, v in ipairs(NewItemEntities(before)) do v:Remove() end
		end)

		Receive(setGroups, sender, {target, {[0] = 0}})
		if (character:GetData("groups") != nil) then fail("a non-admin saved bodygroups") end

		Receive(spawnItem, sender, {"paper"})
		if (#NewItemEntities(before) != 0) then fail("a non-admin spawned an item") end

		MakeAdmin(defer, sender)

		Receive(setGroups, sender, {target, {[0] = 0, [200] = 1, [-1] = 0, [0.5] = 0, junk = "junk"}})
		local saved = character:GetData("groups") or {}
		if (table.Count(saved) != 1 or saved[0] != 0) then
			fail("expected only the real bodygroup to be saved, got " .. util.TableToJSON(saved))
		end
		Receive(setGroups, sender, {game.GetWorld(), {}})

		Receive(spawnItem, sender, {"no_such_item"})
		if (#NewItemEntities(before) != 0) then fail("an unknown item id spawned something") end

		Receive(spawnItem, sender, {"paper"})
		if (#NewItemEntities(before) != 1) then fail("an admin could not spawn an item") end
	end)
end)

GWH.Check("hygiene: joke and custom items are not sold by the business menu", function(fail)
	local client = OtherBot()

	return Scoped(function(defer)
		local team = client:Team()
		client:SetTeam(FACTION_MPF)
		defer(function() client:SetTeam(team) end)

		for _, uniqueID in ipairs({"baby", "infant_skull", "customitem"}) do
			if (hook.Run("CanPlayerUseBusiness", client, uniqueID) != false) then
				fail(uniqueID .. " can be bought")
			end
		end
	end)
end)

GWH.Check("hygiene: opening a child gives its contents once", function(fail)
	return Scoped(function(defer)
		local client = GWH.Bot()
		local inventory = client:GetCharacter():GetInventory()
		local child = GiveItem(inventory, "baby")
		local count = {meat_chunk = inventory:GetItemCount("meat_chunk"), infant_skull = inventory:GetItemCount("infant_skull")}

		defer(function()
			for item in inventory:Iter() do
				if (count[item.uniqueID] or item.uniqueID == "baby") then item:Remove() end
			end
		end)

		local id = child:GetID()
		ix.item.PerformInventoryAction(client, "Open", id, inventory:GetID())
		ix.item.PerformInventoryAction(client, "Open", id, inventory:GetID())

		for uniqueID, had in pairs(count) do
			local gained = inventory:GetItemCount(uniqueID) - had
			if (gained != 1) then fail("expected 1 " .. uniqueID .. ", got " .. gained) end
		end
	end)
end)

-- Entities removed earlier in this frame, by this or another check, are still findable.
local function Dispensers()
	local result = {}

	for _, v in ipairs(ents.FindByClass("ix_childdispenser")) do
		if (!v:IsMarkedForDeletion()) then result[#result + 1] = v end
	end

	return result
end

local function SavedDispensers()
	ix.data.stored.randomitems = nil
	return ix.plugin.list.randomitems:GetData()
end

GWH.Check("hygiene: child dispensers save and load", function(fail)
	return Scoped(function(defer)
		local plugin = ix.plugin.list.randomitems

		defer(function()
			plugin.bCleaningUp = true
			for _, v in ipairs(Dispensers()) do v:Remove() end
			plugin.bCleaningUp = false
			plugin:SetData({})
		end)

		for _, v in ipairs(Dispensers()) do v:Remove() end

		local scripted = scripted_ents.GetStored("ix_childdispenser").t
		local first = scripted:SpawnFunction(GWH.Bot(), {HitPos = Vector(100, 200, 300), HitNormal = Vector(1, 0, 0)})
		local second = scripted:SpawnFunction(GWH.Bot(), {HitPos = Vector(400, 200, 300), HitNormal = Vector(0, 1, 0)})
		second:SetEnabled(false)
		plugin:SaveData()

		if (#SavedDispensers() != 2) then return fail("expected 2 saved dispensers, got " .. #SavedDispensers()) end

		-- A map cleanup removes them after saving. Entities run OnRemove a frame after removal, so it is called here.
		plugin:PreCleanupMap()
		plugin:SetData({})
		first:OnRemove()

		if (#SavedDispensers() != 0) then fail("removal during a map cleanup wrote over the save") end

		plugin:SaveData()
		first:Remove()
		second:Remove()

		plugin:LoadData()
		local loaded = Dispensers()
		if (#loaded != 2) then return fail("expected 2 loaded dispensers, got " .. #loaded) end

		table.sort(loaded, function(a, b) return a:GetPos().x < b:GetPos().x end)

		if (loaded[1]:GetPos():Distance(Vector(100, 200, 300)) > 1) then fail("position was not restored") end
		if (math.abs(math.AngleDifference(loaded[2]:GetAngles().y, 90)) > 1) then fail("angles were not restored") end
		if (loaded[1]:GetEnabled() != true or loaded[2]:GetEnabled() != false) then fail("enabled state was not restored") end

		plugin:SetData({})
		loaded[1]:OnRemove()
		if (#SavedDispensers() == 0) then fail("removing a dispenser by hand does not update the save") end
	end)
end)

GWH.Check("hygiene: one ration ID gets one child per interval", function(fail)
	return Scoped(function(defer)
		local client = GWH.Bot()
		local inventory = client:GetCharacter():GetInventory()
		local plugin = ix.plugin.list.randomitems
		local team = client:Team()
		client:SetTeam(FACTION_CITIZEN)

		local cid = inventory:HasItem("cid")
		local given = !cid
		cid = cid or GiveItem(inventory, "cid")
		local nextRationTime = cid:GetData("nextRationTime")
		cid:SetData("nextRationTime", nil)

		local before = ItemEntities()
		local dispensers = {}

		defer(function()
			client:SetTeam(team)
			cid:SetData("nextRationTime", nextRationTime)
			if (given) then cid:Remove() end

			for _, v in ipairs(NewItemEntities(before)) do v:Remove() end

			plugin.bCleaningUp = true
			for _, v in ipairs(dispensers) do v:Remove() end
			plugin.bCleaningUp = false
			plugin:SetData({})
		end)

		for i = 1, 2 do
			local dispenser = ents.Create("ix_childdispenser")
			dispenser:SetPos(Vector(i * 200, 0, 300))
			dispenser:Spawn()
			dispensers[i] = dispenser
		end

		-- run the dispenser's delays by hand
		local queue = {}
		Replace(defer, timer, "Simple", function(delay, callback) queue[#queue + 1] = callback end)

		dispensers[1]:Use(client)
		table.remove(queue, 1)() -- ID check passes; the dispenser starts preparing
		dispensers[2]:Use(client)
		table.remove(queue)() -- the second ID check happens before the first dispenser has finished

		local steps = 0

		while (queue[1] and steps < 50) do
			table.remove(queue, 1)()
			steps = steps + 1
		end

		local children = 0

		for _, v in ipairs(NewItemEntities(before)) do
			if (v:GetItemID() == "baby") then children = children + 1 end
		end

		if (children != 1) then fail("expected 1 child from two dispensers, got " .. children) end
	end)
end)

GWH.Check("hygiene: notes receivers cope with no character and cooldown", function(fail)
	return Scoped(function(defer)
		local client = OtherBot()
		local plugin = ix.plugin.list.mynotes
		local id = client:GetNetVar("char")
		defer(function() client:SetNetVar("char", id) end)

		client.ixNextNotes = nil
		client:SetNetVar("char", nil)

		Receive(net.Receivers.ixeditmynotes, client, {"nobody"})
		if (plugin:SendNotes(client) != nil) then fail("notes were sent to a player without a character") end

		client:SetNetVar("char", id)

		if (plugin:UpdateNotes(client, "remember the milk") != true) then fail("saving notes failed") end
		if (!isnumber(plugin:UpdateNotes(client, "again"))) then fail("the cooldown was not applied") end

		Receive(net.Receivers.ixeditmynotes, client, {"during cooldown"})
	end)
end)

GWH.Check("hygiene: removed map entities are recorded", function(fail)
	return Scoped(function(defer)
		local client = GWH.Bot()
		local plugin = ix.plugin.list.permaremove
		local saved = plugin:GetData({})
		defer(function() plugin:SetData(saved) end)
		plugin:SetData({})

		local target

		for _, v in ipairs(ents.GetAll()) do
			if (v:CreatedByMap() and v:MapCreationID() != -1 and v:GetClass() == "env_soundscape") then
				target = v
				break
			end
		end

		if (!target) then return {skipped = "no map entity to remove"} end

		local index = target:MapCreationID()
		Replace(defer, FindMetaTable("Player"), "GetEyeTraceNoCursor", function() return {Entity = target} end)
		ix.command.list.mapentremove:OnRun(client)

		if (plugin:GetData({})[1] != index) then fail("the removal was not saved") end

		plugin:LoadData()
	end)
end)

GWH.Check("hygiene: teardown", function()
	if (IsValid(GWH.hygieneBot)) then
		GWH.hygieneBot:Kick("hygiene checks finished")
		GWH.hygieneBot = nil
	end
end)
