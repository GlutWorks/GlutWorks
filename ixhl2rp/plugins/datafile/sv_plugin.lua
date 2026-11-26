local PLUGIN = PLUGIN

ix.log.AddType("datafile_entryadd", function(player, ...)
	local arg = {...}
	return Format("%s has added an entry to %s's datafile with category: %s", player:Name(), arg[1], arg[2])
end, FLAG_WARNING)

ix.log.AddType("datafile_entryrem", function(player, ...)
	local arg = {...}
	return Format("%s has removed an entry of %s's datafile with category: %s", player:Name(), arg[1], arg[2])
end, FLAG_WARNING)

ix.log.AddType("datafile_civilstatus", function(player, ...)
	local arg = {...}
	return Format("%s has changed %s's Civil Status to: %s", player:Name(), arg[1], arg[2])
end, FLAG_WARNING)

--[[ Datafile structure, stored as JSON:
	GenericData = {
		bol = {false, ""},
		restricted = {false, ""},
		civilStatus = "",
		lastSeen = "",
		points = 0,
		sc = 0,
	}
	Datafile = {
		[k] = {
			category = "", -- med, union, civil
			hidden = boolean,
			text = "",
			date = "",
			points = 0,
			poster = {charName, steamID, color},
		},
	}
]]

-- Write a player's datafile to the database and the cache.
function Datafile:UpdateDatafile(player, GenericData, datafile)
	local character = IsValid(player) and player:GetCharacter()

	if (!character) then
		return
	end

	local updateObj = mysql:Update("ix_datafile")
		updateObj:Where("CharacterID", character:GetID())
		updateObj:Where("SteamID", player:SteamID())
		updateObj:Where("Schema", Schema.folder)
		updateObj:Update("CharacterName", character:GetName())
		updateObj:Update("GenericData", util.TableToJSON(GenericData))
		updateObj:Update("Datafile", util.TableToJSON(datafile))
	updateObj:Execute()

	player.Datafile = {
		characterID = character:GetID(),
		GenericData = GenericData,
		Datafile = datafile
	}
end

-- Add a new entry. bCommand is used to prevent logging when /AddEntry is used.
function Datafile:AddEntry(category, text, points, player, poster, bCommand)
	if (!self.Categories[category] or !isstring(text)) then return false end

	local permission = self:ReturnPermission(poster)

	if (permission == DATAFILE_PERMISSION_NONE or (category == "civil" and permission <= DATAFILE_PERMISSION_MINOR)) then
		return false
	end

	local GenericData = self:ReturnGenericData(player)
	local datafile = self:ReturnDatafile(player)

	if (!GenericData or !datafile or self:IsFull(player, poster)) then return false end

	points = math.Clamp(math.floor(tonumber(points) or 0), -self.MaxEntryPoints, self.MaxEntryPoints)

	-- control characters other than newlines and tabs are escaped six bytes wide in JSON
	text = string.Trim((string.gsub(text, "[%z\1-\8\11-\31\127]", ""))):sub(1, self.MaxEntryLength)

	if (text == "") then return false end

	-- Combine earn SC instead of points.
	if (player:IsCombine()) then
		GenericData.sc = (tonumber(GenericData.sc) or 0) + points
	else
		GenericData.points = (tonumber(GenericData.points) or 0) + points
	end

	datafile[#datafile + 1] = {
		category = category,
		hidden = false,
		text = text,
		date = self:Date(),
		points = points,
		poster = {
			poster:GetCharacter():GetName(),
			poster:SteamID(),
			team.GetColor(poster:Team()),
		},
	}

	self:UpdateDatafile(player, GenericData, datafile)

	if (!bCommand) then
		ix.log.Add(poster, "datafile_entryadd", player:Name(), category)
	end

	return true
end

