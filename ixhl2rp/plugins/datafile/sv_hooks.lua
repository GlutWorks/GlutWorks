local PLUGIN = PLUGIN

util.AddNetworkString("UpdateLastSeen")
util.AddNetworkString("UpdateCivilStatus")
util.AddNetworkString("AddDatafileEntry")
util.AddNetworkString("SetBOL")
util.AddNetworkString("RemoveDatafileLine")
util.AddNetworkString("RefreshDatafile")
util.AddNetworkString("RefreshManagefile")
util.AddNetworkString("CreateRestrictedDatafile")
util.AddNetworkString("CreateFullDatafile")
util.AddNetworkString("CreateManagementPanel")

hook.Add("DatabaseConnected", "Datafile", function()
	Datafile:Setup()
end)

hook.Add("OnWipeTables", "Datafile", function()
	Datafile:Wipe()
end)

-- Load the new character's file, creating it the first time.
hook.Add("PlayerLoadedCharacter", "Datafile", function(player, character)
	Datafile:LoadDatafile(player, true)
end)

-- Remove exactly the deleted character's row. Rows store the text SteamID.
hook.Add("CharacterDeleted", "Datafile", function(player, id, isCurrentChar)
	if (!IsValid(player) or !isnumber(id)) then
		return
	end

	local query = mysql:Delete("ix_datafile")
		query:Where("CharacterID", id)
		query:Where("SteamID", player:SteamID())
		query:Where("Schema", Schema.folder)
	query:Execute()

	if (player.Datafile and player.Datafile.characterID == id) then
		player.Datafile = nil
	end
end)

function Datafile:Setup()
	local query = mysql:Create("ix_datafile")
		query:Create("id", "INT(11) UNSIGNED NOT NULL AUTO_INCREMENT")
		query:Create("CharacterID", "VARCHAR(50) NOT NULL")
		query:Create("CharacterName", "VARCHAR(150) NOT NULL")
		query:Create("SteamID", "VARCHAR(60) NOT NULL")
		query:Create("Schema", "TEXT NOT NULL")
		query:Create("GenericData", "TEXT NOT NULL")
		query:Create("Datafile", "TEXT NOT NULL")
		query:PrimaryKey("id")
	query:Execute()
end

function Datafile:Wipe()
	mysql:Drop("ix_datafile"):Execute()
end

