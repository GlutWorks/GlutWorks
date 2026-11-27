local PLUGIN = PLUGIN
Datafile = Datafile or {}

PLUGIN.name = "Datafile"
PLUGIN.author = "James"
PLUGIN.description = "Adds /Datafile."

ix.util.Include("cl_plugin.lua")
ix.util.Include("cl_hooks.lua")
ix.util.Include("sv_plugin.lua")
ix.util.Include("sv_hooks.lua")

-- All the categories possible. Yes, the names are quite annoying.
Datafile.Categories = {
	["med"] = true,     -- Medical note.
	["union"] = true,   -- Union (CWU, WI, UP) type note.
	["civil"] = true    -- Civil Protection/CTA type note.
}

DATAFILE_PERMISSION_NONE = 0
DATAFILE_PERMISSION_MINOR = 1
DATAFILE_PERMISSION_MEDIUM = 2
DATAFILE_PERMISSION_ELEVATED = 3

-- What each tier allows, lowest to highest:
--   MINOR     Civil Protection recruits: read unrestricted files without civil entries, add
--             medical and union entries
--   MEDIUM    Civil Protection units: read full files, add civil entries, set the civil
--             status, put out and lift BOLs
--   ELEVATED  command ranks, Overwatch and administrators: restrict files, manage files
--             (remove entries)
-- A file can only be opened by someone of at least the owner's own tier, and nobody writes
-- to their own file through the panel.
Datafile.Permissions = {
	[FACTION_MPF] = DATAFILE_PERMISSION_MEDIUM,
	[FACTION_OTA] = DATAFILE_PERMISSION_ELEVATED,
	[FACTION_ADMIN] = DATAFILE_PERMISSION_ELEVATED
}

-- Civil Protection officers with a command rank manage files; recruits get the lowest tier.
Datafile.CommandPermission = DATAFILE_PERMISSION_ELEVATED
Datafile.RecruitPermission = DATAFILE_PERMISSION_MINOR

-- Bounds for the points one entry can add or subtract.
Datafile.MaxEntryPoints = 100

-- A file is stored as JSON in a TEXT column (65,535 bytes on MySQL) and sent whole in one net
-- message (64 KB), so its size is bounded: at most MaxEntries entries of MaxEntryLength bytes.
-- Escaping can double the text, which still leaves about 50 KB for a full file.
Datafile.MaxEntries = 40
Datafile.MaxEntryLength = 500
Datafile.MaxReasonLength = 200

-- Seconds between two entries added by the same player.
Datafile.EntryCooldown = 3

-- All the civil statuses. Just for verification purposes.
Datafile.CivilStatus = {
	"Anti-Citizen",
	"Citizen",
	"Black",
	"Brown",
	"Red",
	"Blue",
	"Green",
	"White",
	"Gold",
	"Platinum",
}

function Datafile:Date()
	return os.date("%H:%M:%S - %d/%m/%Y", os.time())
end

-- Fresh default tables. Built on each call so their dates are the time of use.
function Datafile:GetDefault()
	return {
		GenericData = {
			bol = {false, ""},
			restricted = {false, ""},
			civilStatus = "Citizen",
			lastSeen = self:Date(),
			points = 0,
			sc = 0,
		},
		CivilianData = {
			[1] = {
				category = "union", -- med, union, civil
				text = "TRANSFERRED TO DISTRICT WORKFORCE.",
				date = self:Date(),
				points = 0,
				poster = {"Overwatch", "BOT"},
			},
		},
		CombineData = {
			[1] = {
				category = "union", -- med, union, civil
				text = "INSTATED AS CIVIL PROTECTOR.",
				date = self:Date(),
				points = 0,
				poster = {"Overwatch", "BOT"},
			},
		},
	}
end

do
	local COMMAND = {}
	COMMAND.description = "View the datafile of someone."
	COMMAND.arguments = {ix.type.player}

	function COMMAND:OnRun(client, target)
		if (!Datafile:IsValidTarget(target)) then
			return "This datafile does not exist."
		end

		Datafile:HandleDatafile(client, target)
	end

	ix.command.Add("Datafile", COMMAND)

	COMMAND = {}
	COMMAND.description = "Clear the datafile of someone."
	COMMAND.arguments = {ix.type.player}
	COMMAND.superAdminOnly = true

	function COMMAND:OnRun(client, target)
		if (!Datafile:IsValidTarget(target)) then
			return "This datafile does not exist."
		end

		Datafile:ClearDatafile(target)

		return target:Name() .. "'s file has been cleared."
	end

	ix.command.Add("ClearDatafile", COMMAND)

	COMMAND = {}
	COMMAND.description = "Manage the datafile of someone."
	COMMAND.arguments = {ix.type.player}

	function COMMAND:OnRun(client, target)
		if (!Datafile:CanAccess(client, target, DATAFILE_PERMISSION_ELEVATED)) then
			return "You are not authorized to access this datafile."
		end

		Datafile:SendManagementPanel(client, target)
	end

	ix.command.Add("ManageDatafile", COMMAND)

	COMMAND = {}
	COMMAND.description = "Make someone their datafile (un)restricted."
	COMMAND.arguments = {
		ix.type.player,
		bit.bor(ix.type.string, ix.type.optional)
	}

	function COMMAND:OnRun(client, target, reason)
		if (!reason or reason == "") then
			reason = nil
		else
			reason = reason:sub(1, Datafile.MaxReasonLength)
		end

		if (Datafile:CanAccess(client, target, DATAFILE_PERMISSION_ELEVATED)) then
			if (reason) then
				Datafile:SetRestricted(true, reason, target, client)

				return target:Name() .. "'s file has been restricted."
			else
				Datafile:SetRestricted(false, "", target, client)

				return target:Name() .. "'s file has been unrestricted."
			end
		else
			return "You do not have access to this datafile!"
		end
	end

	ix.command.Add("RestrictDatafile", COMMAND)
end