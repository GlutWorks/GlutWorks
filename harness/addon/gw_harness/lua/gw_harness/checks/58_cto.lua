-- Combine Terminal Overhaul (cto): it coexists with the schema's hooks and commands, edits the right character,
-- and the camera commands cope with an ID that is no entity.

local Lib = GWH.Lib
local HasNotice = Lib.HasNotice

local S = Lib.NewS()

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

GWH.Check("schema review: camera commands with an ID that is no entity", function(fail)
	if (!ix.command.list.cameradisable) then return {skipped = "cto not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.SnapshotWithFlags(bot)

	S.Become(bot, FACTION_OTA, "OTA-OWS.51009")

	for _, command in ipairs({"CameraDisable", "CameraEnable"}) do
		local notices
		local errors = S.Errors(function()
			notices = S.Notices(bot, function() S.Command(bot, "/" .. command .. " 4000") end)
		end)

		for _, err in ipairs(errors) do fail("/" .. command .. " 4000: " .. err) end

		if (!notices or !HasNotice(notices, "no combine camera")) then fail("/" .. command .. " 4000 sent no notice") end
	end

	S.RestoreWithFlags(bot, state)
end)
