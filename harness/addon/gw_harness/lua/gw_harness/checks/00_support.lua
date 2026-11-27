-- Shared helpers for the check files, on GWH.Lib. This file sorts first and registers no checks; each check
-- file takes what it uses as locals at the top (`local Scoped, Replace = Lib.Scoped, Lib.Replace`). Do not
-- call the alias `L`: that is Helix's global localisation function, which S.Notices uses.
-- Choosing between the near-twins:
--   Scoped / ScopedLenient     a cleanup that errors fails the check / is only printed.
--   ResetBot / ResetBotFully   back on its feet, alive, full health / that, and also untied, out of god mode,
--                              and deathTime cleared.
--   Fill / FillAll (40_stacking.lua)  fill until `leave` cells are free / until nothing more fits.
--   Receive / ReceiveReads     run a receiver function with values in read order / look a receiver up by
--                              name, with a list of values per net.Read* function.
--   ReceiveWire (with Wire)    a receiver by name, fed a message laid out as the client's net.Write* calls
--                              would lay it out: for receivers that read tables or typed values.
--   S.Target / S.ReviewTarget  two different second bots ("GWH Target" / "GWH Review"); each group of
--                              checks keeps to its own so neither sees the other's leftovers.
--   S.Snapshot / S.SnapshotWithFlags  the character's faction, name, model, money and usergroup / that
--                              and its flags; restore with the matching S.Restore / S.RestoreWithFlags.
--   OtherBot (here) is the shared "GWH Hygiene" bot; 40_stacking.lua has its own OtherBot ("GWH Stacking").
-- Nothing here keeps state between calls except the bots (found by flag or GWH field) and NewCharacter's
-- ID counter; the helpers that replace functions (Replace, Capture, S.Net, S.Notices, ReceiveReads) put
-- them back before they return.

GWH.Lib = {}

local Lib = GWH.Lib

-- Runs fn(defer); every function passed to defer runs afterwards in reverse order, even if fn threw.
-- A cleanup that errors fails the check (its error is raised once the other cleanups have run).
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