-- Whether the file has no room for another entry, telling the poster so.
function Datafile:IsFull(player, poster)
	local datafile = self:ReturnDatafile(player)

	if (datafile and #datafile >= self.MaxEntries) then
		if (IsValid(poster)) then
			poster:Notify("This datafile is full. A command rank must remove entries before anything else can be recorded.")
		end

		return true
	end

	return false
end

-- Set a player's Civil Status.
function Datafile:SetCivilStatus(player, poster, civilStatus)
	if (!table.HasValue(Datafile.CivilStatus, civilStatus)) then return false end
	if (self:ReturnPermission(poster) < DATAFILE_PERMISSION_MEDIUM) then return false end

	local GenericData = self:ReturnGenericData(player)

	-- every change is recorded as an entry, so it needs room for one
	if (!GenericData or self:IsFull(player, poster)) then return false end

	GenericData.civilStatus = civilStatus

	self:AddEntry("union", poster:GetCharacter():GetName() .. " has changed " .. player:GetCharacter():GetName() .. "'s Civil Status to: " .. civilStatus, 0, player, poster)
	self:UpdateDatafile(player, GenericData, self:ReturnDatafile(player))

	ix.log.Add(poster, "datafile_civilstatus", player:Name(), civilStatus)

	return true
end

-- Clear a character's datafile.
function Datafile:ClearDatafile(player)
	local default = self:GetDefault()

	self:UpdateDatafile(player, default.GenericData, player:IsCombine() and default.CombineData or default.CivilianData)
end

-- Update the time a player has last been seen.
function Datafile:UpdateLastSeen(player)
	local GenericData = self:ReturnGenericData(player)

	if (!GenericData) then return false end

	GenericData.lastSeen = self:Date()

	self:UpdateDatafile(player, GenericData, self:ReturnDatafile(player))

	return true
end

-- Enable or disable a BOL on the player.
function Datafile:SetBOL(bBOL, text, player, poster)
	if (self:ReturnPermission(poster) < DATAFILE_PERMISSION_MEDIUM) then return false end

	local GenericData = self:ReturnGenericData(player)

	if (!GenericData or self:IsFull(player, poster)) then return false end

	GenericData.bol = {bBOL and true or false, bBOL and (text or "") or ""}

	self:AddEntry("union", poster:GetCharacter():GetName() .. (bBOL and " has put a bol on " or " has removed a bol on ") .. player:GetCharacter():GetName(), 0, player, poster)
	self:UpdateDatafile(player, GenericData, self:ReturnDatafile(player))

	return true
end

-- Make the file of a player restricted or not.
function Datafile:SetRestricted(bRestricted, text, player, poster)
	if (self:ReturnPermission(poster) < DATAFILE_PERMISSION_ELEVATED) then return false end

	local GenericData = self:ReturnGenericData(player)

	if (!GenericData or self:IsFull(player, poster)) then return false end

	GenericData.restricted = {bRestricted and true or false, bRestricted and (text or "") or ""}

	if (bRestricted) then
		self:AddEntry("civil", poster:GetCharacter():GetName() .. " has made " .. player:GetCharacter():GetName() .. "'s file restricted.", 0, player, poster)
	else
		self:AddEntry("civil", poster:GetCharacter():GetName() .. " has removed the restriction on " .. player:GetCharacter():GetName() .. "'s file.", 0, player, poster)
	end

	self:UpdateDatafile(player, GenericData, self:ReturnDatafile(player))

	return true
end

-- Remove an entry by its key, checking the date, category and text still match it.
function Datafile:RemoveEntry(player, target, key, date, category, text)
	if (!self:CanAccess(player, target, DATAFILE_PERMISSION_ELEVATED)) then return false end

	local datafile = self:ReturnDatafile(target)
	local entry = isnumber(key) and datafile[key]

	if (!entry or entry.date != date or entry.category != category or entry.text != text) then
		return false
	end

	table.remove(datafile, key)

	self:UpdateDatafile(target, self:ReturnGenericData(target), datafile)

	ix.log.Add(player, "datafile_entryrem", target:Name(), category)

	return true
end

-- Return the amount of points someone has.
function Datafile:ReturnPoints(player)
	local GenericData = self:ReturnGenericData(player)

	if (!GenericData) then return 0 end

	return player:IsCombine() and GenericData.sc or GenericData.points
end

function Datafile:ReturnCivilStatus(player)
	local GenericData = self:ReturnGenericData(player)

	return GenericData and GenericData.civilStatus
end

-- The cached file of the player's current character, or nil when it is not loaded.
function Datafile:GetCache(player)
	local cache = IsValid(player) and player.Datafile
	local character = IsValid(player) and player:GetCharacter()

	if (cache and character and cache.characterID == character:GetID()) then
		return cache
	end
end

-- Return GenericData in normal table format.
function Datafile:ReturnGenericData(player)
	local cache = self:GetCache(player)

	return cache and cache.GenericData
end

-- Return Datafile in normal table format.
function Datafile:ReturnDatafile(player)
	local cache = self:GetCache(player)

	return cache and cache.Datafile
end

-- Return the BOL of a player.
function Datafile:ReturnBOL(player)
	local GenericData = self:ReturnGenericData(player)

	if (GenericData and istable(GenericData.bol) and GenericData.bol[1]) then
		return true, GenericData.bol[2] or ""
	end

	return false, ""
end

-- Return the permission of a player. The higher, the more privileges.
function Datafile:ReturnPermission(player)
	if (!IsValid(player) or !player:IsPlayer() or !player:GetCharacter()) then
		return DATAFILE_PERMISSION_NONE
	end

	local permission = self.Permissions[player:Team()] or DATAFILE_PERMISSION_NONE

	if (player:Team() == FACTION_MPF and Schema:IsCombineRank(player:Name(), "RCT")) then
		permission = self.RecruitPermission
	elseif (Schema:HasCommandRank(player)) then
		permission = math.max(permission, self.CommandPermission)
	end

	return permission
end

-- Returns if the player their file is restricted or not, and the text if it is.
function Datafile:IsRestricted(player)
	local GenericData = self:ReturnGenericData(player)

	if (GenericData and istable(GenericData.restricted) and GenericData.restricted[1]) then
		return true, GenericData.restricted[2] or ""
	end

	return false, ""
end

-- If the player is apart of any of the factions allowing a datafile, return false.
function Datafile:IsRestrictedFaction(player)
	local factionTable = ix.faction.indices[player:Team()]

	return !(factionTable and factionTable.bAllowDatafile)
end

-- A player whose current character has a loaded datafile.
function Datafile:IsValidTarget(target)
	return IsValid(target) and target:IsPlayer() and target:GetCharacter() != nil
		and !self:IsRestrictedFaction(target) and self:GetCache(target) != nil
end

-- Whether `player` may act on `target`'s file with at least the `minimum` tier.
function Datafile:CanAccess(player, target, minimum)
	if (!IsValid(player) or !player:IsPlayer() or !player:GetCharacter() or !self:IsValidTarget(target)) then
		return false
	end

	local permission = self:ReturnPermission(player)

	if (permission == DATAFILE_PERMISSION_NONE or permission < (minimum or DATAFILE_PERMISSION_MINOR)) then
		return false
	end

	if (permission < self:ReturnPermission(target)) then
		return false
	end

	-- the lowest tier cannot open restricted files
	if (permission == DATAFILE_PERMISSION_MINOR and self:IsRestricted(target)) then
		return false
	end

	return true
end

-- Tells `player` why they cannot act on `target`'s file at the `minimum` tier.
function Datafile:NotifyDenied(player, target)
	local bRestricted, restrictedText = self:IsRestricted(target)

	if (bRestricted and self:ReturnPermission(player) == DATAFILE_PERMISSION_MINOR) then
		player:Notify("This datafile has been restricted; access denied. REASON: " .. restrictedText)
	else
		player:Notify("You are not authorized to do that with this datafile.")
	end
end

-- Whether `player` may write to `target`'s file through the panel, telling them why not.
-- characterID is the character the panel was opened for; a different one means the target
-- has switched characters since, and the write would land on the wrong file. 0 means the
-- sender did not bind the write to a character (the client always does).
function Datafile:CanWrite(player, target, minimum, characterID)
	if (!IsValid(player) or !player:IsPlayer() or !player:GetCharacter()) then
		return false
	end

	if (!self:IsValidTarget(target)) then
		player:Notify("This datafile does not exist.")
		return false
	end

	if (player == target) then
		player:Notify("You cannot edit your own datafile.")
		return false
	end

	if (isnumber(characterID) and characterID != 0 and characterID != target:GetCharacter():GetID()) then
		player:Notify("The datafile you had open belongs to a character who is no longer present.")
		return false
	end

	if (!self:CanAccess(player, target, minimum)) then
		self:NotifyDenied(player, target)
		return false
	end

	return true
end

function Datafile:SendManagementPanel(player, target)
	net.Start("CreateManagementPanel")
		net.WriteEntity(target)
		net.WriteTable(self:ReturnDatafile(target) or {})
		net.WriteUInt(target:GetCharacter():GetID(), 32)
	net.Send(player)
end
