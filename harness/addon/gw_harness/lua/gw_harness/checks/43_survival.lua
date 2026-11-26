-- Survival workstream checks: hunger/thirst, consumables, the downed state, death drops,
-- NPC spawning and drops, and the door plugins. Each check restores the bot afterwards.

local function Plugin(uniqueID, fail)
	local plugin = ix.plugin.list[uniqueID]

	if (!plugin) then
		fail(uniqueID .. " is not loaded")
	end

	return plugin
end

-- Sets configs for the duration of `fn` and puts the old values back even if it errors.
local function WithConfig(values, fn)
	local old = {}

	for k, v in pairs(values) do
		old[k] = ix.config.Get(k)
		ix.config.Set(k, v)
	end

	local ok, err = pcall(fn)

	for k, v in pairs(old) do
		ix.config.Set(k, v)
	end

	if (!ok) then error(err, 0) end
end

local function Damage(target, amount, damageType, attacker)
	local info = DamageInfo()
		info:SetDamage(amount)
		info:SetDamageType(damageType or DMG_GENERIC)
		info:SetAttacker(attacker or game.GetWorld())
		info:SetInflictor(attacker or game.GetWorld())
		info:SetDamagePosition(target:GetPos())
	target:TakeDamageInfo(info)
end

-- Gets the bot back on its feet with full health, alive and not ragdolled.
local function ResetBot(bot)
	if (!bot:Alive()) then
		bot:Spawn()
	end

	if (IsValid(bot.ixRagdoll)) then
		bot.ixRagdoll.ixWeapons = nil
		bot:SetRagdolled(false)
	end

	bot.ixRagdoll = nil
	bot.ixKnockoutGrace = nil
	bot:SetHealth(100)
	bot:SetArmor(0)
end

local function Count(inventory, uniqueID)
	if (ix.stack) then
		return ix.stack.Count(inventory, uniqueID)
	end

	return inventory:GetItemCount(uniqueID)
end

local function RemoveAll(inventory, uniqueID)
	for _, v in pairs(inventory:GetItemsByUniqueID(uniqueID)) do
		v:Remove()
	end
end

