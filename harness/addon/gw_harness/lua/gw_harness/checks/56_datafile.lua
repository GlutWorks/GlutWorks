-- Datafile (datafile): permission tiers, the receivers, row ownership, entry caps and rate limits, rows that do
-- not parse, writes bound to someone else's current character, and restricted files. Receivers are called the
-- way a net message would call them, with a bot as the sender and a second bot as the target.

local Lib = GWH.Lib
local HasNotice = Lib.HasNotice

local S = Lib.NewS()

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

	S.Net("AddDatafileEntry", bot, {target, "union", "cp note", "1e9"})

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

	local bot, target = GWH.Bot(), S.ReviewTarget()
	if (!bot or !target) then fail("no bots") return end

	local state, targetState = S.SnapshotWithFlags(bot), S.SnapshotWithFlags(target)

	S.Become(bot, FACTION_MPF, "MPF-04.51004")
	S.Become(target, FACTION_CITIZEN)
	LoadDatafile(bot)
	LoadDatafile(target)

	if (!target.Datafile or !bot.Datafile) then
		S.RestoreWithFlags(bot, state)
		S.RestoreWithFlags(target, targetState)
		fail("the bots' datafiles did not load")
		return
	end

	Datafile:ClearDatafile(target)

	return bot, target, function()
		Datafile:ClearDatafile(target)
		Datafile:ClearDatafile(bot)
		bot.ixNextDatafileEntry = nil
		S.RestoreWithFlags(bot, state)
		S.RestoreWithFlags(target, targetState)
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