-- Like Scoped, but a cleanup that errors is printed with ErrorNoHalt and does not fail the check.
local function ScopedLenient(fn)
	local deferred = {}
	local ok, result = xpcall(fn, debug.traceback, function(cleanup)
		deferred[#deferred + 1] = cleanup
	end)

	for i = #deferred, 1, -1 do
		local bCleaned, err = pcall(deferred[i])

		if (!bCleaned) then ErrorNoHalt("check cleanup: " .. tostring(err) .. "\n") end
	end

	if (!ok) then error(result, 0) end

	return result
end

-- Sets target[key] = value inside a Scoped block and puts the original back when it ends.
local function Replace(defer, target, key, value)
	local original = target[key]
	target[key] = value
	defer(function() target[key] = original end)
end

-- Calls a net receiver function as though `client` had sent `values`, in read order (ReadEntity, ReadUInt,
-- ReadString, ReadTable).
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

-- Calls the net receiver registered as `name` as though client had sent it. reads maps a net.Read* name
-- to the values it returns in order, e.g. {ReadUInt = {id}, ReadString = {"1"}}.
local function ReceiveReads(name, client, reads)
	local receiver = net.Receivers[name:lower()]

	if (!receiver) then
		error("no net receiver " .. name, 2)
	end

	Scoped(function(defer)
		for readName, values in pairs(reads) do
			local index = 0

			Replace(defer, net, readName, function()
				index = index + 1
				return values[index]
			end)
		end

		receiver(0, client)
	end)
end

-- A message as a client's net.Write* calls lay it out, for ReceiveWire: Wire():String("Drink"):UInt(5):Table({}).
-- Type and Table write what net.WriteType and net.WriteTable would, type tags included, so the receiver's own
-- net.ReadTable or net.ReadType (or Helix's ix.util.ReadClientType) decodes it as it would a real message; Type
-- also writes what a modified client could, such as an entity or a table nested without end.
local function Wire()
	local wire = {stream = {}}

	local function Put(read, value)
		wire.stream[#wire.stream + 1] = {read, value}
		return wire
	end

	function wire:UInt(value) return Put("ReadUInt", value) end
	function wire:String(value) return Put("ReadString", value) end
	function wire:Bool(value) return Put("ReadBool", value) end
	function wire:Double(value) return Put("ReadDouble", value) end
	function wire:Entity(value) return Put("ReadEntity", value) end

	function wire:Type(value)
		if (value == nil) then
			return self:UInt(TYPE_NIL)
		elseif (isbool(value)) then
			return self:UInt(TYPE_BOOL):Bool(value)
		elseif (isnumber(value)) then
			return self:UInt(TYPE_NUMBER):Double(value)
		elseif (isstring(value)) then
			return self:UInt(TYPE_STRING):String(value)
		elseif (isentity(value)) then
			return self:UInt(TYPE_ENTITY):Entity(value)
		elseif (istable(value)) then
			return self:UInt(TYPE_TABLE):Table(value)
		end

		error("Wire can't write a " .. type(value))
	end

	function wire:Table(value)
		for k, v in pairs(value) do
			self:Type(k)
			self:Type(v)
		end

		return self:UInt(TYPE_NIL)
	end

	return wire
end

-- Calls the net receiver registered as `name` as though client had sent `wire` (from Wire). Only the primitive reads
-- are replaced, each taking the next thing written and failing the check if it was written by another kind of
-- write; past the end they return what net does (0, "", false).
local function ReceiveWire(name, client, wire)
	local receiver = net.Receivers[name:lower()]

	if (!receiver) then
		error("no net receiver " .. name, 2)
	end

	local empty = {ReadUInt = 0, ReadString = "", ReadBool = false, ReadDouble = 0}

	Scoped(function(defer)
		local index = 0

		for _, readName in ipairs({"ReadUInt", "ReadString", "ReadBool", "ReadDouble", "ReadEntity"}) do
			Replace(defer, net, readName, function()
				index = index + 1

				local entry = wire.stream[index]

				if (!entry) then
					return empty[readName]
				end

				if (entry[1] != readName) then
					error(name .. " read " .. readName .. " where the client wrote " .. entry[1], 0)
				end

				return entry[2]
			end)
		end

		receiver(0, client)
	end)
end

-- The plugin with this unique ID, or nil after reporting it as missing through fail.
local function Plugin(uniqueID, fail)
	local plugin = ix.plugin.list[uniqueID]

	if (!plugin) then
		fail(uniqueID .. " is not loaded")
	end

	return plugin
end

-- Sets configs for the duration of `fn` and puts the old values back even if it errors.
local function WithConfig(values, fn)
	local old = {}

	for k, v in pairs(values) do
		old[k] = ix.config.Get(k)
		ix.config.Set(k, v)
	end

	local ok, err = pcall(fn)

	for k, v in pairs(old) do
		ix.config.Set(k, v)
	end

	if (!ok) then error(err, 0) end
end

-- Removes every item of this kind from the inventory.
local function RemoveAll(inventory, uniqueID)
	for _, v in pairs(inventory:GetItemsByUniqueID(uniqueID)) do
		v:Remove()
	end
end

-- Entities of this class that are not already being removed (Remove only takes effect at the end of the
-- tick, and all checks run in one tick).
local function Live(class)
	local result = {}

	for _, v in ipairs(ents.FindByClass(class)) do
		if (!v:IsMarkedForDeletion()) then
			result[#result + 1] = v
		end
	end

	return result
end

-- Whether a notice list (from S.Notices) holds one containing text, ignoring case.
local function HasNotice(notices, text)
	for _, v in ipairs(notices) do
		if (string.find(string.lower(v), string.lower(text), 1, true)) then return true end
	end

	return false
end

-- Gets the bot back on its feet: alive, not ragdolled, full health, no armour, standing still.
local function ResetBot(bot)
	if (!bot:Alive()) then
		bot:Spawn()
	end

	if (IsValid(bot.ixRagdoll)) then
		bot.ixRagdoll.ixWeapons = nil
		bot:SetRagdolled(false)
	end

	bot.ixRagdoll = nil
	bot.ixKnockoutGrace = nil
	bot:SetHealth(100)
	bot:SetArmor(0)

	-- Engine bots run about on their own, and getting up hands back the ragdoll's velocity. The
	-- checks run within one tick, so this holds for the rest of the check.
	bot:SetLocalVelocity(vector_origin)
end

-- Moves every loose entity (items, and anything with physics) within 200 units of the bot's eyes, other than
-- `keep`, 4000 units up. Earlier checks leave items, props, weapons and corpses around the spawn point until
-- the next tick (entities removed in this tick still exist), and one on the bot's use line becomes its engine
-- use entity, which makes Helix refuse to take or act on any other world item (PerformInventoryAction, and the
-- pickup a Use press runs).
local function ClearAround(bot, keep)
	for _, entity in ipairs(ents.FindInSphere(bot:GetShootPos(), 200)) do
		if (entity != keep and entity != bot and entity:GetOwner() != bot and !entity:IsPlayer() and
			(entity:GetClass() == "ix_item" or IsValid(entity:GetPhysicsObject()))) then
			entity:SetPos(entity:GetPos() + Vector(0, 0, 4000))
		end
	end
end

-- Whether something solid other than the bot (and the weapons it holds) is within 96 units of a spot: another
-- player, or a leftover item, weapon or prop. Entities removed earlier in the run are still there until the
-- tick ends, such as the weapons 30_compat.lua gives and strips where the bot first spawned.
local function Occupied(bot, position)
	for _, entity in ipairs(ents.FindInSphere(position + Vector(0, 0, 36), 96)) do
		if (entity != bot and !(entity:GetOwner() == bot and !entity:IsMarkedForDeletion())) then
			if (entity:IsPlayer() or entity:IsWeapon() or entity:GetClass() == "ix_item" or IsValid(entity:GetPhysicsObject())) then
				return true
			end
		end
	end

	return false
end

-- Puts the bot on a spawn point, standing still: bots drift (on gm_construct they end up in the pond), so
-- checks that need open floor around the bot start from one. The first spawn point with nothing around it
-- (Occupied) is used: the extra bots spawn on random ones, and a bot put inside another player or a leftover
-- weapon has every trace from its eyes start in it.
local function StandOnSpawn(bot)
	local spawns = ents.FindByClass("info_player_start")

	if (#spawns == 0) then spawns = ents.FindByClass("info_player_*") end

	local chosen = spawns[1]

	for _, spawn in ipairs(spawns) do
		if (!Occupied(bot, spawn:GetPos())) then
			chosen = spawn
			break
		end
	end

	if (IsValid(chosen)) then
		bot:SetPos(chosen:GetPos())
		bot:SetVelocity(-bot:GetVelocity())
	end
end

-- Like ResetBot, and also unties the bot, ends god mode and clears deathTime.
local function ResetBotFully(bot)
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

-- A second player, for "someone else" ("GWH Hygiene", kept in GWH.hygieneBot). Bot characters are created
-- during the join itself. 90_teardown.lua kicks it.
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

-- Stand-in characters get IDs from 900000001 up, counted across every check that makes them.
local standInCharacterID = 900000000

-- A new, unsaved character for client in its current faction, with its own inventory, loaded but not
-- switched to (see Switch).
local function NewCharacter(client)
	standInCharacterID = standInCharacterID + 1

	local current = client:GetCharacter()
	local id = standInCharacterID
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

-- Switches client to character with the same steps as Helix's ixCharacterChoose receiver. The character is
-- changed even if a hook throws.
local function Switch(client, character)
	local previous = client:GetCharacter()
	local bBefore, beforeFault = xpcall(hook.Run, debug.traceback, "PrePlayerLoadedCharacter", client, character, previous)

	character:Setup(true)
	client:Spawn()
	hook.Run("PlayerLoadedCharacter", client, character, previous)

	if (!bBefore) then error(beforeFault, 0) end
end

-- Adds one item to the inventory and returns the new instance; errors if it does not fit.
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

-- The ix_item entities that exist now, as a set, for NewItemEntities.
local function ItemEntities()
	local result = {}

	for _, v in ipairs(ents.FindByClass("ix_item")) do result[v] = true end

	return result
end

-- The ix_item entities that were not in `before` (from ItemEntities).
local function NewItemEntities(before)
	local result = {}

	for _, v in ipairs(ents.FindByClass("ix_item")) do
		if (!before[v]) then result[#result + 1] = v end
	end

	return result
end

-- Item kinds the stacking and crafting checks use.
local FILLER = "iron3_junk" -- 1x1, not stackable, not used by any recipe
local SCRAP = "metal_scrap" -- resource: kg, 0.1 steps, limit 20
local COAL = "coal" -- resource: kg, 0.1 steps

-- The bot's character inventory.
local function Inventory(bot)
	return bot:GetCharacter():GetInventory()
end

-- Empties the bot's inventory (and slots reserved by pending inserts) and returns it.
local function Fresh(bot)
	local inventory = Inventory(bot)

	for _, item in pairs(inventory:GetItems()) do
		item:Remove()
	end

	for x = 1, inventory.w do
		for y = 1, inventory.h do
			if (inventory.slots[x] and inventory.slots[x][y] == true) then
				inventory.slots[x][y] = nil
			end
		end
	end

	return inventory
end

-- Number of free cells in the inventory.
local function FreeCells(inventory)
	local free = 0

	for x = 1, inventory.w do
		for y = 1, inventory.h do
			if (!(inventory.slots[x] and inventory.slots[x][y])) then
				free = free + 1
			end
		end
	end

	return free
end

-- Fills the inventory with 1x1 filler until only `leave` cells are free (leave is required).
local function Fill(inventory, leave)
	while (FreeCells(inventory) > leave) do
		if (!ix.stack.StockAdd(inventory, FILLER, 1)) then
			break
		end
	end
end

-- One new stack with an exact stored quantity, bypassing merging and the limit.
local function NewStack(inventory, uniqueID, quantity)
	local before = {}

	for _, item in ipairs(ix.stack.GetStacks(inventory, uniqueID)) do
		before[item:GetID()] = true
	end

	ix.stack.StockAdd(inventory, uniqueID, 1, ix.stack.IsStackable(uniqueID) and {quantity = quantity} or nil)

	for _, item in ipairs(ix.stack.GetStacks(inventory, uniqueID)) do
		if (!before[item:GetID()]) then
			return item
		end
	end
end

-- The stored quantities of this kind's stacks, largest first, as "20,3.5".
local function Quantities(inventory, uniqueID)
	local list = {}

	for _, item in ipairs(ix.stack.GetStacks(inventory, uniqueID)) do
		list[#list + 1] = item:GetData("quantity", 1)
	end

	table.sort(list, function(a, b) return a > b end)

	return table.concat(list, ",")
end

-- fail(label: expected X, got Y) unless actual == expected.
local function Expect(fail, label, actual, expected)
	if (actual != expected) then
		fail(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

-- Records the localized notices, plain notices, net messages and log entries sent to client while fn
-- runs; returns them as strings (notices and nets comma separated, texts separated by " | ").
local function Capture(client, fn)
	local seen = {notices = {}, texts = {}, nets = {}, logs = {}}

	Scoped(function(defer)
		local notifyLocalized, notify = ix.util.NotifyLocalized, ix.util.Notify
		local start, logAdd = net.Start, ix.log.Add

		Replace(defer, ix.util, "NotifyLocalized", function(message, recipient, ...)
			if (recipient == client) then seen.notices[#seen.notices + 1] = message end
			return notifyLocalized(message, recipient, ...)
		end)
		Replace(defer, ix.util, "Notify", function(message, recipient)
			if (recipient == client) then seen.texts[#seen.texts + 1] = message end
			return notify(message, recipient)
		end)
		Replace(defer, net, "Start", function(name, ...)
			seen.nets[#seen.nets + 1] = name
			return start(name, ...)
		end)
		Replace(defer, ix.log, "Add", function(logClient, logType, ...)
			seen.logs[#seen.logs + 1] = logType
			return logAdd(logClient, logType, ...)
		end)

		fn()
	end)

	seen.notices = table.concat(seen.notices, ",")
	seen.texts = table.concat(seen.texts, " | ")
	seen.nets = table.concat(seen.nets, ",")
	seen.logs = table.concat(seen.logs, ",")

	return seen
end

-- Answers a split prompt through the ixStackSplit receiver, clearing the rate limit first.
local function Split(bot, item, text)
	bot.ixStackSplitNext = nil
	ReceiveReads("ixStackSplit", bot, {ReadUInt = {item:GetID()}, ReadString = {text}})
end

Lib.Scoped = Scoped
Lib.ScopedLenient = ScopedLenient
Lib.Replace = Replace
Lib.Receive = Receive
Lib.ReceiveReads = ReceiveReads
Lib.Wire = Wire
Lib.ReceiveWire = ReceiveWire
Lib.Plugin = Plugin
Lib.WithConfig = WithConfig
Lib.RemoveAll = RemoveAll
Lib.Live = Live
Lib.HasNotice = HasNotice
Lib.ResetBot = ResetBot
Lib.ResetBotFully = ResetBotFully
Lib.ClearAround = ClearAround
Lib.StandOnSpawn = StandOnSpawn
Lib.OtherBot = OtherBot
Lib.NewCharacter = NewCharacter
Lib.Switch = Switch
Lib.GiveItem = GiveItem
Lib.ItemEntities = ItemEntities
Lib.NewItemEntities = NewItemEntities
Lib.Inventory = Inventory
Lib.Fresh = Fresh
Lib.FreeCells = FreeCells
Lib.Fill = Fill
Lib.NewStack = NewStack
Lib.Quantities = Quantities
Lib.Expect = Expect
Lib.Capture = Capture
Lib.Split = Split
Lib.FILLER = FILLER
Lib.SCRAP = SCRAP
Lib.COAL = COAL

--- A table for a file's `S` helpers: local S = Lib.NewS(). It looks up the shared S functions below, and
-- functions a file defines on it (function S.Sent) stay in that file.
local SHARED = {}

function Lib.NewS()
	return setmetatable({}, {__index = SHARED})
end

local S = SHARED

-- A second bot ("GWH Target") to act as the target of another player's actions, found by its flag.
-- The uniforms check in 60_schema.lua kicks it.
function S.Target()
	for _, v in ipairs(player.GetBots()) do
		if (v.gwhSchemaTarget and v:GetCharacter()) then return v end
	end

	local bot = player.CreateNextBot("GWH Target")

	if (IsValid(bot)) then
		bot.gwhSchemaTarget = true
		return bot:GetCharacter() and bot
	end
end

-- Another second bot ("GWH Review"), kept apart from S.Target's. The map cleanup check in
-- 60_schema.lua kicks it.
function S.ReviewTarget()
	for _, v in ipairs(player.GetBots()) do
		if (v.gwhReviewTarget and v:GetCharacter()) then return v end
	end

	local bot = player.CreateNextBot("GWH Review")

	if (IsValid(bot)) then
		bot.gwhReviewTarget = true
		return bot:GetCharacter() and bot
	end
end

-- Puts the client's character in a faction, and under a name when given.
function S.Become(client, faction, name)
	local character = client:GetCharacter()

	if (character:GetFaction() != faction) then
		character:SetFaction(faction)
	end

	client:SetTeam(faction)

	if (name and character:GetName() != name) then
		character:SetName(name)
	end
end

-- Faction, name, model, usergroup, money and class, for S.Restore (which does not restore class).
function S.Snapshot(client)
	local character = client:GetCharacter()

	return {
		faction = character:GetFaction(),
		name = character:GetName(),
		model = character:GetModel(),
		usergroup = client:GetUserGroup(),
		money = character:GetMoney(),
		class = character:GetClass()
	}
end

-- Puts back what S.Snapshot recorded.
function S.Restore(client, state)
	if (!IsValid(client) or !client:GetCharacter()) then return end

	local character = client:GetCharacter()

	S.Become(client, state.faction, state.name)
	character:SetModel(state.model)
	character:SetMoney(state.money)
	client:SetUserGroup(state.usergroup)
end

-- Faction, name, model, usergroup, money and flags, for S.RestoreWithFlags.
function S.SnapshotWithFlags(client)
	local character = client:GetCharacter()

	return {
		faction = character:GetFaction(),
		name = character:GetName(),
		model = character:GetModel(),
		usergroup = client:GetUserGroup(),
		money = character:GetMoney(),
		flags = character:GetFlags()
	}
end

-- Puts back what S.SnapshotWithFlags recorded, flags included.
function S.RestoreWithFlags(client, state)
	if (!IsValid(client) or !client:GetCharacter()) then return end

	local character = client:GetCharacter()

	S.Become(client, state.faction, state.name)
	character:SetModel(state.model)
	character:SetMoney(state.money)
	character:SetFlags(state.flags)
	client:SetUserGroup(state.usergroup)
end

-- Runs a net.Receive callback with `values` as the message contents, in read order.
function S.Net(name, sender, values)
	local receiver = net.Receivers[string.lower(name)]
	if (!receiver) then error("no net receiver " .. name) end

	local index = 0
	local originals = {}

	for _, fn in ipairs({"ReadString", "ReadUInt", "ReadInt", "ReadEntity", "ReadBool", "ReadTable", "ReadFloat", "ReadType"}) do
		originals[fn] = net[fn]
		net[fn] = function()
			index = index + 1
			return values[index]
		end
	end

	local ok, err = pcall(receiver, 0, sender)

	for k, v in pairs(originals) do net[k] = v end

	if (!ok) then error(err, 0) end
end

-- Runs a netstream hook as though sender had sent the arguments.
function S.Stream(name, sender, ...)
	local callback = netstream.stored[name]
	if (!callback) then error("no netstream hook " .. name) end

	callback(sender, ...)
end

-- Runs a chat command as the client, clearing the command cooldown first.
function S.Command(client, text)
	client.ixCommandCooldown = nil
	ix.command.Parse(client, text)
end

-- How much of an item the inventory holds (ix.stack.Count when stacking is loaded).
function S.Count(inventory, uniqueID)
	if (ix.stack and ix.stack.Count) then
		return ix.stack.Count(inventory, uniqueID)
	end

	return table.Count(inventory:GetItemsByUniqueID(uniqueID, true) or {})
end

-- Removes every item of this kind from the inventory.
function S.RemoveAll(inventory, uniqueID)
	for _, item in pairs(inventory:GetItemsByUniqueID(uniqueID, true) or {}) do
		item:Remove()
	end
end

-- Errors raised while fn ran, from pcall and the harness's OnLuaError log.
function S.Errors(fn)
	local before = #GWH.errors
	local ok, err = pcall(fn)
	local errors = {}

	if (!ok) then errors[#errors + 1] = tostring(err) end

	for i = before + 1, #GWH.errors do
		errors[#errors + 1] = GWH.errors[i].error
	end

	return errors
end

-- Notices sent to client while fn ran, as text.
function S.Notices(client, fn)
	local meta = FindMetaTable("Player")
	local notify, localized = meta.Notify, meta.NotifyLocalized
	local notices = {}

	meta.Notify = function(self, message, ...)
		if (self == client) then notices[#notices + 1] = tostring(message) end
		return notify(self, message, ...)
	end

	meta.NotifyLocalized = function(self, message, ...)
		if (self == client) then notices[#notices + 1] = L(message, self, ...) end
		return localized(self, message, ...)
	end

	local ok, err = pcall(fn)
	meta.Notify, meta.NotifyLocalized = notify, localized

	if (!ok) then error(err, 0) end

	return notices
end
