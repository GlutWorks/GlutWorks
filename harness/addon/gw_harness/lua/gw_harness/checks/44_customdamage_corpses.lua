-- Knockouts and death (customdamage, persistent_corpses, Helix's death hooks): a knockdown leaves no permanent
-- half damage, zero damage does not knock out, a knockout is decided from the health a hit left, a knockout
-- resumes on rejoin, item actions are refused while downed, dead or tied, death drops equipped weapons, dying
-- while knocked out with and without persistent corpses, and corpse cleanup. Each check restores the bot.

local Lib = GWH.Lib
local Plugin, WithConfig, ResetBot, RemoveAll = Lib.Plugin, Lib.WithConfig, Lib.ResetBot, Lib.RemoveAll
local ScopedLenient, ResetBotFully, Live = Lib.ScopedLenient, Lib.ResetBotFully, Lib.Live

local function Damage(target, amount, damageType, attacker)
	local info = DamageInfo()
		info:SetDamage(amount)
		info:SetDamageType(damageType or DMG_GENERIC)
		info:SetAttacker(attacker or game.GetWorld())
		info:SetInflictor(attacker or game.GetWorld())
		info:SetDamagePosition(target:GetPos())
	target:TakeDamageInfo(info)
end

local function Downed(bot)
	return IsValid(bot.ixRagdoll) and !bot.ixRagdoll:IsMarkedForDeletion()
end

GWH.Check("survival: a knockdown does not leave permanent half damage", function(fail)
	local plugin = Plugin("customdamage", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	ResetBot(bot)

	-- what a 30 point hit normally does, other plugins' scaling included
	Damage(bot, 30)
	local normal = 100 - bot:Health()
	bot:SetHealth(100)

	-- getting up leaves a removed (NULL) ragdoll behind in ixRagdoll
	bot.ixRagdoll = NULL
	Damage(bot, 30)
	local afterGetup = 100 - bot:Health()

	if (afterGetup != normal) then
		fail("after getting up a 30 damage hit did " .. afterGetup .. ", a normal one does " .. normal)
	end

	-- knocked out for real: health 30, a 15 point hit leaves 15, under the 20 threshold
	ResetBot(bot)
	bot:SetHealth(30)
	Damage(bot, 15)

	local ragdoll = bot.ixRagdoll

	if (!IsValid(ragdoll) or !ragdoll.ixKnockout) then
		fail("a hit leaving 15 health did not knock the character out")
	else
		-- while downed, damage is halved (past the brief grace window)
		bot.ixKnockoutGrace = 0
		bot:SetHealth(100)
		Damage(bot, 20)

		if (100 - bot:Health() != normal * 20 / 30 / 2) then
			fail("a downed character took " .. (100 - bot:Health()) .. " from a 20 damage hit, expected half")
		end
	end

	ResetBot(bot)

	return {normal = normal, afterGetup = afterGetup}
end)

GWH.Check("survival: zero damage at low health does not knock out", function(fail)
	local plugin = Plugin("customdamage", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	ResetBot(bot)
	bot:SetHealth(10)

	local info = DamageInfo()
		info:SetDamage(0)
		info:SetDamageType(DMG_GENERIC)
		info:SetAttacker(game.GetWorld())
		info:SetInflictor(game.GetWorld())
	plugin:EntityTakeDamage(bot, info)
	bot:TakeDamageInfo(info)

	if (IsValid(bot.ixRagdoll)) then
		fail("a zero-damage event at 10 health knocked the character out")
	end

	ResetBot(bot)
end)

GWH.Check("survival: disconnecting while unconscious resumes on rejoin", function(fail)
	local plugin = Plugin("customdamage", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local character = bot:GetCharacter()

	ResetBot(bot)
	plugin:KnockOut(bot, 60)
	plugin:OnCharacterDisconnect(bot, character)

	local saved = character:GetData("knockout")

	if (!isnumber(saved) or saved <= 0) then
		fail("disconnecting while unconscious did not store the remaining time (got " .. tostring(saved) .. ")")
	end

	ResetBot(bot)
	plugin:ResumeKnockout(bot, character)

	if (!IsValid(bot.ixRagdoll) or !bot.ixRagdoll.ixKnockout) then
		fail("loading the character did not resume the knockout")
	end

	if (character:GetData("knockout") != nil) then
		fail("the stored knockout was not cleared after resuming")
	end

	ResetBot(bot)

	-- not knocked out: nothing is stored
	plugin:OnCharacterDisconnect(bot, character)

	if (character:GetData("knockout") != nil) then
		fail("disconnecting while awake stored a knockout")
	end
end)

GWH.Check("survival: death runs its hooks and drops equipped weapons", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()

	ResetBot(bot)

	local function Equip(uniqueID)
		inventory:Add(uniqueID)
		local item = inventory:HasItem(uniqueID)

		if (item) then
			ix.item.PerformInventoryAction(bot, "Equip", item:GetID(), inventory:GetID())
		end

		return item
	end

	local function KillAndCheck(label, item)
		local errors = #GWH.errors
		local deaths = bot:Deaths()

		bot:Kill()

		if (#GWH.errors > errors) then fail(label .. ": death raised " .. GWH.errors[#GWH.errors].error) end
		if (bot:Deaths() != deaths + 1) then fail(label .. ": GM:DoPlayerDeath did not run") end
		if (!bot:GetNetVar("deathTime")) then fail(label .. ": GM:PlayerDeath did not run") end
		if (pace and next(bot:GetParts() or {})) then fail(label .. ": PAC parts stayed on the dead player") end

		if (item) then
			if (item.invID == inventory:GetID()) then
				fail(label .. ": the equipped " .. item.uniqueID .. " stayed in the inventory")
			elseif (IsValid(item:GetEntity())) then
				item:GetEntity():Remove()
			end
		end

		bot:SetNetVar("deathTime", nil)
		ResetBot(bot)
	end

	-- ix_stunstick ships with the schema, so this one equips for real
	local stunstick = Equip("stunstick")

	if (!stunstick or !bot:HasWeapon("ix_stunstick")) then
		fail("could not equip the stunstick")
	end

	KillAndCheck("standing", stunstick)

	-- knocked out first: the weapon went into the ragdoll's list when they fell
	stunstick = Equip("stunstick")
	ix.plugin.list.customdamage:KnockOut(bot, 60)

	if (stunstick and stunstick:GetData("equip")) then
		fail("the stunstick stayed equipped through the knockout")
	end

	KillAndCheck("unconscious", stunstick)

	RemoveAll(inventory, "stunstick")
end)

-- persistent_corpses, Helix's death hooks and ragdollstate all act on a knocked-out player's
-- ragdoll when they die. With corpses on it becomes the corpse; with them off Helix removes it.
-- Either way the knockout countdown must not carry on and later stand the dead player up.
GWH.Check("survival: dying while knocked out, with and without persistent corpses", function(fail)
	local bot = GWH.Bot()
	local plugin = Plugin("customdamage", fail)
	if (!bot or !plugin or !Plugin("persistent_corpses", fail)) then return fail("no bot or plugin") end

	local timerID = "ixUnRagdoll" .. bot:SteamID()
	local detail = {}

	for _, bCorpses in ipairs({true, false}) do
		local label = bCorpses and "corpses on" or "corpses off"

		WithConfig({persistentCorpses = bCorpses}, function()
			ResetBot(bot)
			plugin:KnockOut(bot, 60)

			local ragdoll = bot.ixRagdoll

			if (!IsValid(ragdoll)) then
				return fail(label .. ": the knockout made no ragdoll")
			end

			bot:Kill()

			local bKept = IsValid(ragdoll) and !ragdoll:IsMarkedForDeletion()
			local clientRagdoll = hook.Run("ShouldSpawnClientRagdoll", bot)

			detail[label] = {kept = bKept, clientRagdoll = clientRagdoll}

			if (bot:Alive()) then fail(label .. ": the bot survived Kill()") end
			if (timer.Exists(timerID)) then fail(label .. ": the knockout countdown is still running on the dead player") end
			if (IsValid(bot.ixRagdoll) and !bot.ixRagdoll:IsMarkedForDeletion()) then
				fail(label .. ": the dead player still has a knockout ragdoll attached")
			end

			if (bCorpses) then
				if (!bKept) then
					fail(label .. ": the ragdoll did not stay as the corpse")
				else
					if (ragdoll:GetNetVar("isDeadPlayer") != true) then fail(label .. ": the corpse is not marked isDeadPlayer") end
					if (ragdoll.ixPlayer != nil) then fail(label .. ": the corpse still forwards damage to the player") end
				end

				if (clientRagdoll != false) then fail(label .. ": a clientside ragdoll would be spawned next to the corpse") end
			else
				if (bKept) then fail(label .. ": the knockout ragdoll was kept although corpses are off") end
				if (clientRagdoll == false) then fail(label .. ": the clientside ragdoll is suppressed, so the death leaves no body") end
			end

			if (IsValid(ragdoll)) then ragdoll:Remove() end

			bot:SetNetVar("deathTime", nil)
			ResetBot(bot)
		end)
	end

	return detail
end)

GWH.Check("survival: corpse cleanup keeps the newest corpses", function(fail)
	local plugin = Plugin("persistent_corpses", fail)
	if (!plugin) then return end

	local saved = plugin.corpses
	local corpses = {}

	for i = 1, 3 do
		corpses[i] = ents.Create("prop_physics")
		corpses[i]:SetModel("models/props_junk/popcan01a.mdl")
		corpses[i]:Spawn()
	end

	plugin.corpses = table.Copy(corpses)
	plugin:CleanupCorpses(1)

	if (#plugin.corpses != 1 or plugin.corpses[1] != corpses[3]) then
		fail("cleaning up to 1 corpse kept " .. #plugin.corpses .. ", expected only the newest")
	end

	for _, v in ipairs(corpses) do
		if (IsValid(v)) then v:Remove() end
	end

	plugin.corpses = saved
end)

GWH.Check("world review: knockout is decided from the health the hit left", function(fail)
	local bot = GWH.Bot()
	if (!bot or !ix.plugin.list.customdamage) then return fail("no bot or customdamage") end

	local threshold = ix.config.Get("unconsciousHealth", 20)
	local detail = {}

	ScopedLenient(function(defer)
		defer(function() ResetBotFully(bot) end)

		-- armour takes most of an 85 point hit, so the character stays well above the threshold
		ResetBotFully(bot)
		bot:SetArmor(100)
		Damage(bot, 85)
		detail.armour = {health = bot:Health(), armour = bot:Armor(), downed = Downed(bot)}

		if (bot:Health() <= 100 - 85) then
			fail("armour absorbed nothing (health " .. bot:Health() .. "), so the scenario does not apply")
		elseif (bot:Health() >= threshold and Downed(bot)) then
			fail("an armoured hit leaving " .. bot:Health() .. " health knocked the character out")
		end

		-- god mode (an admin in observer): no damage and no ragdoll
		ResetBotFully(bot)
		bot:GodEnable()
		Damage(bot, 85)
		detail.god = {health = bot:Health(), downed = Downed(bot), god = bot:HasGodMode()}

		if (Downed(bot)) then fail("a player in god mode was knocked out") end
		if (bot:Health() != 100) then fail("a player in god mode took damage: health " .. bot:Health()) end
		if (!bot:HasGodMode()) then fail("god mode was switched off by the hit") end

		Damage(bot, 40, DMG_FALL)
		if (Downed(bot)) then fail("a player in god mode fell over from fall damage") end

		-- a plain hit that does cross the threshold still knocks out, and falling still falls over
		ResetBotFully(bot)
		Damage(bot, 85)
		detail.plain = {health = bot:Health(), downed = Downed(bot)}

		if (bot:Health() >= threshold) then
			fail("an unarmoured 85 point hit left " .. bot:Health() .. " health")
		elseif (!Downed(bot) or !bot.ixRagdoll.ixKnockout) then
			fail("a hit leaving " .. bot:Health() .. " health did not knock the character out")
		end

		ResetBotFully(bot)
		Damage(bot, 30, DMG_FALL)
		detail.fall = {health = bot:Health(), downed = Downed(bot)}

		if (!Downed(bot)) then
			fail("30 fall damage did not make the character fall over")
		elseif (bot.ixRagdoll.ixKnockout) then
			fail("falling at 70 health counted as a knockout")
		end

		-- a hit that kills does not leave a knockout behind
		ResetBotFully(bot)
		bot:SetHealth(10)
		Damage(bot, 50)
		if (bot:Alive()) then fail("a 50 point hit at 10 health did not kill") end
	end)

	return detail
end)

-- Item actions (eat, drink, fill, place a station) go through Helix's CanPlayerInteractItem,
-- which already refuses these states; this confirms nothing in the schema overrides that.
GWH.Check("world review: item actions refuse a downed, dead or tied player", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = bot:GetCharacter():GetInventory()

	ScopedLenient(function(defer)
		defer(function() ResetBotFully(bot) RemoveAll(inventory, "water") RemoveAll(inventory, "workbench") end)

		for _, state in ipairs({"downed", "tied", "dead"}) do
			ResetBotFully(bot)
			RemoveAll(inventory, "water")
			RemoveAll(inventory, "workbench")
			inventory:Add("water")
			inventory:Add("workbench")

			local water, workbench = inventory:HasItem("water"), inventory:HasItem("workbench")
			local stations = #Live("ix_station_workbench")

			if (state == "downed") then
				bot:SetRagdolled(true)
			elseif (state == "tied") then
				bot:SetRestricted(true)
			else
				bot:Kill()
			end

			ix.item.PerformInventoryAction(bot, "Drink", water:GetID(), inventory:GetID())
			ix.item.PerformInventoryAction(bot, "place", workbench:GetID(), inventory:GetID())

			if (!inventory:GetItemByID(water:GetID())) then fail("a " .. state .. " player could drink") end
			if (!inventory:GetItemByID(workbench:GetID()) or #Live("ix_station_workbench") != stations) then
				fail("a " .. state .. " player could place a station")
			end
		end
	end)
end)
