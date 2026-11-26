-- Schema and security-critical RP plugin checks: the business menu, starter kits, /SetFreq,
-- the schema's net receivers, applicationsystem, datafile, cto and protectionteams.
-- Receivers are called the way a net message would call them, with a bot as the sender.

local S = {}

-- A second bot to act as the target of another player's actions.
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

-- Puts the bot's character in a faction under a name, the way the schema reads them.
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

function S.Restore(client, state)
	if (!IsValid(client) or !client:GetCharacter()) then return end

	local character = client:GetCharacter()

	S.Become(client, state.faction, state.name)
	character:SetModel(state.model)
	character:SetMoney(state.money)
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

function S.Stream(name, sender, ...)
	local callback = netstream.stored[name]
	if (!callback) then error("no netstream hook " .. name) end

	callback(sender, ...)
end

function S.Command(client, text)
	client.ixCommandCooldown = nil
	ix.command.Parse(client, text)
end

function S.Count(inventory, uniqueID)
	if (ix.stack and ix.stack.Count) then
		return ix.stack.Count(inventory, uniqueID)
	end

	return table.Count(inventory:GetItemsByUniqueID(uniqueID, true) or {})
end

function S.RemoveAll(inventory, uniqueID)
	for _, item in pairs(inventory:GetItemsByUniqueID(uniqueID, true) or {}) do
		item:Remove()
	end
end

-- Errors raised while fn ran, from the harness's OnLuaError log.
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

local function OptsIn(itemTable)
	return itemTable.factions != nil or itemTable.classes != nil
		or (itemTable.permit != nil and itemTable.base != "base_permits")
end

GWH.Check("schema: business menu only lists items that opt in", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()
	local state = S.Snapshot(bot)
	local listed = {}

	for _, faction in ipairs({FACTION_CITIZEN, FACTION_MPF, FACTION_OTA, FACTION_ADMIN}) do
		S.Become(bot, faction)
		listed[team.GetName(faction)] = 0

		for uniqueID, itemTable in pairs(ix.item.list) do
			if (hook.Run("CanPlayerUseBusiness", bot, uniqueID) != false) then
				listed[team.GetName(faction)] = listed[team.GetName(faction)] + 1

				if (!OptsIn(itemTable)) then
					fail(team.GetName(faction) .. " can buy '" .. uniqueID .. "', which declares no permit, faction or class")
				end
			end
		end
	end

	-- plugin items that do not opt in, unpriced and priced, through the real purchase receiver
	local free, priced

	for uniqueID, itemTable in SortedPairs(ix.item.list) do
		if (itemTable.plugin and !OptsIn(itemTable)) then
			if (!itemTable.price) then
				free = free or uniqueID
			else
				priced = priced or uniqueID
			end
		end
	end

	local function Shipments() return #ents.FindByClass("ix_shipment") end

	for _, faction in ipairs({FACTION_CITIZEN, FACTION_MPF, FACTION_OTA, FACTION_ADMIN}) do
		S.Become(bot, faction)

		for _, probe in ipairs({free, priced}) do
			character:SetMoney(1000)
			bot.ixNextBusiness = nil

			local before = Shipments()
			S.Net("ixBusinessBuy", bot, {1, probe, 1})

			if (Shipments() != before) then
				fail(team.GetName(faction) .. " received a shipment of '" .. tostring(probe) .. "', which does not opt in")
			end
		end
	end

	-- a faction allow-list item is sold, at its price, to that faction only
	S.Become(bot, FACTION_MPF)
	character:SetMoney(100)
	bot.ixNextBusiness = nil

	local before = Shipments()
	S.Net("ixBusinessBuy", bot, {1, "zip_tie", 1})

	if (Shipments() != before + 1) then
		fail("Civil Protection could not buy zip_tie")
	elseif (character:GetMoney() != 100 - ix.item.list.zip_tie.price) then
		fail("zip_tie cost " .. (100 - character:GetMoney()) .. ", expected " .. ix.item.list.zip_tie.price)
	end

	for _, v in ipairs(ents.FindByClass("ix_shipment")) do v:Remove() end

	S.Become(bot, FACTION_CITIZEN)

	if (hook.Run("CanPlayerUseBusiness", bot, "zip_tie") != false) then
		fail("a citizen can buy zip_tie (Civil Protection and OTA only)")
	end

	-- a permit item needs the permit
	if (hook.Run("CanPlayerUseBusiness", bot, "melon") != false) then
		fail("melon is buyable without the consumables permit")
	end

	inventory:Add("permit_consumables")

	if (hook.Run("CanPlayerUseBusiness", bot, "melon") == false) then
		fail("melon is not buyable with the consumables permit")
	end

	if (hook.Run("CanPlayerUseBusiness", bot, "permit_consumables") != false) then
		fail("permits themselves are buyable")
	end

	S.RemoveAll(inventory, "permit_consumables")
	S.Restore(bot, state)

	return {listed = listed, unpricedProbe = free, pricedProbe = priced}
end)

