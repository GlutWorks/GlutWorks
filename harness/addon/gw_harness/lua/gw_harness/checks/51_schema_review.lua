-- Fixes from the schema review: business prices and flags, datafile caps, ownership and tiers,
-- applications, map cleanup persistence, door_saver on a wipe, nicknames, protection teams,
-- camera commands, Combine data and paper edits. A second bot is the hostile sender or target.

local S = {}

function S.Target()
	for _, v in ipairs(player.GetBots()) do
		if (v.gwhReviewTarget and v:GetCharacter()) then return v end
	end

	local bot = player.CreateNextBot("GWH Review")

	if (IsValid(bot)) then
		bot.gwhReviewTarget = true
		return bot:GetCharacter() and bot
	end
end

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
		flags = character:GetFlags()
	}
end

function S.Restore(client, state)
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

function S.Stream(name, sender, ...)
	local callback = netstream.stored[name]
	if (!callback) then error("no netstream hook " .. name) end

	callback(sender, ...)
end

function S.Command(client, text)
	client.ixCommandCooldown = nil
	ix.command.Parse(client, text)
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

-- Notices sent to `client` while fn ran, as text.
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

local function HasNotice(notices, text)
	for _, v in ipairs(notices) do
		if (string.find(string.lower(v), string.lower(text), 1, true)) then return true end
	end

	return false
end

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

