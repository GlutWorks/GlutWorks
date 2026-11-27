-- Survival additions (survivaladditions): hunger and thirst draining and their timer, low needs slowing stamina,
-- every food and drink, filling empty cans, the hunger and thirst admin commands, and the poison from a
-- headcrab gland. Each check restores the bot afterwards.

local Lib = GWH.Lib
local Plugin, WithConfig, ResetBot, RemoveAll = Lib.Plugin, Lib.WithConfig, Lib.ResetBot, Lib.RemoveAll
local ScopedLenient, ResetBotFully = Lib.ScopedLenient, Lib.ResetBotFully

local function Count(inventory, uniqueID)
	if (ix.stack) then
		return ix.stack.Count(inventory, uniqueID)
	end

	return inventory:GetItemCount(uniqueID)
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

GWH.Check("world review: poison stops when the character changes or dies", function(fail)
	local bot = GWH.Bot()
	local gland = ix.item.list.poison_headcrab_gland
	if (!bot or !gland) then return fail("no bot or poison gland") end

	local name = "ixPoison" .. bot:SteamID64()

	ScopedLenient(function(defer)
		defer(function() timer.Remove(name) ResetBotFully(bot) end)

		-- keep the tick so it can be run by hand
		local function Eat()
			local create, tick = timer.Create, nil

			timer.Create = function(identifier, delay, repetitions, callback)
				if (identifier == name) then tick = callback end
				return create(identifier, delay, repetitions, callback)
			end

			local ok, err = pcall(gland.OnConsumed, gland, bot)
			timer.Create = create

			if (!ok) then error(err, 0) end

			return tick
		end

		ResetBotFully(bot)
		local tick = Eat()
		if (!tick) then return fail("eating the gland started no poison timer") end

		tick()
		if (bot:Health() >= 100) then fail("the poison did no damage to the character that ate it") end

		-- switched to another character: the next tick does nothing
		local id = bot:GetNetVar("char")
		defer(function() bot:SetNetVar("char", id) end)

		bot:SetHealth(100)
		bot:SetNetVar("char", nil)
		tick()
		bot:SetNetVar("char", id)

		if (bot:Health() != 100) then fail("the poison hurt the player after they switched character") end
		if (timer.Exists(name)) then fail("the poison timer kept running after a character switch") end

		-- died: the timer is gone at once
		ResetBotFully(bot)
		Eat()
		bot:Kill()

		if (timer.Exists(name)) then fail("the poison timer survived the character's death") end
	end)
end)