-- Load the datafile of the player's current character into the cache. With bCreate, a
-- character in a datafile faction that has no row yet gets one.
function Datafile:LoadDatafile(player, bCreate)
	local character = IsValid(player) and player:GetCharacter()

	-- never leave the previous character's file in place
	player.Datafile = nil

	if (!character) then
		return
	end

	local characterID = character:GetID()
	local queryObj = mysql:Select("ix_datafile")
		queryObj:Where("CharacterID", characterID)
		queryObj:Where("SteamID", player:SteamID())
		queryObj:Where("Schema", Schema.folder)
		queryObj:Callback(function(result)
			if (!IsValid(player) or player:GetCharacter() != character) then
				return
			end

			if (istable(result) and #result >= 1) then
				local GenericData = util.JSONToTable(result[1].GenericData or "")
				local datafile = util.JSONToTable(result[1].Datafile or "")

				if (istable(GenericData) and istable(datafile)) then
					player.Datafile = {
						characterID = characterID,
						GenericData = GenericData,
						Datafile = datafile
					}
				else
					-- a row that no longer parses (truncated by an older, unbounded file) would
					-- otherwise leave the character without a file for good
					local default = self:GetDefault()

					self:UpdateDatafile(player, default.GenericData, player:IsCombine() and default.CombineData or default.CivilianData)
				end
			elseif (bCreate and !self:IsRestrictedFaction(player)) then
				self:CreateDatafile(player)
			end
		end)
	queryObj:Execute()
end

-- Create a datafile for the player's current character.
function Datafile:CreateDatafile(player)
	local character = IsValid(player) and player:GetCharacter()

	if (!character) then
		return
	end

	local default = self:GetDefault()
	local datafile = player:IsCombine() and default.CombineData or default.CivilianData

	local insertObj = mysql:Insert("ix_datafile")
		insertObj:Insert("CharacterID", character:GetID())
		insertObj:Insert("CharacterName", character:GetName())
		insertObj:Insert("SteamID", player:SteamID())
		insertObj:Insert("Schema", Schema.folder)
		insertObj:Insert("GenericData", util.TableToJSON(default.GenericData))
		insertObj:Insert("Datafile", util.TableToJSON(datafile))
		insertObj:Callback(function()
			if (IsValid(player) and player:GetCharacter() == character) then
				self:LoadDatafile(player)
			end
		end)
	insertObj:Execute()
end

-- Decides what to do when a player types /Datafile John Doe.
function Datafile:HandleDatafile(player, target)
	if (!self:CanAccess(player, target, DATAFILE_PERMISSION_MINOR)) then
		if (IsValid(player) and player:IsPlayer()) then
			self:NotifyDenied(player, target)
		end

		return false
	end

	local GenericData = self:ReturnGenericData(target)
	local datafile = self:ReturnDatafile(target)

	if (self:ReturnPermission(player) == DATAFILE_PERMISSION_MINOR) then
		local visible = {}

		for _, v in ipairs(datafile) do
			if (v.category != "civil") then
				visible[#visible + 1] = v
			end
		end

		net.Start("CreateRestrictedDatafile")
			net.WriteEntity(target)
			net.WriteTable(GenericData)
			net.WriteTable(visible)
			net.WriteUInt(target:GetCharacter():GetID(), 32)
		net.Send(player)
	else
		net.Start("CreateFullDatafile")
			net.WriteEntity(target)
			net.WriteTable(GenericData)
			net.WriteTable(datafile)
			net.WriteUInt(target:GetCharacter():GetID(), 32)
		net.Send(player)
	end

	return true
end

-- Net receivers. Every one re-checks the sender's access to the target's file. The write
-- receivers also take the character ID the panel was opened for, sent last.
Datafile.receivers = {}

function Datafile.receivers.UpdateLastSeen(player, target, characterID)
	if (Datafile:CanWrite(player, target, DATAFILE_PERMISSION_MINOR, characterID)) then
		return Datafile:UpdateLastSeen(target)
	end

	return false
end

function Datafile.receivers.UpdateCivilStatus(player, target, civilStatus, characterID)
	if (isstring(civilStatus) and Datafile:CanWrite(player, target, DATAFILE_PERMISSION_MEDIUM, characterID)) then
		return Datafile:SetCivilStatus(target, player, civilStatus)
	end

	return false
end

function Datafile.receivers.AddDatafileEntry(player, target, category, text, points, characterID)
	local minimum = category == "civil" and DATAFILE_PERMISSION_MEDIUM or DATAFILE_PERMISSION_MINOR

	if (!Datafile:CanWrite(player, target, minimum, characterID)) then
		return false
	end

	if ((player.ixNextDatafileEntry or 0) > CurTime()) then
		player:Notify("Please wait before adding another entry.")
		return false
	end

	if (Datafile:AddEntry(category, text, points, target, player, false)) then
		player.ixNextDatafileEntry = CurTime() + Datafile.EntryCooldown
		return true
	end

	return false
end

-- Toggles the target's BOL.
function Datafile.receivers.SetBOL(player, target, characterID)
	if (Datafile:CanWrite(player, target, DATAFILE_PERMISSION_MEDIUM, characterID)) then
		return Datafile:SetBOL(!Datafile:ReturnBOL(target), "", target, player)
	end

	return false
end

function Datafile.receivers.RemoveDatafileLine(player, target, key, date, category, text, characterID)
	if (Datafile:CanWrite(player, target, DATAFILE_PERMISSION_ELEVATED, characterID)) then
		return Datafile:RemoveEntry(player, target, key, date, category, text)
	end

	return false
end

function Datafile.receivers.RefreshDatafile(player, target)
	return Datafile:HandleDatafile(player, target)
end

function Datafile.receivers.RefreshManagefile(player, target)
	if (Datafile:CanAccess(player, target, DATAFILE_PERMISSION_ELEVATED)) then
		Datafile:SendManagementPanel(player, target)
		return true
	end

	return false
end

net.Receive("UpdateLastSeen", function(len, player)
	Datafile.receivers.UpdateLastSeen(player, net.ReadEntity(), net.ReadUInt(32))
end)

net.Receive("UpdateCivilStatus", function(len, player)
	Datafile.receivers.UpdateCivilStatus(player, net.ReadEntity(), net.ReadString(), net.ReadUInt(32))
end)

net.Receive("AddDatafileEntry", function(len, player)
	Datafile.receivers.AddDatafileEntry(player, net.ReadEntity(), net.ReadString(), net.ReadString(), net.ReadString(), net.ReadUInt(32))
end)

net.Receive("SetBOL", function(len, player)
	Datafile.receivers.SetBOL(player, net.ReadEntity(), net.ReadUInt(32))
end)

net.Receive("RemoveDatafileLine", function(len, player)
	Datafile.receivers.RemoveDatafileLine(player, net.ReadEntity(), net.ReadUInt(16), net.ReadString(), net.ReadString(), net.ReadString(), net.ReadUInt(32))
end)

net.Receive("RefreshDatafile", function(len, player)
	Datafile.receivers.RefreshDatafile(player, net.ReadEntity())
end)

net.Receive("RefreshManagefile", function(len, player)
	Datafile.receivers.RefreshManagefile(player, net.ReadEntity())
end)
