-- Applications (applicationsystem): only reviewers decide and only applicants collect, a letter that does not fit
-- is dropped, acknowledgements are rate limited, /ViewApplications with many full-length applications, one open
-- application per player, and a deleted character's applications go with it.

local Lib = GWH.Lib

local S = Lib.NewS()

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

	local bot, other = GWH.Bot(), S.ReviewTarget()
	if (!bot or !other) then return fail("no bots") end

	local state = S.SnapshotWithFlags(bot)
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
	S.RestoreWithFlags(bot, state)
end)