GWH.Check("schema: /SetFreq accepts a valid frequency", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()

	inventory:Add("handheld_radio")

	local radio = inventory:HasItem("handheld_radio")
	if (!radio) then return fail("could not give the bot a radio") end

	S.Command(bot, "/SetFreq 100.0")

	if (character:GetData("frequency") != "100.0" or radio:GetData("frequency") != "100.0") then
		fail("/SetFreq 100.0 left the frequency at " .. tostring(character:GetData("frequency")))
	end

	S.Command(bot, "/SetFreq 451.25")

	if (character:GetData("frequency") != "451.3") then
		fail("/SetFreq 451.25 set " .. tostring(character:GetData("frequency")) .. ", expected 451.3")
	end

	for _, bad in ipairs({"abc", "99.9", "1000"}) do
		S.Command(bot, "/SetFreq " .. bad)

		if (character:GetData("frequency") != "451.3") then
			fail("/SetFreq " .. bad .. " was accepted")
		end
	end

	S.RemoveAll(inventory, "handheld_radio")
	character:SetData("frequency", nil)
end)

GWH.Check("schema: every faction's starting loadout is given", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()
	local cid = character:GetData("cid")
	local expected = {
		[FACTION_CITIZEN] = {suitcase = 1, cid = 1},
		[FACTION_MPF] = {stunstick = 1, pistol = 1, pistolammo = 2},
		[FACTION_OTA] = {pistol = 1, pistolammo = 2, ar2 = 1, ar2ammo = 2}
	}
	local given = {}

	for index, faction in ipairs(ix.faction.indices) do
		if (faction.OnCharacterCreated) then
			local before = {}

			for item in inventory:Iter() do before[item.id] = true end

			local errors = S.Errors(function() faction:OnCharacterCreated(bot, character) end)

			for _, err in ipairs(errors) do fail(faction.name .. ": " .. err) end

			given[faction.name] = {}

			for uniqueID, amount in pairs(expected[index] or {}) do
				local count = S.Count(inventory, uniqueID)
				given[faction.name][uniqueID] = count

				if (ix.item.list[uniqueID] and count < amount) then
					fail(faction.name .. " got " .. count .. " of " .. uniqueID .. ", expected " .. amount)
				end
			end

			for item in inventory:Iter() do
				if (!before[item.id]) then item:Remove() end
			end
		end
	end

	character:SetData("cid", cid)

	-- a loadout naming an item that is not registered is skipped, not an error
	local errors = S.Errors(function()
		Schema:GiveLoadout(character, {{"gwh_unregistered_item", 1}, {"suitcase", 1}})
	end)

	for _, err in ipairs(errors) do fail("missing loadout item: " .. err) end

	if (S.Count(inventory, "suitcase") < 1) then
		fail("an unregistered loadout item stopped the rest of the loadout")
	end

	S.RemoveAll(inventory, "suitcase")

	return given
end)