-- netstream messages started while fn runs, as {name, args}.
function S.Streamed(fn)
	local sent = {}
	local start = netstream.Start

	netstream.Start = function(receiver, name, ...)
		sent[#sent + 1] = {name = name, args = {...}}
		return start(receiver, name, ...)
	end

	local ok, err = pcall(fn)
	netstream.Start = start

	if (!ok) then error(err, 0) end

	return sent
end

local function Shipments() return #ents.FindByClass("ix_shipment") end

local function ClearShipments()
	for _, v in ipairs(ents.FindByClass("ix_shipment")) do v:Remove() end
end

-- Buys one of uniqueID through the real receiver; returns whether a shipment came and what it cost.
local function Buy(client, uniqueID, money)
	local character = client:GetCharacter()

	character:SetMoney(money)
	client.ixNextBusiness = nil

	local before = Shipments()
	S.Net("ixBusinessBuy", client, {1, uniqueID, 1})

	return Shipments() > before, money - character:GetMoney()
end

GWH.Check("schema review: business items need a positive price", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.Snapshot(bot)
	local itemTable = ix.item.list.zip_tie
	local price = itemTable.price

	S.Become(bot, FACTION_MPF, "MPF-04.51001")

	for _, probe in ipairs({false, 0, -5}) do
		itemTable.price = probe or nil

		local bShipped, cost = Buy(bot, "zip_tie", 100)

		if (bShipped or cost != 0) then
			fail("zip_tie with price " .. tostring(itemTable.price) .. " was sold (cost " .. cost .. ")")
		end
	end

	itemTable.price = price

	local bShipped, cost = Buy(bot, "zip_tie", 100)

	if (!bShipped) then
		fail("a priced zip_tie was not sold to Civil Protection")
	elseif (cost != price) then
		fail("zip_tie cost " .. cost .. ", expected " .. tostring(price))
	end

	-- the schema's allow-listed items that had no price
	for _, uniqueID in ipairs({"ar2ammo", "pistolammo", "smg1ammo", "resistance_uniform", "rmedic_uniform"}) do
		local item = ix.item.list[uniqueID]

		if (item and !(isnumber(item.price) and item.price > 0)) then
			fail(uniqueID .. " has no price")
		end
	end

	ClearShipments()
	S.Restore(bot, state)
end)

GWH.Check("schema review: a held flag opts a flag-only item in", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.Snapshot(bot)
	local character = bot:GetCharacter()
	local uniform = ix.item.list.resistance_uniform

	S.Become(bot, FACTION_CITIZEN)
	character:SetFlags("")

	if (hook.Run("CanPlayerUseBusiness", bot, "resistance_uniform") != false) then
		fail("resistance_uniform is buyable without the v flag")
	end

	character:SetFlags("vV")

	local bShipped, cost = Buy(bot, "resistance_uniform", 500)

	if (!bShipped) then
		fail("a citizen holding the v flag could not buy resistance_uniform")
	elseif (cost != uniform.price) then
		fail("resistance_uniform cost " .. cost .. ", expected " .. tostring(uniform.price))
	end

	-- a flag on an item with a class allow-list is an extra requirement, not an opt-in
	if (hook.Run("CanPlayerUseBusiness", bot, "pistolammo") != false) then
		fail("a citizen with the V flag can buy pistolammo, which is limited to elite classes")
	end

	ClearShipments()
	S.Restore(bot, state)
end)

GWH.Check("schema review: Overwatch may edit the objectives", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.Snapshot(bot)
	local objectives = Schema.CombineObjectives

	S.Become(bot, FACTION_OTA, "OTA-OWS.51002")
	Schema.CombineObjectives = {text = "before"}
	bot.ixNextObjectivesEdit = nil

	S.Stream("ViewObjectivesUpdate", bot, "overwatch")

	if (Schema.CombineObjectives.text != "overwatch") then fail("an Overwatch soldier could not edit the objectives") end

	Schema.CombineObjectives = objectives
	ix.data.Set("combineObjectives", objectives, false, true)
	bot.ixNextObjectivesEdit = nil
	S.Restore(bot, state)
end)

GWH.Check("schema review: Combine data edits are rate limited", function(fail)
	local bot, target = GWH.Bot(), S.Target()
	if (!bot or !target) then return fail("no bots") end

	local state, targetState = S.Snapshot(bot), S.Snapshot(target)
	local targetCharacter = target:GetCharacter()

	S.Become(bot, FACTION_MPF, "MPF-04.51003")
	S.Become(target, FACTION_CITIZEN)
	targetCharacter:SetData("combineData", nil)
	bot.ixNextDataEdit = nil

	S.Stream("ViewDataUpdate", bot, target, "first")

	local notices = S.Notices(bot, function()
		for i = 1, 20 do S.Stream("ViewDataUpdate", bot, target, "flood " .. i) end
	end)

	local data = targetCharacter:GetData("combineData")

	if (!istable(data) or data.text != "first") then
		fail("21 edits in one tick left the text at " .. tostring(istable(data) and data.text))
	end

	if (!HasNotice(notices, "wait")) then fail("a refused Combine data edit sent no notice") end

	bot.ixNextDataEdit = nil
	S.Stream("ViewDataUpdate", bot, target, "later")

	if (targetCharacter:GetData("combineData", {}).text != "later") then fail("an edit after the cooldown was refused") end

	targetCharacter:SetData("combineData", nil)
	bot.ixNextDataEdit = nil
	S.Restore(bot, state)
	S.Restore(target, targetState)
end)

-- Datafile helpers, as the datafile plugin's own check uses them.
local function LoadDatafile(client)
	hook.GetTable().PlayerLoadedCharacter.Datafile(client, client:GetCharacter())
end

local function File(client)
	return client.Datafile and client.Datafile.Datafile or {}
end

local function AddEntry(sender, target, category, text, points, characterID)
	sender.ixNextDatafileEntry = nil
	S.Net("AddDatafileEntry", sender, {target, category, text, points, characterID})
end

local function Opened(viewer, target)
	local names = S.Sent(function() S.Net("RefreshDatafile", viewer, {target}) end)

	return table.HasValue(names, "CreateFullDatafile") or table.HasValue(names, "CreateRestrictedDatafile")
end

local function DatafileSetup(fail)
	if (!Datafile) then return end

	local bot, target = GWH.Bot(), S.Target()
	if (!bot or !target) then fail("no bots") return end

	local state, targetState = S.Snapshot(bot), S.Snapshot(target)

	S.Become(bot, FACTION_MPF, "MPF-04.51004")
	S.Become(target, FACTION_CITIZEN)
	LoadDatafile(bot)
	LoadDatafile(target)

	if (!target.Datafile or !bot.Datafile) then
		S.Restore(bot, state)
		S.Restore(target, targetState)
		fail("the bots' datafiles did not load")
		return
	end

	Datafile:ClearDatafile(target)

	return bot, target, function()
		Datafile:ClearDatafile(target)
		Datafile:ClearDatafile(bot)
		bot.ixNextDatafileEntry = nil
		S.Restore(bot, state)
		S.Restore(target, targetState)
	end
end

GWH.Check("schema review: datafile entries are capped and rate limited", function(fail)
	local bot, target, Cleanup = DatafileSetup(fail)
	if (!bot) then return Datafile and nil or {skipped = "datafile not loaded"} end

	local count = #File(target)

	bot.ixNextDatafileEntry = nil
	S.Net("AddDatafileEntry", bot, {target, "union", "first", "0"})

	local notices = S.Notices(bot, function()
		S.Net("AddDatafileEntry", bot, {target, "union", "second", "0"})
	end)

	if (#File(target) != count + 1) then fail("two entries in one tick gave " .. (#File(target) - count) .. " entries, expected 1") end
	if (!HasNotice(notices, "wait")) then fail("a rate limited entry sent no notice") end

	-- quotes double in JSON, the worst case for the stored size
	local text = string.rep("\"", 1000)

	notices = S.Notices(bot, function()
		for i = 1, 80 do AddEntry(bot, target, "civil", text, "1") end
	end)

	local maxEntries = Datafile.MaxEntries or 40
	local file = File(target)
	local json = util.TableToJSON(file)

	if (#file != maxEntries) then fail("80 entries left " .. #file .. " in the file, the cap is " .. maxEntries) end
	if (#json > 60000) then fail("a full file is " .. #json .. " bytes of JSON; a TEXT column holds 65535") end
	if (!HasNotice(notices, "full")) then fail("an entry refused for a full file sent no notice") end

	local bol = Datafile:ReturnBOL(target)
	S.Net("SetBOL", bot, {target})

	if (Datafile:ReturnBOL(target) != bol or #File(target) != maxEntries) then fail("a BOL change was recorded in a full file") end

	Cleanup()
end)

GWH.Check("schema review: a datafile row that does not parse is recreated", function(fail)
	local bot, target, Cleanup = DatafileSetup(fail)
	if (!bot) then return Datafile and nil or {skipped = "datafile not loaded"} end

	local characterID = target:GetCharacter():GetID()

	local update = mysql:Update("ix_datafile")
		update:Where("CharacterID", characterID)
		update:Where("SteamID", target:SteamID())
		update:Update("Datafile", "[{\"category\":\"uni")
	update:Execute()

	LoadDatafile(target)

	if (!target.Datafile) then
		fail("a truncated row left the character without a datafile")
	else
		local stored

		local query = mysql:Select("ix_datafile")
			query:Where("CharacterID", characterID)
			query:Where("SteamID", target:SteamID())
			query:Callback(function(result) stored = istable(result) and result[1] end)
		query:Execute()

		if (!stored or !istable(util.JSONToTable(stored.Datafile or ""))) then fail("the recreated row does not parse") end
	end

	Cleanup()
end)

GWH.Check("schema review: datafile writes are bound to someone else's current character", function(fail)
	local bot, target, Cleanup = DatafileSetup(fail)
	if (!bot) then return Datafile and nil or {skipped = "datafile not loaded"} end

	-- a unit's own file
	local points = Datafile:ReturnPoints(bot)
	local status = Datafile:ReturnCivilStatus(bot)
	local count = #File(bot)

	local notices = S.Notices(bot, function()
		AddEntry(bot, bot, "civil", "self", "100")
		S.Net("UpdateCivilStatus", bot, {bot, "Platinum"})
		S.Net("UpdateLastSeen", bot, {bot})
	end)

	if (#File(bot) != count or Datafile:ReturnPoints(bot) != points) then fail("a unit added an entry to its own file") end
	if (Datafile:ReturnCivilStatus(bot) != status) then fail("a unit changed its own civil status") end
	if (!HasNotice(notices, "own datafile")) then fail("a write to one's own file sent no notice") end

	-- a panel opened for another character than the one being played
	local characterID = target:GetCharacter():GetID()
	count = #File(target)

	notices = S.Notices(bot, function()
		AddEntry(bot, target, "union", "stale", "0", characterID + 1)
		S.Net("SetBOL", bot, {target, characterID + 1})
	end)

	if (#File(target) != count) then fail("an entry for a character no longer played was added to the current one") end
	if (Datafile:ReturnBOL(target)) then fail("a BOL for a character no longer played was put on the current one") end
	if (!HasNotice(notices, "no longer present")) then fail("a write for another character sent no notice") end

	AddEntry(bot, target, "union", "current", "0", characterID)

	if (#File(target) != count + 1) then fail("a write bound to the current character was refused") end

	Cleanup()
end)

GWH.Check("schema review: datafile tiers for recruits and units", function(fail)
	local bot, target, Cleanup = DatafileSetup(fail)
	if (!bot) then return Datafile and nil or {skipped = "datafile not loaded"} end

	-- an ordinary unit issues and lifts a BOL
	S.Net("SetBOL", bot, {target})

	if (!Datafile:ReturnBOL(target)) then fail("an ordinary Civil Protection unit could not put out a BOL") end

	S.Net("SetBOL", bot, {target})

	if (Datafile:ReturnBOL(target)) then fail("an ordinary Civil Protection unit could not lift a BOL") end

	-- a recruit is the lowest tier, and a restricted file is closed to it
	S.Become(bot, FACTION_OTA, "OTA-OWS.51005")
	Datafile:SetRestricted(true, "gwh", target, bot)

	if (!Datafile:IsRestricted(target)) then
		Cleanup()
		return fail("Overwatch could not restrict a file")
	end

	S.Become(bot, FACTION_MPF, "MPF-RCT.51005")

	if (Datafile:ReturnPermission(bot) != DATAFILE_PERMISSION_MINOR) then fail("a recruit is not the lowest datafile tier") end

	local count = #File(target)
	local bOpened

	local notices = S.Notices(bot, function()
		bOpened = Opened(bot, target)
		AddEntry(bot, target, "med", "recruit note", "0")
	end)

	if (bOpened) then fail("a recruit opened a restricted file") end
	if (#File(target) != count) then fail("a recruit added an entry to a restricted file") end
	if (!HasNotice(notices, "restricted")) then fail("a recruit refused by a restricted file got no notice") end

	-- an unrestricted file opens without the civil entries, and refusals say so
	S.Become(bot, FACTION_OTA, "OTA-OWS.51005")
	Datafile:SetRestricted(false, "", target, bot)
	S.Become(bot, FACTION_MPF, "MPF-RCT.51005")

	local names = S.Sent(function() S.Net("RefreshDatafile", bot, {target}) end)

	if (!table.HasValue(names, "CreateRestrictedDatafile")) then fail("a recruit was not sent the restricted view of a file") end

	notices = S.Notices(bot, function() S.Net("SetBOL", bot, {target}) end)

	if (Datafile:ReturnBOL(target)) then fail("a recruit put out a BOL") end
	if (#notices == 0) then fail("a refused BOL sent no notice") end

	Cleanup()
end)

-- Applications, inserted directly so the test controls their state.
local function InsertApplication(client, characterID, response, size)
	local character = client:GetCharacter()
	local plugin = ix.plugin.list.applicationsystem

	local query = mysql:Insert("ix_applications")
		query:Insert("name", character:GetName())
		query:Insert("cid", "51000")

		for _, field in ipairs(plugin.answerFields or {}) do
			query:Insert(field[1], string.rep("a", size and field[2] or 1))
		end

		query:Insert("date", "gwh")
		query:Insert("steamid", client:SteamID64())
		query:Insert("char_id", tostring(characterID))
		query:Insert("response", response)
		query:Insert("seen", "false")
	query:Execute()

	local appID

	local select = mysql:Select("ix_applications")
		select:Select("app_id")
		select:Where("steamid", client:SteamID64())
		select:OrderByDesc("app_id")
		select:Limit(1)
		select:Callback(function(result) appID = istable(result) and result[1] and tonumber(result[1].app_id) end)
	select:Execute()

	return appID
end

local function ApplicationRows(client, characterID)
	local rows

	local query = mysql:Select("ix_applications")
		query:Where("steamid", client:SteamID64())

		if (characterID) then query:Where("char_id", tostring(characterID)) end

		query:Callback(function(result) rows = istable(result) and result or {} end)
	query:Execute()

	return rows or {}
end

local function DeleteApplications(client)
	local query = mysql:Delete("ix_applications")
		query:Where("steamid", client:SteamID64())
	query:Execute()
end

local function LetterEntities()
	local result = {}

	for _, v in ipairs(ents.FindByClass("ix_item")) do
		local item = !v:IsMarkedForDeletion() and v.GetItemTable and v:GetItemTable()

		if (item and item.uniqueID == "acceptance_paper") then result[v] = true end
	end

	return result
end

GWH.Check("schema review: an accepted letter that does not fit is dropped", function(fail)
	local plugin = ix.plugin.list.applicationsystem
	if (!plugin) then return {skipped = "applicationsystem not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()

	DeleteApplications(bot)

	local appID = InsertApplication(bot, character:GetID(), "!true")
	local before = LetterEntities()

	-- a full inventory
	inventory.Add = function() return false, "noFit" end
	bot.ixApplicationSeenReset = nil
	plugin.pendingSeen[appID] = nil

	local ok, err = pcall(S.Stream, "ApplicationSeen", bot, {"cp", true, appID, "x"})
	inventory.Add = nil

	if (!ok) then fail("ApplicationSeen: " .. tostring(err)) end

	local dropped = {}

	for entity in pairs(LetterEntities()) do
		if (!before[entity]) then dropped[#dropped + 1] = entity end
	end

	if (#dropped != 1) then
		fail("a full inventory got " .. #dropped .. " letters on the ground, expected 1")
	elseif (dropped[1]:GetPos():Distance(bot:GetPos()) > 200) then
		fail("the letter was dropped " .. math.Round(dropped[1]:GetPos():Distance(bot:GetPos())) .. " units from the player")
	end

	for _, v in ipairs(dropped) do v:Remove() end

	-- acknowledgements are rate limited: past a short burst they are not even looked up
	appID = InsertApplication(bot, character:GetID(), "!true")
	bot.ixApplicationSeenReset = nil
	plugin.pendingSeen[appID] = nil

	for i = 1, 20 do plugin:MarkApplicationSeen(bot, 999000 + i) end

	if (plugin:MarkApplicationSeen(bot, appID)) then fail("21 acknowledgements in one tick were all looked up") end

	bot.ixApplicationSeenReset = nil
	plugin.pendingSeen[appID] = nil

	if (!plugin:MarkApplicationSeen(bot, appID)) then fail("an acknowledgement after the cooldown did not grant the letter") end

	for _, item in pairs(inventory:GetItemsByUniqueID("acceptance_paper", true) or {}) do item:Remove() end

	DeleteApplications(bot)
	bot.ixApplicationSeenReset = nil
end)

GWH.Check("schema review: /ViewApplications with 30 full-length applications", function(fail)
	local plugin = ix.plugin.list.applicationsystem
	if (!plugin) then return {skipped = "applicationsystem not loaded"} end

	local bot, other = GWH.Bot(), S.Target()
	if (!bot or !other) then return fail("no bots") end

	local state = S.Snapshot(bot)
	local character = bot:GetCharacter()
	local inventory = character:GetInventory()

	DeleteApplications(other)

	local appID

	for i = 1, 30 do
		appID = InsertApplication(other, 900100 + i, "rejected", true)
	end

	bot:SetUserGroup("superadmin")

	local sent
	local errors = S.Errors(function()
		sent = S.Streamed(function() S.Command(bot, "/ViewApplications") end)
	end)

	for _, err in ipairs(errors) do fail("/ViewApplications: " .. err) end

	local list

	for _, v in ipairs(sent or {}) do
		if (v.name == "SyncApplicationDataCP") then list = v.args[1] and v.args[1][1] end
	end

	if (!istable(list) or #list < 30) then
		fail("/ViewApplications sent " .. (istable(list) and #list or "no") .. " applications, expected at least 30")
	end

	-- one application's text on demand
	local detail

	errors = S.Errors(function()
		bot.ixNextApplicationFetch = nil
		sent = S.Streamed(function() S.Stream("RequestApplication", bot, appID) end)
	end)

	for _, err in ipairs(errors) do fail("RequestApplication: " .. err) end

	for _, v in ipairs(sent or {}) do
		if (v.name == "ApplicationDetail") then detail = v.args[1] end
	end

	if (!istable(detail) or tonumber(detail.app_id) != appID or #(detail.story or "") != 1500) then
		fail("RequestApplication did not send the full application")
	end

	-- the text is for reviewers only
	bot:SetUserGroup("user")
	bot.ixNextApplicationFetch = nil
	sent = S.Streamed(function() S.Stream("RequestApplication", bot, appID) end)

	for _, v in ipairs(sent) do
		if (v.name == "ApplicationDetail") then fail("a non-reviewer was sent an application") end
	end

	DeleteApplications(other)

	-- one unanswered application per player, whichever character sent it
	DeleteApplications(bot)
	InsertApplication(bot, 900003, "")
	inventory:Add("cid", 1, {name = character:GetName(), id = "51000"})
	character:SetData("applicationopen", nil)
	bot.ixApplicationTerminal = true

	S.Stream("SubmitApplication", bot, {"", "", "ref", "why", "story", "skills", "reloc", "family", "work"})

	if (#ApplicationRows(bot, character:GetID()) != 0) then fail("a second unanswered application was accepted from another character") end

	-- a deleted character's applications go with it
	local deleted = hook.GetTable().CharacterDeleted
	local handler = deleted and deleted.applicationsystem

	if (plugin.CharacterDeleted) then
		plugin:CharacterDeleted(bot, 900003, false)
	elseif (handler) then
		handler(bot, 900003, false)
	end

	if (#ApplicationRows(bot, 900003) != 0) then fail("deleting a character left its applications") end

	for _, item in pairs(inventory:GetItemsByUniqueID("cid", true) or {}) do
		if (item:GetData("id") == "51000") then item:Remove() end
	end

	DeleteApplications(bot)
	character:SetData("applicationopen", nil)
	bot.ixApplicationTerminal = nil
	S.Restore(bot, state)
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

GWH.Check("schema review: nicknames keep apostrophes and stay off Combine names", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.Snapshot(bot)
	local character = bot:GetCharacter()

	local function Reset()
		character:SetData("nicknameBase", nil)
		character:SetData("nicknameName", nil)
	end

	Reset()
	S.Become(bot, FACTION_MPF, "MPF-RCT 51006")

	local notices = S.Notices(bot, function() S.Command(bot, "/SetNickname x.SeC.x") end)

	if (character:GetName() != "MPF-RCT 51006") then fail("a Civil Protection unit took a nickname: " .. character:GetName()) end
	if (Schema:HasCommandRank(bot)) then fail("a nickname gave a recruit a command rank") end
	if (#notices == 0) then fail("a refused Combine nickname sent no notice") end

	Reset()
	S.Become(bot, FACTION_CITIZEN, "D'Arcy O'Neil")

	for _, case in ipairs({
		{"Chief", "D'Arcy 'Chief' O'Neil"},
		{"Boss", "D'Arcy 'Boss' O'Neil"},
		{"none", "D'Arcy O'Neil"}
	}) do
		S.Command(bot, "/SetNickname " .. case[1])

		if (character:GetName() != case[2]) then
			fail("/SetNickname " .. case[1] .. " gave '" .. character:GetName() .. "', expected '" .. case[2] .. "'")
		end
	end

	-- rank tokens in a citizen's name mean nothing
	S.Become(bot, FACTION_CITIZEN, "Mr SeC Jones")

	if (bot:IsDispatch()) then fail("a citizen named 'Mr SeC Jones' counts as dispatch") end

	Reset()
	S.Restore(bot, state)
end)

GWH.Check("schema review: protection team indices and reassignment", function(fail)
	local plugin = ix.plugin.list.protectionteams
	if (!plugin) then return {skipped = "protectionteams not loaded"} end

	local bot, target = GWH.Bot(), S.Target()
	if (!bot or !target) then return fail("no bots") end

	local state, targetState = S.Snapshot(bot), S.Snapshot(target)
	local used = {7, 7.5, 61, 62, 70, 71}

	local function Clear()
		for _, client in ipairs({bot, target}) do
			if (client.curTeam) then plugin:LeaveTeam(client) end
			client.curTeam = nil
			client.isTeamOwner = nil
		end

		for _, index in ipairs(used) do
			if (plugin.teams[index]) then plugin:DeleteTeam(index) end
		end
	end

	S.Become(bot, FACTION_MPF, "MPF-04.51007")
	S.Become(target, FACTION_MPF, "MPF-04.51008")
	Clear()

	for _, index in ipairs(used) do
		if (plugin.teams[index]) then Clear() return fail("team " .. index .. " already exists") end
	end

	S.Command(bot, "/PTCreate 61")
	S.Command(target, "/PTCreate 62")

	if (bot.curTeam != 61 or target.curTeam != 62) then
		Clear()
		return fail("/PTCreate did not create teams 61 and 62")
	end

	-- the owner of team 61 renumbers team 62
	S.Command(bot, "/PTReassign 70 62")

	if (!plugin.teams[62] or plugin.teams[70]) then fail("the owner of one team renumbered another") end

	S.Command(bot, "/PTReassign 71")

	if (!plugin.teams[71] or bot.curTeam != 71) then fail("an owner could not renumber their own team") end

	Clear()

	S.Command(bot, "/PTCreate 7.5")

	if (plugin.teams[7.5]) then fail("/PTCreate 7.5 created team 7.5") end
	if (!plugin.teams[7] or bot.curTeam != 7) then fail("/PTCreate 7.5 did not create team 7") end

	S.Command(target, "/PTJoin 7")

	if (target.curTeam != 7) then fail("/PTJoin 7 did not join the team made by /PTCreate 7.5") end

	Clear()

	for _, bad in ipairs({"0", "-3", "1e300", "100"}) do
		S.Command(bot, "/PTCreate " .. bad)

		if (bot.curTeam) then fail("/PTCreate " .. bad .. " created team " .. tostring(bot.curTeam)) end

		Clear()
	end

	S.Restore(bot, state)
	S.Restore(target, targetState)
end)

GWH.Check("schema review: camera commands with an ID that is no entity", function(fail)
	if (!ix.command.list.cameradisable) then return {skipped = "cto not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.Snapshot(bot)

	S.Become(bot, FACTION_OTA, "OTA-OWS.51009")

	for _, command in ipairs({"CameraDisable", "CameraEnable"}) do
		local notices
		local errors = S.Errors(function()
			notices = S.Notices(bot, function() S.Command(bot, "/" .. command .. " 4000") end)
		end)

		for _, err in ipairs(errors) do fail("/" .. command .. " 4000: " .. err) end

		if (!notices or !HasNotice(notices, "no combine camera")) then fail("/" .. command .. " 4000 sent no notice") end
	end

	S.Restore(bot, state)
end)

GWH.Check("schema review: a written paper cannot be rewritten through the receiver", function(fail)
	if (!ix.item.list.paper) then return {skipped = "writing not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = bot:GetCharacter():GetInventory()

	for _, item in pairs(inventory:GetItemsByUniqueID("paper", true) or {}) do item:Remove() end

	inventory:Add("paper")

	local paper = inventory:HasItem("paper")
	if (!paper) then return fail("could not give the bot a paper") end

	S.Stream("ixWritingEdit", bot, paper:GetID(), "first")

	if (paper:GetData("text") != "first") then fail("a blank paper could not be written on") end

	S.Stream("ixWritingEdit", bot, paper:GetID(), "rewritten")

	if (paper:GetData("text") != "first") then fail("the author rewrote a paper the menu no longer lets them edit") end

	paper:Remove()
end)

-- Last in this file: a real map cleanup also clears every other check's entities.
local CLEANUP_CLASSES = {"ix_rationdispenser", "ix_vendingmachine", "ix_forcefield"}
local CLEANUP_SAVES = {ix_rationdispenser = "rationDispensers", ix_vendingmachine = "vendingMachines", ix_forcefield = "forceFields"}

local function Live(class)
	local result = {}

	for _, v in ipairs(ents.FindByClass(class)) do
		if (!v:IsMarkedForDeletion()) then result[#result + 1] = v end
	end

	return result
end

GWH.Check("schema review: a map cleanup keeps the saved dispensers, vending machines and forcefields", function(fail)
	local base = Vector(5100, 5100, 64)
	local positions = {}

	for index, class in ipairs(CLEANUP_CLASSES) do
		positions[class] = {}

		for i = 1, 2 do
			local entity = ents.Create(class)
			entity:SetPos(base + Vector(i * 80, index * 160, 0))
			entity:Spawn()
			positions[class][i] = entity:GetPos()
		end
	end

	hook.Run("SaveData")

	local before = {}

	for _, class in ipairs(CLEANUP_CLASSES) do
		before[class] = #Live(class)
	end

	local errors = S.Errors(function() game.CleanUpMap() end)

	for _, err in ipairs(errors) do fail("game.CleanUpMap: " .. err) end

	for _, class in ipairs(CLEANUP_CLASSES) do
		local saved = #(ix.data.Get(CLEANUP_SAVES[class]) or {})

		if (#Live(class) != before[class]) then fail("after a cleanup " .. #Live(class) .. " " .. class .. " remain, expected " .. before[class]) end
		if (saved != before[class]) then fail("after a cleanup " .. saved .. " " .. class .. " are saved, expected " .. before[class]) end
	end

	-- an entity removed this frame is not saved again
	local removed = Live("ix_rationdispenser")[1]

	if (IsValid(removed)) then
		local count = #Live("ix_rationdispenser")

		Schema.bCleaningUp = true
		removed:Remove()
		Schema.bCleaningUp = false
		Schema:SaveRationDispensers()

		if (#(ix.data.Get("rationDispensers") or {}) != count - 1) then fail("a ration dispenser removed this frame was saved again") end
	end

	-- remove the ones made here, then save what is left
	Schema.bCleaningUp = true

	for _, class in ipairs(CLEANUP_CLASSES) do
		for _, entity in ipairs(Live(class)) do
			for _, position in ipairs(positions[class]) do
				if (entity:GetPos():Distance(position) < 1) then entity:Remove() end
			end
		end
	end

	Schema.bCleaningUp = false
	Schema:SaveData()

	-- the extra bot is only needed by this file
	for _, v in ipairs(player.GetBots()) do
		if (v.gwhReviewTarget) then v:Kick("gw_harness") end
	end
end)
