-- Doors (doors, door_saver, kickdoor, shootlock, stealthability): kicking, shooting and breaching a spawned
-- door, /KickDoor refused while downed, dead or tied, door ownership and access across character switches and
-- restarts, old door saves, and door_saver on a database wipe.

local Lib = GWH.Lib
local Plugin, ResetBot, ScopedLenient, ResetBotFully = Lib.Plugin, Lib.ResetBot, Lib.ScopedLenient, Lib.ResetBotFully
local OtherBot, Scoped, Replace, Receive = Lib.OtherBot, Lib.Scoped, Lib.Replace, Lib.Receive
local NewCharacter, Switch = Lib.NewCharacter, Lib.Switch

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

GWH.Check("survival: door plugins work on a spawned door", function(fail)
	local bot = GWH.Bot()
	local kick = Plugin("kickdoor", fail)
	local shoot = Plugin("shootlock", fail)
	local stealth = Plugin("stealthability", fail)
	if (!bot or !kick or !shoot or !stealth) then return fail("no bot or plugin") end

	ResetBot(bot)

	local door = ents.Create("prop_door_rotating")
	door:SetModel("models/props_c17/door01_left.mdl")
	door:SetKeyValue("hardware", "1")
	door:SetKeyValue("distance", "90")
	door:SetKeyValue("speed", "100")
	door:SetKeyValue("returndelay", "-1")
	door:SetPos(bot:GetPos() + Vector(80, 0, 54))
	door:Spawn()
	door:Activate()

	local team = bot:Team()
	local errors = #GWH.errors

	-- kickdoor: per-player cooldown and stamina, impact through the validity-checked path
	bot:SetTeam(FACTION_MPF)
	bot:SetLocalVar("stm", 100)
	bot.ixNextKick = nil

	local bCanKick, message = kick:CanKick(bot, door)

	if (!bCanKick) then
		fail("a still Combine bot 80 units from a door cannot kick it: " .. tostring(message))
	else
		kick:Kick(bot, door)

		if (bot:GetLocalVar("stm", 0) != 100 - kick.staminaCost) then fail("kicking did not cost stamina") end
		if (kick:CanKick(bot, door)) then fail("no cooldown after a kick") end
		if (!bot.ixNextKick) then fail("the cooldown is not stored on the player") end

		kick:KickImpact(bot, door, true)

		if (!IsValid(door.ixDummy)) then
			fail("a breaking kick did not blast the door")
		else
			door.ixDummy:Remove()
		end
	end

	bot:SetTeam(FACTION_CITIZEN)
	bot.ixNextKick = nil
	if (kick:CanKick(bot, door)) then fail("a citizen can kick doors") end
	bot:SetTeam(team)

	-- shootlock: an NPC or the world shooting a door must not error
	local npc = ents.Create("npc_headcrab")
	npc:SetPos(bot:GetPos() + Vector(0, 0, 120))
	npc:Spawn()

	for _, attacker in ipairs({npc, game.GetWorld()}) do
		local info = DamageInfo()
			info:SetDamage(10)
			info:SetDamageType(DMG_BULLET)
			info:SetAttacker(attacker)
			info:SetInflictor(attacker)
			info:SetDamagePosition(door:GetPos())
		shoot:EntityTakeDamage(door, info)
	end

	npc:Remove()

	if (shoot:IsShotgun(NULL)) then fail("IsShotgun accepted a NULL weapon") end

	shoot:BreachDoor(bot, door, door:GetPos())

	if (!IsValid(door.ixDummy)) then
		fail("a shotgun breach did not blast the door")
	else
		door.ixDummy:Remove()
	end

	-- stealthability: a use alternates the per-door flag and records who used it
	stealth:PlayerUse(bot, door)
	stealth:PlayerUse(bot, door)

	if (door:GetNWEntity("ControlingPlayer") != bot) then
		fail("using a door did not record the player for stealthability")
	end

	if (#GWH.errors > errors) then fail("door plugins raised " .. GWH.errors[#GWH.errors].error) end

	-- the kick's delayed impact runs after this and must cope with the door being gone
	door:Remove()
end)

GWH.Check("world review: /KickDoor refuses a downed, dead or tied player", function(fail)
	local bot = GWH.Bot()
	local kick = ix.plugin.list.kickdoor
	if (!bot or !kick) then return fail("no bot or kickdoor") end

	ScopedLenient(function(defer)
		local team = bot:Team()
		defer(function() bot:SetTeam(team) ResetBotFully(bot) end)

		ResetBotFully(bot)

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
		ResetBotFully(bot)

		bot:SetRestricted(true)
		Ready()
		if (kick:CanKick(bot, door)) then fail("a tied player can kick a door") end
		ResetBotFully(bot)

		local position = bot:GetPos()
		bot:Kill()
		bot:SetPos(position)
		Ready()
		if (kick:CanKick(bot, door)) then fail("a dead player can kick a door") end
	end)
end)

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

GWH.Check("schema review: door_saver forgets owners on a database wipe", function(fail)
	local plugin = ix.plugin.list.door_saver
	if (!plugin) then return {skipped = "door_saver not loaded"} end

	local doors, access, titles = plugin.DOORS_BUFFER, plugin.DOORS_ACCESS_BUFFER, plugin.DOORS_TITLES_BUFFER
	local saved = plugin:GetData()

	plugin.DOORS_BUFFER = {[51000] = 7}
	plugin.DOORS_ACCESS_BUFFER = {[51000] = {[8] = DOOR_GUEST or 1}}
	plugin.DOORS_TITLES_BUFFER = {[51000] = "gwh"}
	plugin:SaveDoors()

	if (plugin.OnWipeTables) then plugin:OnWipeTables() end

	if (next(plugin.DOORS_BUFFER) or next(plugin.DOORS_ACCESS_BUFFER) or next(plugin.DOORS_TITLES_BUFFER)) then
		fail("a database wipe left door owners, access or titles in the buffers")
	end

	local data = plugin:GetData() or {}

	if (next(data.doors_buff or {})) then fail("a database wipe left door owners in the save") end

	plugin.DOORS_BUFFER, plugin.DOORS_ACCESS_BUFFER, plugin.DOORS_TITLES_BUFFER = doors, access, titles
	plugin:SetData(saved)
end)
