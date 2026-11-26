local PLUGIN = PLUGIN

-- Maximum lengths of the free-text answers, in the order the form sends them (fields 3-9).
PLUGIN.answerFields = {
	{"referral", 300},
	{"why", 600},
	{"story", 1500},
	{"skills", 300},
	{"relocation", 600},
	{"family", 600},
	{"employment", 600}
}

PLUGIN.ACCEPTED = "!true"
PLUGIN.pendingSeen = PLUGIN.pendingSeen or {}

-- Reviewing applications uses the same permission as opening them with /ViewApplications.
function PLUGIN:CanReviewApplications(client)
	return IsValid(client) and ix.command.HasAccess(client, "ViewApplications")
end

local function Sanitize(text, limit)
	if (!isstring(text)) then
		return ""
	end

	return string.Trim(text):sub(1, limit)
end

function PLUGIN:DatabaseConnected()
	local query = mysql:Create("ix_applications")
		query:Create("app_id", "INT AUTO_INCREMENT")
		query:Create("name", "VARCHAR(128) NOT NULL")
		query:Create("cid", "VARCHAR(6) NOT NULL")
		query:Create("referral", "TEXT")
		query:Create("why", "VARCHAR(600) DEFAULT NULL")
		query:Create("story", "VARCHAR(1500) DEFAULT NULL")
		query:Create("skills", "TEXT")
		query:Create("relocation", "TEXT")
		query:Create("family", "TEXT")
		query:Create("employment", "TEXT")
		query:Create("date", "TEXT")
		query:Create("steamid", "TEXT")
		query:Create("char_id", "TEXT")
		query:Create("response", "TEXT")
		query:Create("seen", "TEXT")
		query:PrimaryKey("app_id")
	query:Execute()
end

-- Shows the applicant the responses they have not acknowledged yet.
function PLUGIN:CharacterLoaded(character)
	local client = character:GetPlayer()

	if (!IsValid(client)) then
		return
	end

	local query = mysql:Select("ix_applications")
		query:Select("response")
		query:Select("name")
		query:Select("app_id")
		query:Where("char_id", character:GetID())
		query:Where("steamid", client:SteamID64())
		query:Where("seen", "false")
		query:Callback(function(results)
			if (!istable(results) or !IsValid(client) or client:GetCharacter() != character) then
				return
			end

			for _, v in ipairs(results) do
				if (isstring(v.response) and v.response != "") then
					netstream.Start(client, "ApplicationPlayerResponse",
						{v.response, false, v.response == PLUGIN.ACCEPTED, v.name, tonumber(v.app_id)})

					character:SetData("applicationopen", false)
				end
			end
		end)
	query:Execute()
end

-- The application form, sent by a character that logged in at a terminal. Identity comes
-- from the server; the client only supplies the free-text answers.
function PLUGIN:SubmitApplication(client, data)
	local character = client:GetCharacter()

	if (!character or !istable(data) or !client.ixApplicationTerminal) then
		return false
	end

	if (character:GetData("applicationopen", false)) then
		client:Notify("You cannot submit another application while you already have one open!")
		return false
	end

	local inventory = character:GetInventory()
	local cidItem = inventory and inventory:HasItem("cid")

	if (!cidItem) then
		client:Notify("You need a CID to do this.")
		return false
	end

	client.ixApplicationTerminal = nil

	local cid = tostring(cidItem:GetData("id", character:GetData("cid", ""))):sub(1, 6)
	local query = mysql:Insert("ix_applications")
		query:Insert("name", character:GetName():sub(1, 128))
		query:Insert("cid", cid)

		for k, field in ipairs(self.answerFields) do
			query:Insert(field[1], Sanitize(data[k + 2], field[2]))
		end

		query:Insert("date", os.date("%H:%M:%S - %d/%m/%Y", os.time()))
		query:Insert("steamid", client:SteamID64())
		query:Insert("char_id", tostring(character:GetID()))
		query:Insert("response", "")
		query:Insert("seen", "false")
		query:Callback(function()
			character:SetData("applicationopen", true)
		end)
	query:Execute()

	ix.log.AddRaw(client:Name() .. " has submitted an application.")

	return true
