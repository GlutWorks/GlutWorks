-- Protection teams (protectionteams): reassigning a missing team, team indices, and who may renumber a team.

local Lib = GWH.Lib

local S = Lib.NewS()

GWH.Check("protectionteams: reassigning a missing team", function(fail)
	local plugin = ix.plugin.list.protectionteams
	if (!plugin) then return {skipped = "protectionteams not loaded"} end

	local result

	for _, err in ipairs(S.Errors(function() result = plugin:ReassignTeam(97, 98, true) end)) do
		fail("ReassignTeam of a missing team: " .. err)
	end

	if (result != "@TeamNonExistent") then fail("ReassignTeam of a missing team returned " .. tostring(result)) end
end)

GWH.Check("schema review: protection team indices and reassignment", function(fail)
	local plugin = ix.plugin.list.protectionteams
	if (!plugin) then return {skipped = "protectionteams not loaded"} end

	local bot, target = GWH.Bot(), S.ReviewTarget()
	if (!bot or !target) then return fail("no bots") end

	local state, targetState = S.SnapshotWithFlags(bot), S.SnapshotWithFlags(target)
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

	S.RestoreWithFlags(bot, state)
	S.RestoreWithFlags(target, targetState)
end)