GWH.Check("schema: data and objective receivers validate their input", function(fail)
	local bot, target = GWH.Bot(), S.Target()
	if (!bot or !target) then return fail("no bots") end

	local state, targetState = S.Snapshot(bot), S.Snapshot(target)
	local targetCharacter = target:GetCharacter()
	local objectives = Schema.CombineObjectives

	S.Become(target, FACTION_CITIZEN)
	targetCharacter:SetData("combineData", nil)

	-- malformed payloads must not throw
	for _, payload in ipairs({{target, 5}, {"x", "text"}, {Entity(0), "text"}, {nil, nil}}) do
		for _, err in ipairs(S.Errors(function() S.Stream("ViewDataUpdate", bot, payload[1], payload[2]) end)) do
			fail("ViewDataUpdate with a bad payload: " .. err)
		end
	end

	for _, err in ipairs(S.Errors(function() S.Stream("ViewObjectivesUpdate", bot, {}) end)) do
		fail("ViewObjectivesUpdate with a table: " .. err)
	end

	S.Become(bot, FACTION_CITIZEN)
	S.Stream("ViewDataUpdate", bot, target, "citizen edit")

	if (targetCharacter:GetData("combineData")) then
		fail("a citizen edited another character's Combine data")
	end

	S.Become(bot, FACTION_MPF, "MPF-RCT.11111")
	S.Stream("ViewDataUpdate", bot, target, "cp edit")

	if (!istable(targetCharacter:GetData("combineData")) or targetCharacter:GetData("combineData").text != "cp edit") then
		fail("Civil Protection could not edit a citizen's Combine data")
	end

	-- objectives need a command rank, and are rate limited
	Schema.CombineObjectives = {text = "before"}
	bot.ixNextObjectivesEdit = nil
	S.Stream("ViewObjectivesUpdate", bot, "recruit")

	if (Schema.CombineObjectives.text != "before") then
		fail("a recruit edited the objectives")
	end

	S.Become(bot, FACTION_MPF, "MPF-OfC.11111")
	S.Stream("ViewObjectivesUpdate", bot, "officer")

	if (Schema.CombineObjectives.text != "officer") then
		fail("an OfC could not edit the objectives")
	end

	S.Stream("ViewObjectivesUpdate", bot, "again")

	if (Schema.CombineObjectives.text != "officer") then
		fail("objective edits are not rate limited")
	end

	-- a name change on a character without a player
	local ghost = {GetPlayer = function() return NULL end}

	for _, err in ipairs(S.Errors(function() Schema:CharacterVarChanged(ghost, "name", "a", "b") end)) do
		fail("CharacterVarChanged without a player: " .. err)
	end

	Schema.CombineObjectives = objectives
	ix.data.Set("combineObjectives", objectives, false, true)
	bot.ixNextObjectivesEdit = nil
	targetCharacter:SetData("combineData", nil)
	S.Restore(bot, state)
	S.Restore(target, targetState)
end)