end

-- A reviewer's decision. `reason` is the rejection text, or PLUGIN.ACCEPTED.
function PLUGIN:RespondToApplication(client, appID, reason)
	if (!self:CanReviewApplications(client)) then
		return false
	end

	appID = tonumber(appID)
	reason = Sanitize(reason, 500)

	if (!appID or reason == "") then
		return false
	end

	local bResponded = false
	local query = mysql:Select("ix_applications")
		query:Select("name")
		query:Select("steamid")
		query:Select("char_id")
		query:Select("seen")
		query:Where("app_id", appID)
		query:Callback(function(results)
			local row = istable(results) and results[1]

			-- an acknowledged response has already been delivered and cannot change
			if (!row or row.seen == "true") then
				return
			end

			local update = mysql:Update("ix_applications")
				update:Update("response", reason)
				update:Where("app_id", appID)
			update:Execute()

			local character = ix.char.loaded[tonumber(row.char_id)]

			if (character and character:GetSteamID() == row.steamid) then
				character:SetData("applicationopen", false)

				local target = character:GetPlayer()

				if (IsValid(target) and target:GetCharacter() == character) then
					netstream.Start(target, "ApplicationPlayerResponse",
						{reason, true, reason == PLUGIN.ACCEPTED, row.name, appID})
				end
			end

			bResponded = true

			if (IsValid(client)) then
				ix.log.AddRaw(client:Name() .. " has responded to application #" .. appID .. ".")
			end
		end)
	query:Execute()

	-- only known here when the database is synchronous (SQLite)
	return bResponded
end

-- The applicant acknowledges a response. Only their own unacknowledged, answered application
-- counts, and an accepted one grants the letter once.
function PLUGIN:MarkApplicationSeen(client, appID)
	local character = client:GetCharacter()
	appID = tonumber(appID)

	if (!character or !appID or self.pendingSeen[appID]) then
		return false
	end

	self.pendingSeen[appID] = true

	local bGranted = false
	local query = mysql:Select("ix_applications")
		query:Select("name")
		query:Select("response")
		query:Where("app_id", appID)
		query:Where("char_id", character:GetID())
		query:Where("steamid", client:SteamID64())
		query:Where("seen", "false")
		query:Callback(function(results)
			local row = istable(results) and results[1]

			if (!row or !isstring(row.response) or row.response == "") then
				self.pendingSeen[appID] = nil
				return
			end

			local update = mysql:Update("ix_applications")
				update:Update("seen", "true")
				update:Where("app_id", appID)
				update:Callback(function()
					self.pendingSeen[appID] = nil
				end)
			update:Execute()

			if (row.response == PLUGIN.ACCEPTED and IsValid(client) and client:GetCharacter() == character) then
				character:GetInventory():Add("acceptance_paper", 1, {
					application = "Name: " .. row.name .. "\nIssue Date: " .. os.date("%H:%M:%S - %d/%m/%Y", os.time())
				})

				bGranted = true
			end

			if (IsValid(client)) then
				ix.log.AddRaw(client:Name() .. " has seen their applications' response.")
			end
		end)
	query:Execute()

	return bGranted
end

netstream.Hook("SubmitApplication", function(client, data)
	PLUGIN:SubmitApplication(client, data)
end)

netstream.Hook("ApplicationResponse", function(client, data)
	if (istable(data)) then
		PLUGIN:RespondToApplication(client, data[2], data[1])
	end
end)

netstream.Hook("ApplicationSeen", function(client, data)
	if (istable(data)) then
		PLUGIN:MarkApplicationSeen(client, data[3])
	end
end)