GWH.Check("survival: needs drain at the configured rate and only damage when set to", function(fail)
	local plugin = Plugin("survivaladditions", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local character = bot:GetCharacter()
	local detail = {}

	ResetBot(bot)

	WithConfig({
		hungerthirstEnabled = true, hungerLossTime = 10, thirstLossTime = 20,
		hungerDamage = 5, thirstDamage = 0, needsRespawnLevel = 40
	}, function()
		if (!timer.Exists(plugin:GetTimerName(character))) then
			fail("enabling hungerthirstEnabled did not start the character's needs timer")
		end

		-- 6 s of a 10 minute bar is 1 point; of a 20 minute bar, 0.5
		character:SetHunger(100)
		character:SetThirst(100)
		plugin:NeedsTick(bot, character, 6)

		detail.hungerAfterTick = character:GetHunger()
		detail.thirstAfterTick = character:GetThirst()

		if (math.abs(character:GetHunger() - 99) > 1e-6) then
			fail("hunger after a 6 s tick with a 10 minute loss time is " .. character:GetHunger() .. ", expected 99")
		end

		if (math.abs(character:GetThirst() - 99.5) > 1e-6) then
			fail("thirst after a 6 s tick with a 20 minute loss time is " .. character:GetThirst() .. ", expected 99.5")
		end

		-- empty hunger with hungerDamage = 5
		character:SetHunger(0.01)
		bot:SetHealth(50)
		plugin:NeedsTick(bot, character, 6)

		if (character:GetHunger() != 0) then fail("hunger did not reach zero") end
		if (bot:Health() != 45) then fail("starving at hungerDamage 5 left health at " .. bot:Health() .. ", expected 45") end

		-- empty thirst with thirstDamage = 0: no damage and, above all, no death
		character:SetHunger(100)
		character:SetThirst(0)
		bot:SetHealth(3)
		plugin:NeedsTick(bot, character, 6)

		if (!bot:Alive()) then
			fail("thirstDamage 0 killed the character")
		elseif (bot:Health() != 3) then
			fail("thirstDamage 0 changed health to " .. bot:Health())
		end

		-- a lethal starvation tick kills, and death leaves the bars at the respawn level
		character:SetHunger(0)
		plugin:NeedsTick(bot, character, 6)

		if (bot:Alive()) then
			fail("starving at 3 health with hungerDamage 5 did not kill")
		elseif (character:GetHunger() != 40 or character:GetThirst() != 40) then
			fail("after death hunger/thirst are " .. character:GetHunger() .. "/" .. character:GetThirst() .. ", expected 40/40")
		end

		ResetBot(bot)

		-- noclip and a disabled config both pause the drain
		ix.config.Set("hungerthirstEnabled", false)
		character:SetHunger(80)
		plugin:NeedsTick(bot, character, 60)

		if (character:GetHunger() != 80) then fail("needs drained while hungerthirstEnabled is off") end
		if (timer.Exists(plugin:GetTimerName(character))) then fail("disabling the config left the needs timer running") end
	end)

	character:SetHunger(100)
	character:SetThirst(100)
	ResetBot(bot)

	return detail
end)

GWH.Check("survival: needs timer follows the character's load and unload", function(fail)
	local plugin = Plugin("survivaladditions", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local character = bot:GetCharacter()
	local name = plugin:GetTimerName(character)

	WithConfig({hungerthirstEnabled = true}, function()
		hook.Run("CharacterLoaded", character)
		if (!timer.Exists(name)) then fail("CharacterLoaded did not start the needs timer") end

		plugin:OnCharacterDisconnect(bot, character)
		if (timer.Exists(name)) then fail("the needs timer survived OnCharacterDisconnect") end

		plugin:StartNeeds(character)
		plugin:PlayerLoadedCharacter(bot, character, character)
		if (timer.Exists(name)) then fail("the needs timer survived switching away from the character") end

		-- old per-player timers must be gone
		if (timer.Exists("ixHunger" .. bot:SteamID64()) or timer.Exists("ixThirst" .. bot:SteamID64())) then
			fail("old per-player ixHunger/ixThirst timers still exist")
		end
	end)
end)

GWH.Check("survival: low needs slow stamina regeneration", function(fail)
	local plugin = Plugin("survivaladditions", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local character = bot:GetCharacter()

	WithConfig({hungerthirstEnabled = true, needsLowThreshold = 25, needsLowStaminaScale = 0.5}, function()
		character:SetHunger(100)
		character:SetThirst(100)

		if (hook.Run("AdjustStaminaOffset", bot, 2) != nil) then fail("stamina regeneration changed with full needs") end

		character:SetThirst(10)
		local offset = hook.Run("AdjustStaminaOffset", bot, 2)

		if (offset != 1) then fail("regeneration with low thirst is " .. tostring(offset) .. ", expected 1") end
		if (hook.Run("AdjustStaminaOffset", bot, -1) != nil) then fail("drain was scaled; only regeneration should be") end
	end)

	character:SetThirst(100)
end)

GWH.Check("survival: every food and drink restores its needs and returns its container", function(fail)
	local plugin = Plugin("survivaladditions", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	ResetBot(bot)

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()
	local team = bot:Team()
	local tested = {}

	for uniqueID, itemTable in SortedPairs(ix.item.list) do
		local action = (itemTable.base == "base_eatable" and "Eat") or (itemTable.base == "base_drinkable" and "Drink")

		if (!action) then
			continue
		end

		-- Combine-only and citizen-only food
		bot:SetTeam(uniqueID == "metropolice_supplements" and FACTION_MPF or FACTION_CITIZEN)

		local bAdded, err = inventory:Add(uniqueID)
		local item = bAdded and inventory:HasItem(uniqueID)

		if (!item) then
			fail(uniqueID .. ": could not give it to the bot (" .. tostring(err) .. ")")
			continue
		end

		local returned = {}

		for _, v in ipairs(itemTable.items or {}) do
			returned[v] = (returned[v] or 0) + Count(inventory, v)
		end

		character:SetHunger(30)
		character:SetThirst(30)

		local bRan = ix.item.PerformInventoryAction(bot, action, item:GetID(), inventory:GetID())
		local hunger = math.Clamp(30 + itemTable.restoredHunger, 0, 100)
		local thirst = math.Clamp(30 + itemTable.restoredThirst, 0, 100)

		if (!bRan) then
			fail(uniqueID .. ": " .. action .. " did not run")
		else
			if (character:GetHunger() != hunger) then
				fail(uniqueID .. ": hunger went 30 -> " .. character:GetHunger() .. ", expected " .. hunger)
			end

			if (character:GetThirst() != thirst) then
				fail(uniqueID .. ": thirst went 30 -> " .. character:GetThirst() .. ", expected " .. thirst)
			end

			if (inventory:GetItemByID(item:GetID())) then
				fail(uniqueID .. ": the item was not used up")
			end

			for v in pairs(returned) do
				if (Count(inventory, v) != returned[v] + 1) then
					fail(uniqueID .. ": did not return " .. v)
				end
			end
		end

		if (itemTable.restoredHunger == 0 and itemTable.restoredThirst == 0) then
			fail(uniqueID .. ": restores neither hunger nor thirst")
		end

		for v in pairs(returned) do RemoveAll(inventory, v) end
		tested[#tested + 1] = uniqueID
	end

	-- the poison gland keeps hurting; stop it
	timer.Remove("ixPoison" .. bot:SteamID64())
	bot:SetTeam(team)
	character:SetHunger(100)
	character:SetThirst(100)
	ResetBot(bot)

	-- the schema's food and water must be among them
	for _, v in ipairs({"water", "water_sparkling", "water_special", "supplements", "metropolice_supplements",
		"melon", "milk_carton", "chinese_takeout", "unclean_water"}) do
		if (!table.HasValue(tested, v)) then fail(v .. " is not a base_eatable/base_drinkable item") end
	end

	-- clean water beats what comes out of a puddle
	local clean, unclean = ix.item.list.water, ix.item.list.unclean_water

	if (clean and unclean and clean.restoredThirst <= unclean.restoredThirst) then
		fail("Breen's Water restores no more thirst than unclean water")
	end

	return {items = tested}
end)

GWH.Check("survival: empty cans only fill with unclean water, and only in water", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	for uniqueID, itemTable in SortedPairs(ix.item.list) do
		if (itemTable.fillsInto) then
			local filled = ix.item.list[itemTable.fillsInto]

			if (!filled) then
				fail(uniqueID .. " fills into unknown item " .. itemTable.fillsInto)
			elseif (!string.find(itemTable.fillsInto, "unclean", 1, true) or filled.base != "base_drinkable") then
				fail(uniqueID .. " fills into " .. itemTable.fillsInto .. ", which is not an unclean drink")
			end

			local item = setmetatable({player = bot}, {__index = itemTable})

			if (bot:WaterLevel() == 0 and item.functions.Fill.OnCanRun(item) != false) then
				fail(uniqueID .. " can be filled while not standing in water")
			end
		end
	end
end)

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

GWH.Check("survival: death runs its hooks without PAC3 and drops equipped weapons", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	if (pace) then return {skipped = "PAC3 is installed"} end

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

GWH.Check("survival: weapon items work without their SWEPs", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	for _, v in ipairs({"pistol", "stunstick", "ar2"}) do
		if (!ix.item.list[v]) then fail("faction loadout item " .. v .. " is missing") end
	end

	if (ix.plugin.list.tfa_support or ix.item.list.ammo_assault) then
		fail("tfa_support is still loaded")
	end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()
	local errors = #GWH.errors

	ResetBot(bot)

	-- pistol's SWEP is external content: equipping it must fail quietly
	inventory:Add("pistol")
	local item = inventory:HasItem("pistol")

	if (item) then
		ix.item.PerformInventoryAction(bot, "Equip", item:GetID(), inventory:GetID())

		if (item:GetData("equip")) then
			ix.item.PerformInventoryAction(bot, "EquipUn", item:GetID(), inventory:GetID())
		end

		item:Remove()
	end

	if (#GWH.errors > errors) then fail("equipping a weapon without its SWEP raised " .. GWH.errors[#GWH.errors].error) end

	for _, v in ipairs({"shotgun", "waterpipe"}) do
		if (ix.item.list[v] and !ix.item.list[v].isShotgun) then fail(v .. " is not marked isShotgun for breaching") end
	end
end)

GWH.Check("survival: every NPC spawner group spawns", function(fail)
	local plugin = Plugin("npcspawner", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local position = bot:GetPos() + Vector(0, 0, 120)
	local spawned = {}
	local height = 0

	if (!plugin.spawngroups.blackheadcrab) then fail("no black headcrab group") end

	-- removed NPCs linger until the end of the frame, so each spawn gets its own spot
	local function NextPosition()
		height = height + 100
		return position + Vector(0, 0, height)
	end

	for group, classes in SortedPairs(plugin.spawngroups) do
		local npc = plugin:SpawnAt({NextPosition(), group})

		if (!IsValid(npc)) then
			fail(group .. ": nothing spawned")
		else
			if (!table.HasValue(classes, npc:GetClass())) then fail(group .. ": spawned " .. npc:GetClass()) end

			spawned[group] = npc:GetClass()
			npc:Remove()
		end
	end

	-- a point saved with a group that no longer exists falls back instead of erroring
	local npc = plugin:SpawnAt({NextPosition(), "no_such_group"})

	if (!IsValid(npc)) then
		fail("a point with an unknown group spawned nothing")
	else
		npc:Remove()
	end

	-- saves from before this fix can have holes and missing groups
	local points, getData = plugin.spawnpoints, plugin.GetData
	plugin.GetData = function() return {[1] = {position, "zombie"}, [3] = {position}} end
	plugin:LoadData()
	plugin.GetData = getData

	local groups = {}

	for _, v in ipairs(plugin.spawnpoints) do groups[v[2]] = true end

	if (#plugin.spawnpoints != 2 or !groups.zombie or !groups[plugin.defaultGroup]) then
		fail("LoadData did not compact old spawn points and default their groups")
	end

	plugin.spawnpoints = points

	return spawned
end)

GWH.Check("survival: NPC drop tables only produce existing items", function(fail)
	local plugin = Plugin("npcdropitems", fail)
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local detail = {}
	local height = 120

	for class, drops in SortedPairs(plugin.drops) do
		local rolled = {}

		for _ = 1, 500 do
			for _, uniqueID in ipairs(plugin:RollDrops(class)) do
				rolled[uniqueID] = (rolled[uniqueID] or 0) + 1
			end
		end

		for uniqueID in pairs(rolled) do
			if (!ix.item.list[uniqueID]) then fail(class .. " drops unknown item " .. uniqueID) end
		end

		if (!next(rolled)) then fail(class .. " dropped nothing in 500 kills") end

		-- one real kill with every drop forced
		local forced = {}

		for _, v in ipairs(drops) do forced[#forced + 1] = {v[1], 1} end

		local npc = ents.Create(class)
		height = height + 150
		npc:SetPos(bot:GetPos() + Vector(0, 0, height))
		npc:Spawn()

		local position = npc:GetPos()
		plugin.drops[class] = forced
		npc:TakeDamage(100000, game.GetWorld(), game.GetWorld())
		plugin.drops[class] = drops

		local found = {}

		for _, v in ipairs(ents.FindInSphere(position, 96)) do
			if (v:GetClass() == "ix_item" and v:GetItemTable()) then
				found[v:GetItemTable().uniqueID] = true
				v:Remove()
			end
		end

		for _, v in ipairs(forced) do
			if (!found[v[1]]) then fail("killing " .. class .. " did not drop " .. v[1]) end
		end

		if (IsValid(npc)) then npc:Remove() end

		detail[class] = rolled
	end

	for _, class in ipairs({"npc_zombie", "npc_headcrab_black"}) do
		if (!plugin.drops[class]) then fail(class .. " has no drops") end
	end

	return detail
end)

GWH.Check("survival: door plugins work on a spawned door", function(fail)
	local bot = GWH.Bot()
	local kick = Plugin("kickdoor", fail)
	local shoot = Plugin("shootlock", fail)
	local stealth = Plugin("stealthability", fail)
	if (!bot or !kick or !shoot or !stealth) then return fail("no bot or plugin") end

	ResetBot(bot)

	local door = ents.Create("prop_door_rotating")
	door:SetModel("models/props_c17/door01_left.mdl")
	door:SetKeyValue("hardware", "1")
	door:SetKeyValue("distance", "90")
	door:SetKeyValue("speed", "100")
	door:SetKeyValue("returndelay", "-1")
	door:SetPos(bot:GetPos() + Vector(80, 0, 54))
	door:Spawn()
	door:Activate()

	local team = bot:Team()
	local errors = #GWH.errors

	-- kickdoor: per-player cooldown and stamina, impact through the validity-checked path
	bot:SetTeam(FACTION_MPF)
	bot:SetLocalVar("stm", 100)
	bot.ixNextKick = nil

	local bCanKick, message = kick:CanKick(bot, door)

	if (!bCanKick) then
		fail("a still Combine bot 80 units from a door cannot kick it: " .. tostring(message))
	else
		kick:Kick(bot, door)

		if (bot:GetLocalVar("stm", 0) != 100 - kick.staminaCost) then fail("kicking did not cost stamina") end
		if (kick:CanKick(bot, door)) then fail("no cooldown after a kick") end
		if (!bot.ixNextKick) then fail("the cooldown is not stored on the player") end

		kick:KickImpact(bot, door, true)

		if (!IsValid(door.ixDummy)) then
			fail("a breaking kick did not blast the door")
		else
			door.ixDummy:Remove()
		end
	end

	bot:SetTeam(FACTION_CITIZEN)
	bot.ixNextKick = nil
	if (kick:CanKick(bot, door)) then fail("a citizen can kick doors") end
	bot:SetTeam(team)

	-- shootlock: an NPC or the world shooting a door must not error
	local npc = ents.Create("npc_headcrab")
	npc:SetPos(bot:GetPos() + Vector(0, 0, 120))
	npc:Spawn()

	for _, attacker in ipairs({npc, game.GetWorld()}) do
		local info = DamageInfo()
			info:SetDamage(10)
			info:SetDamageType(DMG_BULLET)
			info:SetAttacker(attacker)
			info:SetInflictor(attacker)
			info:SetDamagePosition(door:GetPos())
		shoot:EntityTakeDamage(door, info)
	end

	npc:Remove()

	if (shoot:IsShotgun(NULL)) then fail("IsShotgun accepted a NULL weapon") end

	shoot:BreachDoor(bot, door, door:GetPos())

	if (!IsValid(door.ixDummy)) then
		fail("a shotgun breach did not blast the door")
	else
		door.ixDummy:Remove()
	end

	-- stealthability: a use alternates the per-door flag and records who used it
	stealth:PlayerUse(bot, door)
	stealth:PlayerUse(bot, door)

	if (door:GetNWEntity("ControlingPlayer") != bot) then
		fail("using a door did not record the player for stealthability")
	end

	if (#GWH.errors > errors) then fail("door plugins raised " .. GWH.errors[#GWH.errors].error) end

	-- the kick's delayed impact runs after this and must cope with the door being gone
	door:Remove()
end)

GWH.Check("survival: hunger and thirst admin commands run", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local errors = #GWH.errors

	for name, getter in pairs({charsethunger = "GetHunger", charsetthirst = "GetThirst"}) do
		local command = ix.command.list[name]

		if (!command) then
			fail(name .. " is not registered")
		else
			command.OnRun(command, bot, character, 0)

			if (character[getter](character) != 0) then fail(name .. " 0 did not set the value to 0") end
		end
	end

	if (#GWH.errors > errors) then fail("the commands raised " .. GWH.errors[#GWH.errors].error) end

	character:SetHunger(100)
	character:SetThirst(100)
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