GWH.Check("applicationsystem: only reviewers decide, only applicants collect", function(fail)
	local plugin = ix.plugin.list.applicationsystem
	if (!plugin) then return {skipped = "applicationsystem not loaded"} end

	local bot, other = GWH.Bot(), S.Target()
	if (!bot or !other) then return fail("no bots") end

	local state = S.Snapshot(bot)
	local character = bot:GetCharacter()
	local inventory = character:GetInventory()

	local function Rows()
		local rows

		local query = mysql:Select("ix_applications")
			query:Where("char_id", character:GetID())
			query:Callback(function(result) rows = istable(result) and result or {} end)
		query:Execute()

		return rows or {}
	end

	local function Cleanup()
		local query = mysql:Delete("ix_applications")
			query:Where("char_id", character:GetID())
		query:Execute()

		S.RemoveAll(inventory, "acceptance_paper")
		S.RemoveAll(inventory, "cid")
		character:SetData("applicationopen", nil)
		bot.ixApplicationTerminal = nil
	end

	Cleanup()
	S.Become(bot, FACTION_CITIZEN)
	bot:SetUserGroup("user")
	inventory:Add("cid", 1, {name = character:GetName(), id = "12345"})

	local spoofed = {"Forged Name", "99999", "ref", "why", string.rep("s", 5000), "skills", "reloc", "family", "work",
		"cp", "date", "76561197960265728", 1}

	-- a form from someone who never logged in at a terminal
	S.Stream("SubmitApplication", bot, spoofed)

	if (#Rows() != 0) then fail("an application was accepted without using a terminal") end

	bot.ixApplicationTerminal = true
	S.Stream("SubmitApplication", bot, spoofed)

	local row = Rows()[1]
	if (!row) then Cleanup() S.Restore(bot, state) return fail("a terminal application was not stored") end

	local appID = tonumber(row.app_id)

	if (row.steamid != bot:SteamID64() or row.name != character:GetName() or row.cid != "12345") then
		fail("the stored identity came from the client: " .. tostring(row.steamid) .. " / " .. tostring(row.name) .. " / " .. tostring(row.cid))
	end

	if (#row.story != 1500) then fail("story stored with length " .. #row.story .. ", cap is 1500") end

	-- an unprivileged client cannot answer it, or mint a letter for it
	S.Stream("ApplicationResponse", bot, {"!true", appID})
	S.Stream("ApplicationSeen", bot, {"cp", true, appID, "Forged"})

	row = Rows()[1]

	if (row.response != "") then fail("a non-reviewer answered an application") end
	if (S.Count(inventory, "acceptance_paper") != 0) then fail("an unanswered application produced a letter") end

	-- a reviewer accepts it
	bot:SetUserGroup("superadmin")
	S.Stream("ApplicationResponse", bot, {"!true", appID})
	bot:SetUserGroup("user")

	if (Rows()[1].response != "!true") then fail("a reviewer could not accept an application") end

	-- another character cannot collect it, the applicant collects exactly one letter
	S.Stream("ApplicationSeen", other, {"cp", true, appID, "Forged"})

	if (Rows()[1].seen != "false") then fail("another character marked the application seen") end

	S.Stream("ApplicationSeen", bot, {"cp", true, appID, "Forged"})
	S.Stream("ApplicationSeen", bot, {"cp", true, appID, "Forged"})

	local letters = inventory:GetItemsByUniqueID("acceptance_paper", true) or {}

	if (#letters != 1) then
		fail("the applicant got " .. #letters .. " acceptance letters, expected 1")
	elseif (!string.find(letters[1]:GetData("application", ""), character:GetName(), 1, true)) then
		fail("the letter does not carry the applicant's name from the server")
	end

	Cleanup()
	S.Restore(bot, state)
end)

-- Names of the net messages started while fn runs.
function S.Sent(fn)
	local names = {}
	local start = net.Start

	net.Start = function(name, ...)
		names[#names + 1] = name
		return start(name, ...)
	end

	local ok, err = pcall(fn)
	net.Start = start

	if (!ok) then error(err, 0) end

	return names
end

GWH.Check("datafile: tiers, receivers and row ownership", function(fail)
	if (!Datafile) then return {skipped = "datafile not loaded"} end

	local bot, target = GWH.Bot(), S.Target()
	if (!bot or !target) then return fail("no bots") end

	local state, targetState = S.Snapshot(bot), S.Snapshot(target)
	local loaded = hook.GetTable().PlayerLoadedCharacter.Datafile
	local maxPoints = 100

	local function Load(client)
		loaded(client, client:GetCharacter())
	end

	local function File(client)
		return client.Datafile and client.Datafile.Datafile or {}
	end

	local function Generic(client)
		return client.Datafile and client.Datafile.GenericData or {}
	end

	local function Opened(viewer)
		local names = S.Sent(function() S.Net("RefreshDatafile", viewer, {target}) end)

		return table.HasValue(names, "CreateFullDatafile") or table.HasValue(names, "CreateRestrictedDatafile")
	end

	local function Managed(viewer)
		return table.HasValue(S.Sent(function() S.Net("RefreshManagefile", viewer, {target}) end), "CreateManagementPanel")
	end

	S.Become(bot, FACTION_CITIZEN)
	S.Become(target, FACTION_CITIZEN)
	Load(bot)
	Load(target)

	if (!target.Datafile or !File(target)[1]) then
		S.Restore(bot, state)
		S.Restore(target, targetState)
		return fail("loading a character did not create and load its datafile")
	end

	local first = File(target)[1]
	local removeArgs = {target, 1, first.date, first.category, first.text}

	-- citizens have no access to anyone's file
	local count = #File(target)

	if (Datafile:ReturnPermission(bot) != DATAFILE_PERMISSION_NONE) then fail("citizens have datafile access") end
	if (Opened(bot)) then fail("a citizen opened another character's file") end
	if (Managed(bot)) then fail("a citizen opened another character's management panel") end

	S.Net("AddDatafileEntry", bot, {target, "med", "citizen note", "5"})
	if (#File(target) != count) then fail("a citizen added an entry") end

	Generic(target).lastSeen = "gwh"
	S.Net("UpdateLastSeen", bot, {target})
	if (Generic(target).lastSeen != "gwh") then fail("a citizen updated last seen") end

	count = #File(target)
	S.Net("RemoveDatafileLine", bot, removeArgs)
	if (#File(target) != count) then fail("a citizen removed a datafile line") end

	-- bad targets are rejected without errors
	for _, bad in ipairs({NULL, Entity(0)}) do
		for _, name in ipairs({"UpdateLastSeen", "SetBOL", "RefreshManagefile", "RefreshDatafile"}) do
			for _, err in ipairs(S.Errors(function() S.Net(name, bot, {bad}) end)) do
				fail(name .. " with target " .. tostring(bad) .. ": " .. err)
			end
		end
	end

	-- Civil Protection reads and adds, but does not manage
	S.Become(bot, FACTION_MPF, "MPF-RCT.22222")
	Load(bot)

	local points = Datafile:ReturnPoints(target)
	count = #File(target)

	if (!Opened(bot)) then fail("Civil Protection could not open a citizen's file") end
	if (Managed(bot)) then fail("a Civil Protection recruit opened the management panel") end

	S.Net("AddDatafileEntry", bot, {target, "civil", "cp note", "1e9"})

	local added = File(target)[#File(target)]

	if (#File(target) != count + 1 or added.text != "cp note") then
		fail("Civil Protection could not add an entry")
	elseif (tonumber(added.points) != maxPoints or Datafile:ReturnPoints(target) != points + maxPoints) then
		fail("1e9 points were stored as " .. tostring(added.points) .. "; the cap is " .. maxPoints)
	end

	count = #File(target)
	S.Net("RemoveDatafileLine", bot, removeArgs)

	if (#File(target) != count) then fail("a Civil Protection recruit removed a datafile line") end

	S.Net("SetBOL", bot, {target})

	if (Datafile:ReturnBOL(target)) then fail("a Civil Protection recruit set a BOL") end

	-- a command rank manages the file
	S.Become(bot, FACTION_MPF, "MPF-OfC.22222")
	Load(bot)

	if (!Managed(bot)) then fail("an OfC could not open the management panel") end

	local sent
	local writeTable = net.WriteTable

	-- WriteTable recurses into nested tables, so keep only the outermost one
	net.WriteTable = function(tbl, ...) sent = sent or tbl return writeTable(tbl, ...) end
	S.Command(bot, "/ManageDatafile \"" .. target:Name() .. "\"")
	net.WriteTable = writeTable

	if (sent != File(target)) then fail("/ManageDatafile did not send the target's file") end

	S.Net("RemoveDatafileLine", bot, removeArgs)

	if (#File(target) != count - 1) then fail("an OfC could not remove a datafile line") end

	local bViewerBOL = Datafile:ReturnBOL(bot)

	S.Net("SetBOL", bot, {target})

	if (!Datafile:ReturnBOL(target)) then fail("an OfC could not put a BOL on the target") end
	if (Datafile:ReturnBOL(bot) != bViewerBOL) then fail("SetBOL changed the viewer's own BOL") end

	S.Net("SetBOL", bot, {target})

	if (Datafile:ReturnBOL(target)) then fail("a second SetBOL did not lift the target's BOL") end

	-- deleting a character removes exactly its own row
	local steamID = target:SteamID()

	local function RowCount(characterID)
		local n = 0
		local query = mysql:Select("ix_datafile")
			query:Where("CharacterID", characterID)
			query:Where("SteamID", steamID)
			query:Callback(function(result) n = istable(result) and #result or 0 end)
		query:Execute()

		return n
	end

	for _, id in ipairs({900001, 900002}) do
		local insert = mysql:Insert("ix_datafile")
			insert:Insert("CharacterID", id)
			insert:Insert("CharacterName", "gwh")
			insert:Insert("SteamID", steamID)
			insert:Insert("Schema", Schema.folder)
			insert:Insert("GenericData", "{}")
			insert:Insert("Datafile", "[]")
		insert:Execute()
	end

	local deleted = hook.GetTable().CharacterDeleted.Datafile

	deleted(target, 900001, false)

	if (RowCount(900001) != 0) then fail("CharacterDeleted left the deleted character's row") end
	if (RowCount(900002) != 1) then fail("CharacterDeleted removed another character's row") end
	if (RowCount(target:GetCharacter():GetID()) != 1) then fail("CharacterDeleted removed the player's current row") end

	deleted(target, 900002, false)

	local cleanup = mysql:Delete("ix_datafile")
		cleanup:Where("CharacterID", 900002)
	cleanup:Execute()

	S.Restore(bot, state)
	S.Restore(target, targetState)
end)

GWH.Check("cto: coexists with the schema and edits the right character", function(fail)
	local plugin = ix.plugin.list.cto
	if (!plugin) then return {skipped = "cto not loaded"} end

	local bot, target = GWH.Bot(), S.Target()
	if (!bot or !target) then return fail("no bots") end

	local state, targetState = S.Snapshot(bot), S.Snapshot(target)

	for _, name in ipairs({"PlayerDeath", "GetPlayerDeathSound"}) do
		local source = debug.getinfo(Schema[name], "S").short_src

		if (!string.find(source, "schema/sv_hooks.lua", 1, true)) then
			fail("Schema:" .. name .. " is defined in " .. source)
		end
	end

	local request = debug.getinfo(ix.command.list.request.OnRun, "S").short_src

	if (!string.find(request, "schema/sh_commands.lua", 1, true)) then
		fail("/Request is defined in " .. request)
	end

	-- the schema's scanner death sound survives
	S.Become(bot, FACTION_MPF, "MPF-SCN.33333")
	bot.ixDiedWithBiosignal = true

	local sound = hook.Run("GetPlayerDeathSound", bot)

	if (sound != "NPC_CScanner.Die") then fail("a scanner's death sound is " .. tostring(sound)) end

	-- CID tags: the admin's command edits the target and publishes the tag
	S.Become(target, FACTION_CITIZEN)
	target:GetCharacter():SetData("cid", "54321")
	target:GetCharacter():SetData("IsCIDTagGone", nil)
	bot:GetCharacter():SetData("IsCIDTagGone", nil)
	plugin:UpdateCIDTag(target)

	if (target:GetNetVar("ctoCIDTag") != "54321") then fail("the CID tag net var is " .. tostring(target:GetNetVar("ctoCIDTag"))) end

	bot:SetUserGroup("superadmin")
	S.Command(bot, "/CharSetHasTags \"" .. target:Name() .. "\" false")

	if (!target:GetCharacter():GetData("IsCIDTagGone")) then fail("/CharSetHasTags did not change the target") end
	if (bot:GetCharacter():GetData("IsCIDTagGone")) then fail("/CharSetHasTags changed the admin's own character") end
	if (target:GetNetVar("ctoCIDTag") != nil) then fail("a removed CID tag is still published") end

	-- sociostatus needs a rank
	bot:SetUserGroup("user")
	plugin.socioStatus = "GREEN"
	S.Become(bot, FACTION_MPF, "MPF-RCT.33333")
	S.Command(bot, "/SetSocioStatus red")

	if (plugin.socioStatus != "GREEN") then fail("a recruit set the sociostatus") end

	S.Become(bot, FACTION_MPF, "MPF-OfC.33333")
	S.Command(bot, "/SetSocioStatus red")

	if (plugin.socioStatus != "RED") then fail("an OfC could not set the sociostatus") end

	plugin.socioStatus = "GREEN"

	-- the periodic HUD message before the schema has loaded its objectives
	local objectives = Schema.CombineObjectives
	Schema.CombineObjectives = nil

	for _, err in ipairs(S.Errors(function() plugin:SendHUDObjectives({bot}) end)) do
		fail("HUD objectives without loaded objectives: " .. err)
	end

	Schema.CombineObjectives = objectives
	target:GetCharacter():SetData("IsCIDTagGone", nil)
	S.Restore(bot, state)
	S.Restore(target, targetState)
end)

GWH.Check("protectionteams: reassigning a missing team", function(fail)
	local plugin = ix.plugin.list.protectionteams
	if (!plugin) then return {skipped = "protectionteams not loaded"} end

	local result

	for _, err in ipairs(S.Errors(function() result = plugin:ReassignTeam(97, 98, true) end)) do
		fail("ReassignTeam of a missing team: " .. err)
	end

	if (result != "@TeamNonExistent") then fail("ReassignTeam of a missing team returned " .. tostring(result)) end
end)

GWH.Check("schema: uniforms change citizen models", function(fail)
	local cases = {
		{"models/player/zelpa/male_03_extended.mdl", "group03", "models/humans/group03/male_03.mdl"},
		{"models/player/zelpa/female_07_extended.mdl", "group03m", "models/humans/group03m/female_07.mdl"},
		{"models/player/zelpa/male_11_extended.mdl", "group03", "models/humans/group03/male_01.mdl"},
		{"models/humans/group01/female_02.mdl", "group03", "models/humans/group03/female_02.mdl"},
		{"models/police.mdl", "group03", "models/police.mdl"}
	}

	for _, case in ipairs(cases) do
		local result = Schema:GetUniformModel(case[1], case[2])

		if (result != case[3]) then fail(case[1] .. " -> " .. tostring(result) .. ", expected " .. case[3]) end
		if (result != case[1] and !util.IsValidModel(result)) then fail(result .. " is not a valid model") end
	end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.Snapshot(bot)
	local character = bot:GetCharacter()
	local inventory = character:GetInventory()
	local zelpa = "models/player/zelpa/male_03_extended.mdl"

	S.Become(bot, FACTION_CITIZEN)
	character:SetModel(zelpa)

	for uniqueID, expected in pairs({resistance_uniform = "models/humans/group03/male_03.mdl", rmedic_uniform = "models/humans/group03m/male_03.mdl"}) do
		inventory:Add(uniqueID)

		local item = inventory:HasItem(uniqueID)

		if (!item) then
			fail("could not give " .. uniqueID)
		else
			item.player = bot
			item.functions.Equip.OnRun(item)

			if (character:GetModel() != expected) then fail(uniqueID .. " gave model " .. character:GetModel()) end

			item.functions.EquipUn.OnRun(item)

			if (character:GetModel() != zelpa) then fail(uniqueID .. " did not restore the model, left " .. character:GetModel()) end

			item:Remove()
		end
	end

	S.Restore(bot, state)

	-- the extra bot is only needed by this file
	local target = S.Target()

	if (IsValid(target)) then target:Kick("gw_harness") end
end)
