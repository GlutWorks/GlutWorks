-- Wear (wear): condition, effectiveness and level maths; boots worn by distance and its multipliers; nothing
-- wears in noclip or with wearEnabled off; damage wearing the slot that covers the hit; armour capacity from
-- condition and the armoured clothing's Repair; the modifier chain; one item per slot, equip, unequip and no
-- transfer while worn; repairs through ix.stack with material, tool and ceiling; the level-change hook and
-- notice; the new items and their recipes. Every check empties the bot's inventory afterwards and gets it
-- back on its feet.

local Lib = GWH.Lib
local Scoped, WithConfig, ResetBot, Fresh, GiveItem = Lib.Scoped, Lib.WithConfig, Lib.ResetBot, Lib.Fresh, Lib.GiveItem
local NewStack, Expect, Plugin = Lib.NewStack, Lib.Expect, Lib.Plugin
local S = Lib.NewS()

local NEW_ITEMS = {"work_boots", "winter_coat", "rain_poncho", "wool_gloves", "wool_cap", "sewing_kit"}

-- Units in one kilometre.
local KM = 1000 / 0.01905

local function Near(fail, label, actual, expected, epsilon)
	if (!isnumber(actual) or math.abs(actual - expected) > (epsilon or 1e-6)) then
		fail(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

-- Unequips everything without running the outfit code (the uniforms here are marked equipped directly),
-- then empties the inventory.
local function Clear(bot)
	for _, item in pairs(bot:GetCharacter():GetInventory():GetItems()) do
		if (item.data) then item.data.equip = nil end
	end

	Fresh(bot)
end

-- A fresh bot, inventory emptied, with cleanup deferred.
local function Setup(defer)
	local bot = GWH.Bot()

	if (!bot) then error("no bot") end

	ResetBot(bot)
	bot:SetMoveType(MOVETYPE_WALK)
	Clear(bot)

	defer(function()
		Clear(bot)
		bot:SetMoveType(MOVETYPE_WALK)
		ResetBot(bot)
	end)

	return bot, bot:GetCharacter():GetInventory()
end

-- Gives and equips a base_wearable item through its Equip action.
local function Wear(bot, inventory, uniqueID)
	local item = GiveItem(inventory, uniqueID)

	item.player = bot
	item.functions.Equip.OnRun(item)
	item.player = nil

	return item
end

-- Gives an outfit and marks it worn without the model change (the uniforms' own equip is checked in
-- 60_schema.lua).
local function WearOutfit(inventory, uniqueID)
	local item = GiveItem(inventory, uniqueID)
	item:SetData("equip", true)

	return item
end

GWH.Check("wear: condition, effectiveness and levels follow the curve", function(fail)
	if (!ix.wear) then return fail("ix.wear is missing") end

	Expect(fail, "effectiveness at 100", ix.wear.GetEffectiveness(100), 1)
	Expect(fail, "effectiveness at 60", ix.wear.GetEffectiveness(60), 1)
	Near(fail, "effectiveness at 30", ix.wear.GetEffectiveness(30), 0.75)
	Near(fail, "effectiveness at 15", ix.wear.GetEffectiveness(15), 1 - 0.75 * 0.75)
	Expect(fail, "effectiveness at 0", ix.wear.GetEffectiveness(0), 0)

	local expected = {[100] = 1, [90] = 1, [89] = 2, [65] = 2, [64] = 3, [40] = 3, [39] = 4, [20] = 4, [19] = 5, [0.01] = 5, [0] = 6}

	for condition, level in SortedPairs(expected) do
		local index, phrase = ix.wear.GetLevel(condition)

		Expect(fail, "level at " .. condition, index, level)
		if (!isstring(phrase) or !ix.lang.stored.english[phrase]) then fail("level " .. index .. " has no English phrase: " .. tostring(phrase)) end
	end

	Expect(fail, "LEVEL_RUINED", ix.wear.LEVEL_RUINED, 6)

	-- definitions and uniqueIDs; the uniforms opt in through outfitCategory "model"
	for _, uniqueID in ipairs({"work_boots", "winter_coat", "rain_poncho", "wool_gloves", "wool_cap", "resistance_uniform", "rmedic_uniform"}) do
		if (!ix.wear.IsWearable(uniqueID)) then fail(uniqueID .. " is not wearable") end
	end

	if (ix.wear.IsWearable("sewing_kit") or ix.wear.IsWearable("fabric")) then fail("a tool or material counts as wearable") end

	Expect(fail, "resistance_uniform part", ix.item.list.resistance_uniform.wearPart, "body")
	Expect(fail, "rmedic_uniform part", ix.item.list.rmedic_uniform.wearPart, "body")
	Expect(fail, "definition condition", ix.wear.GetCondition(ix.item.list.work_boots), 100)

	Scoped(function(defer)
		local _, inventory = Setup(defer)
		local item = GiveItem(inventory, "winter_coat")

		Expect(fail, "new condition", ix.wear.GetCondition(item), 100)
		ix.wear.SetCondition(item, 150)
		Expect(fail, "condition above 100 clamps", ix.wear.GetCondition(item), 100)
		ix.wear.SetCondition(item, -5)
		Expect(fail, "condition below 0 clamps", ix.wear.GetCondition(item), 0)
		item:SetData("conditionMax", 80)
		ix.wear.SetCondition(item, 95)
		Expect(fail, "condition clamps to the ceiling", ix.wear.GetCondition(item), 80)
		Expect(fail, "Repair at the ceiling restores", ix.wear.Repair(item, 10), 0)
	end)
end)

GWH.Check("wear: boots lose the configured share per kilometre, scaled by sprinting, ground and water", function(fail)
	local plugin = Plugin("wear", fail)
	if (!plugin) then return end

	local detail = {}

	Scoped(function(defer)
		local bot, inventory = Setup(defer)
		local boots = Wear(bot, inventory, "work_boots")

		if (ix.wear.GetWornPart(bot, "feet") != boots) then return fail("the boots are not the worn feet item") end

		WithConfig({wearEnabled = true, wearBootsDistance = 100}, function()
			-- 1 km of 100: 1 point
			Near(fail, "1 km plain", plugin:WearFeet(bot, KM), 1, 1e-4)
			Near(fail, "condition after 1 km", ix.wear.GetCondition(boots), 99, 1e-4)

			Expect(fail, "sprint multiplier", plugin:GetDistanceMultiplier({sprint = true}), 1.5)
			Expect(fail, "concrete multiplier", plugin:GetDistanceMultiplier({material = MAT_CONCRETE}), 1.25)
			Expect(fail, "grass multiplier", plugin:GetDistanceMultiplier({material = MAT_GRASS}), 0.8)
			Expect(fail, "wading multiplier", plugin:GetDistanceMultiplier({water = 1}), 1.5)
			Expect(fail, "dry multiplier", plugin:GetDistanceMultiplier({water = 0}), 1)

			-- sprinting through shallow water on concrete: 1.5 * 1.25 * 1.5
			ix.wear.SetCondition(boots, 100)
			Near(fail, "1 km sprinting, concrete, wading", plugin:WearFeet(bot, KM, {sprint = true, material = MAT_CONCRETE, water = 1}), 1.5 * 1.25 * 1.5, 1e-4)

			-- with a 5 km config, 5 km takes boots of durability 1 from new to ruined
			ix.config.Set("wearBootsDistance", 5)
			ix.wear.SetCondition(boots, 100)
			plugin:WearFeet(bot, 5 * KM)
			Near(fail, "5 km of a 5 km config", ix.wear.GetCondition(boots), 0, 1e-4)

			-- the feeder: samples only count ground distance and flush into WearFeet
			ix.config.Set("wearBootsDistance", 100)
			ix.wear.SetCondition(boots, 100)
			bot.ixWearLastPos, bot.ixWearDistance, bot.ixWearSamples = nil, 0, 0
			detail.circumstances = plugin:GetCircumstances(bot)
		end)
	end)

	return detail
end)

GWH.Check("wear: nothing wears in noclip or with wearEnabled off", function(fail)
	local plugin = Plugin("wear", fail)
	if (!plugin) then return end

	Scoped(function(defer)
		local bot, inventory = Setup(defer)
		local boots = Wear(bot, inventory, "work_boots")
		local coat = Wear(bot, inventory, "winter_coat")

		WithConfig({wearEnabled = true}, function()
			bot:SetMoveType(MOVETYPE_NOCLIP)
			Expect(fail, "walking in noclip", plugin:WearFeet(bot, KM), 0)
			Expect(fail, "time worn in noclip", plugin:WearFromTime(bot, 3600), 0)
			bot:SetMoveType(MOVETYPE_WALK)
		end)

		WithConfig({wearEnabled = false}, function()
			ix.wear.SetCondition(coat, 30)

			Expect(fail, "walking with wear off", plugin:WearFeet(bot, KM), 0)
			Expect(fail, "Damage with wear off", ix.wear.Damage(coat, 10, "damage", bot), 0)
			Expect(fail, "time with wear off", plugin:WearFromTime(bot, 3600), 0)
			local removed = 0

			for _, amount in pairs(plugin:WearFromDamage(bot, 20, DMG_BURN, HITGROUP_CHEST, 0)) do removed = removed + amount end

			Expect(fail, "damage taken with wear off", removed, 0)
			Expect(fail, "boots untouched", ix.wear.GetCondition(boots), 100)
			Expect(fail, "coat untouched", ix.wear.GetCondition(coat), 30)
			-- condition already lost still counts
			Near(fail, "effectiveness with wear off", ix.wear.GetEffectiveness(coat), 0.75)
		end)

		WithConfig({wearEnabled = true, wearPerHour = 1}, function()
			ix.wear.SetCondition(coat, 100)
			plugin:WearFromTime(bot, 3600)
			-- durability 1.5
			Near(fail, "an hour worn, coat", ix.wear.GetCondition(coat), 100 - 1 / 1.5, 1e-4)
			Near(fail, "an hour worn, boots", ix.wear.GetCondition(boots), 99, 1e-4)
		end)
	end)
end)

GWH.Check("wear: damage wears the garment that covers the hit, by damage type", function(fail)
	local plugin = Plugin("wear", fail)
	if (!plugin) then return end

	local detail = {}

	Scoped(function(defer)
		local bot, inventory = Setup(defer)
		local boots = Wear(bot, inventory, "work_boots")
		local coat = Wear(bot, inventory, "winter_coat")
		local cap = Wear(bot, inventory, "wool_cap")
		local gloves = Wear(bot, inventory, "wool_gloves")
		local uniform = WearOutfit(inventory, "rmedic_uniform")
		local all = {boots = boots, coat = coat, cap = cap, gloves = gloves, uniform = uniform}

		local function Reset()
			for _, item in pairs(all) do ix.wear.SetCondition(item, 100) end
		end

		local function Lost()
			local result = {}

			for name, item in pairs(all) do result[name] = 100 - ix.wear.GetCondition(item) end

			return result
		end

		WithConfig({wearEnabled = true, wearDamageScale = 1}, function()
			-- a bullet to the head: only the cap, 10 * 0.3
			Reset()
			plugin:WearFromDamage(bot, 10, DMG_BULLET, HITGROUP_HEAD, 0)
			local lost = Lost()
			detail.headshot = lost
			Near(fail, "headshot cap", lost.cap, 3)

			for _, name in ipairs({"boots", "coat", "gloves", "uniform"}) do
				if (lost[name] != 0) then fail("a headshot wore the " .. name) end
			end

			-- fire to the chest: the coat (durability 1.5) and half of it to the uniform under it (1.25)
			Reset()
			plugin:WearFromDamage(bot, 10, DMG_BURN, HITGROUP_CHEST, 0)
			lost = Lost()
			detail.burn = lost
			Near(fail, "burn coat", lost.coat, 10 / 1.5, 1e-4)
			Near(fail, "burn uniform", lost.uniform, 5 / 1.25, 1e-4)
			if (lost.cap != 0 or lost.boots != 0) then fail("a chest burn wore the cap or boots") end

			-- burns wear far more than bullets, slashes more than blunt hits, drowning nothing
			local burn = lost.coat

			Reset()
			plugin:WearFromDamage(bot, 10, DMG_BULLET, HITGROUP_CHEST, 0)
			local bullet = Lost().coat
			Reset()
			plugin:WearFromDamage(bot, 10, DMG_SLASH, HITGROUP_CHEST, 0)
			local slash = Lost().coat
			Reset()
			plugin:WearFromDamage(bot, 10, DMG_CLUB, HITGROUP_CHEST, 0)
			local club = Lost().coat
			Reset()
			plugin:WearFromDamage(bot, 10, DMG_ACID, HITGROUP_CHEST, 0)
			local acid = Lost().coat
			Reset()
			plugin:WearFromDamage(bot, 50, DMG_DROWN, HITGROUP_GENERIC, 0)
			local drown = Lost()
			detail.coat = {burn = burn, acid = acid, bullet = bullet, slash = slash, club = club}

			if (!(burn > bullet * 2 and acid > bullet * 2)) then fail("burns and acid do not wear much more than bullets") end
			if (!(slash > club)) then fail("a slash does not wear more than a blunt hit") end

			for name, value in pairs(drown) do
				if (value != 0) then fail("drowning wore the " .. name) end
			end

			-- a fall: the boots, and half to the body
			Reset()
			plugin:WearFromDamage(bot, 20, DMG_FALL, HITGROUP_GENERIC, 0)
			lost = Lost()
			detail.fall = lost
			Near(fail, "fall boots", lost.boots, 20 * 0.25, 1e-4)
			Near(fail, "fall uniform", lost.uniform, 20 * 0.25 * 0.5 / 1.25, 1e-4)
			if (lost.coat != 0 or lost.cap != 0) then fail("a fall wore the coat or cap") end

			-- an arm hit also wears the gloves (durability 0.8)
			Reset()
			plugin:WearFromDamage(bot, 10, DMG_BULLET, HITGROUP_LEFTARM, 0)
			Near(fail, "arm hit gloves", Lost().gloves, 1.5 / 0.8, 1e-4)

			-- without the coat, the uniform takes all of a body hit
			coat:SetData("equip", false)
			Reset()
			plugin:WearFromDamage(bot, 10, DMG_BURN, HITGROUP_CHEST, 0)
			Near(fail, "burn uniform without coat", Lost().uniform, 10 / 1.25, 1e-4)
			coat:SetData("equip", true)

			-- a real hit goes through PostEntityTakeDamage
			Reset()
			bot:SetHealth(100)
			local info = DamageInfo()
			info:SetDamage(5)
			info:SetDamageType(DMG_BURN)
			info:SetAttacker(game.GetWorld())
			info:SetInflictor(game.GetWorld())
			info:SetDamagePosition(bot:GetPos())
			bot:TakeDamageInfo(info)
			lost = Lost()
			detail.real = lost
			if (lost.coat <= 0) then fail("a real burn did not wear the coat") end
		end)
	end)

	return detail
end)

GWH.Check("wear: armour capacity follows condition and Repair works without stored armour", function(fail)
	local plugin = Plugin("wear", fail)
	if (!plugin) then return end

	Scoped(function(defer)
		local bot, inventory = Setup(defer)
		local item = GiveItem(inventory, "resistance_uniform")
		local maxArmor = item.maxArmor

		Expect(fail, "capacity when new", item:GetArmorCapacity(), maxArmor)

		local ok, restored = pcall(item.Repair, item, 10)

		if (!ok) then fail("Repair without armor data errored: " .. tostring(restored)) end
		Expect(fail, "Repair of a full, never-worn item restores", restored, 0)

		item:SetData("armor", 20)
		Expect(fail, "Repair 10 from 20", item:Repair(10), 10)
		Expect(fail, "stored armour after Repair", item:GetData("armor"), 30)

		ix.wear.SetCondition(item, 30)
		Expect(fail, "capacity at condition 30", item:GetArmorCapacity(), math.floor(maxArmor * 0.75))
		item:Repair(100)
		Expect(fail, "Repair is clamped to the capacity", item:GetArmor(), math.floor(maxArmor * 0.75))

		ix.wear.SetCondition(item, 0)
		Expect(fail, "a ruined item holds no armour", item:GetData("armor"), 0)

		-- worn: the wearer's armour is clamped as the condition drops, and absorbed hits wear it
		ix.wear.SetCondition(item, 100)
		item:SetData("equip", true)
		bot:SetArmor(maxArmor)
		ix.wear.SetCondition(item, 30)
		Expect(fail, "worn armour after the condition drops", bot:Armor(), math.floor(maxArmor * 0.75))

		WithConfig({wearEnabled = true, wearDamageScale = 1}, function()
			ix.wear.SetCondition(item, 100)
			plugin:WearFromDamage(bot, 10, DMG_BULLET, HITGROUP_CHEST, 8)
			-- 10 * 0.3 for the hit and 8 * 0.25 for what the plates absorbed, durability 1.25
			Near(fail, "an absorbed hit", 100 - ix.wear.GetCondition(item), (3 + 2) / 1.25, 1e-4)
		end)

		item:SetData("equip", false)
		bot:SetArmor(0)
	end)
end)

GWH.Check("wear: modifiers scale wear in a chain and re-registering an id replaces it", function(fail)
	Scoped(function(defer)
		local _, inventory = Setup(defer)
		local boots = GiveItem(inventory, "work_boots")
		local before = #ix.wear.modifierOrder
		local causes = {}

		defer(function()
			ix.wear.AddModifier("gwh_double", nil)
			ix.wear.AddModifier("gwh_cause", nil)
		end)

		WithConfig({wearEnabled = true}, function()
			ix.wear.AddModifier("gwh_double", function(client, item, cause, amount) return amount * 2 end)
			Near(fail, "doubled", ix.wear.Damage(boots, 5, "walk"), 10)

			ix.wear.AddModifier("gwh_double", function(client, item, cause, amount) return amount * 3 end)
			Expect(fail, "modifiers after re-registering", #ix.wear.modifierOrder, before + 1)
			ix.wear.SetCondition(boots, 100)
			Near(fail, "re-registered replaces", ix.wear.Damage(boots, 5, "walk"), 15)

			-- a second modifier composes with the first, and sees the cause
			ix.wear.AddModifier("gwh_cause", function(client, item, cause, amount)
				causes[#causes + 1] = cause

				if (cause == "soaked") then return amount * 2 end
			end)
			ix.wear.SetCondition(boots, 100)
			Near(fail, "two modifiers", ix.wear.Damage(boots, 5, "soaked"), 30)
			ix.wear.SetCondition(boots, 100)
			Near(fail, "a modifier returning nil", ix.wear.Damage(boots, 5, "walk"), 15)
			Expect(fail, "causes seen", table.concat(causes, ","), "soaked,walk")

			ix.wear.AddModifier("gwh_double", nil)
			ix.wear.AddModifier("gwh_cause", nil)
			Expect(fail, "modifiers after removing", #ix.wear.modifierOrder, before)
			ix.wear.SetCondition(boots, 100)
			Near(fail, "after removing", ix.wear.Damage(boots, 5, "walk"), 5)
		end)
	end)
end)

GWH.Check("wear: one item per slot, equip and unequip, no transfer or drop while worn", function(fail)
	Scoped(function(defer)
		local bot, inventory = Setup(defer)
		local first = GiveItem(inventory, "work_boots")
		local second = GiveItem(inventory, "work_boots")
		local cap = GiveItem(inventory, "wool_cap")

		for _, item in ipairs({first, second, cap}) do item.player = bot end

		defer(function()
			for _, item in ipairs({first, second, cap}) do item.player = nil end
		end)

		if (!first.functions.Equip.OnCanRun(first)) then fail("boots cannot be equipped") end
		first.functions.Equip.OnRun(first)
		if (!first:GetData("equip")) then fail("Equip did not equip the boots") end

		local notices = S.Notices(bot, function() second.functions.Equip.OnRun(second) end)

		if (second:GetData("equip")) then fail("a second pair of boots was equipped") end
		if (#notices == 0) then fail("no notice for the occupied slot") end

		cap.functions.Equip.OnRun(cap)
		if (!cap:GetData("equip")) then fail("the cap could not be worn with the boots") end
		Expect(fail, "worn items", #ix.wear.GetWorn(bot), 2)

		-- a 2x2 coat is listed once
		local coat = GiveItem(inventory, "winter_coat")
		coat:SetData("equip", true)
		Expect(fail, "worn items with a coat", #ix.wear.GetWorn(bot), 3)
		coat:SetData("equip", false)
		Expect(fail, "worn head", ix.wear.GetWornPart(bot, "head"), cap)
		Expect(fail, "worn hands", ix.wear.GetWornPart(bot, "hands"), nil)

		if (first:CanTransfer(inventory, nil) != false) then fail("worn boots can be dropped") end
		if (first:CanTransfer(inventory, inventory) != false) then fail("worn boots can be moved") end
		if (first.functions.EquipUn.OnCanRun(first) != true) then fail("worn boots cannot be unequipped") end

		-- Helix's equip hooks are honoured
		hook.Add("CanPlayerUnequipItem", "gwh_wear", function(client, item) if (item == first) then return false end end)
		hook.Add("CanPlayerEquipItem", "gwh_wear", function(client, item) if (item == second) then return false end end)
		defer(function()
			hook.Remove("CanPlayerUnequipItem", "gwh_wear")
			hook.Remove("CanPlayerEquipItem", "gwh_wear")
		end)

		if (first.functions.EquipUn.OnCanRun(first)) then fail("CanPlayerUnequipItem returning false did not stop unequipping") end
		if (second.functions.Equip.OnCanRun(second)) then fail("CanPlayerEquipItem returning false did not stop equipping") end

		hook.Remove("CanPlayerUnequipItem", "gwh_wear")
		first.functions.EquipUn.OnRun(first)

		if (first:GetData("equip")) then fail("Unequip did not unequip") end
		if (first:CanTransfer(inventory, nil) == false) then fail("unequipped boots cannot be dropped") end

		-- bodygroups on the extended citizen model: set while worn, put back from the character's data
		local character = bot:GetCharacter()
		local model = character:GetModel()
		local groups = character:GetData("groups")

		defer(function()
			character:SetModel(model)
			character:SetData("groups", groups)
		end)

		cap.functions.EquipUn.OnRun(cap)
		character:SetModel("models/player/zelpa/male_03_extended.mdl")

		local index = bot:FindBodygroupByName("beanies")

		if (index > -1) then
			bot:SetBodygroup(index, 1)
			character:SetData("groups", {[index] = 1})
			cap.functions.Equip.OnRun(cap)
			Expect(fail, "beanie bodygroup while worn", bot:GetBodygroup(index), 2)
			cap.functions.EquipUn.OnRun(cap)
			Expect(fail, "beanie bodygroup after", bot:GetBodygroup(index), 1)
			Expect(fail, "saved groups untouched", (character:GetData("groups") or {})[index], 1)
		end
	end)
end)

GWH.Check("wear: mending takes exactly its material, needs the tool and lowers the ceiling", function(fail)
	local detail = {}

	Scoped(function(defer)
		local bot, inventory = Setup(defer)
		local character = bot:GetCharacter()
		local coat = GiveItem(inventory, "winter_coat")

		defer(function()
			timer.Remove("ixAct" .. bot:SteamID64())
			bot.ixWearRepairUntil = nil
		end)

		ix.wear.SetCondition(coat, 40)

		local ok, reason = ix.wear.CanRepair(bot, coat, "mend")
		Expect(fail, "without the sewing kit", reason, "wearNeedTool")

		local kit = GiveItem(inventory, "sewing_kit")
		ok, reason = ix.wear.CanRepair(bot, coat, "mend")
		Expect(fail, "without fabric", reason, "wearNeedMaterial")

		NewStack(inventory, "fabric", 1.2)
		ok = ix.wear.CanRepair(bot, coat, "mend")
		if (!ok) then fail("cannot mend with fabric and the kit") end
		if (!coat.functions.wearMend) then fail("the coat has no Mend action") end

		-- the action starts a timed repair; completing it takes 0.5 fabric and keeps the kit
		if (!ix.wear.StartRepair(bot, coat, "mend")) then fail("StartRepair refused") end
		if (ix.wear.StartRepair(bot, coat, "mend")) then fail("a second repair started during the first") end

		local bDone = ix.wear.FinishRepair(bot, coat:GetID(), "mend", character:GetID())

		if (!bDone) then fail("FinishRepair did not repair") end
		Near(fail, "fabric after one mend", ix.stack.Count(inventory, "fabric"), 0.7, 1e-6)
		Expect(fail, "sewing kit kept", ix.stack.Count(inventory, "sewing_kit"), 1)
		Expect(fail, "condition after one mend", ix.wear.GetCondition(coat), 65)
		Expect(fail, "ceiling after one mend", ix.wear.GetCeiling(coat), 95)

		ix.wear.FinishRepair(bot, coat:GetID(), "mend", character:GetID())
		Near(fail, "fabric after two mends", ix.stack.Count(inventory, "fabric"), 0.2, 1e-6)
		Expect(fail, "condition after two mends", ix.wear.GetCondition(coat), 90)
		Expect(fail, "ceiling after two mends", ix.wear.GetCeiling(coat), 90)

		ok, reason = ix.wear.CanRepair(bot, coat, "mend")
		Expect(fail, "at the ceiling", reason, "wearNoRepairNeeded")
		coat.player = bot
		if (coat.functions.wearMend.OnCanRun(coat)) then fail("Mend is offered at the ceiling") end
		coat.player = nil

		-- not enough fabric left: refused, nothing taken
		ix.wear.SetCondition(coat, 10)
		if (ix.wear.FinishRepair(bot, coat:GetID(), "mend", character:GetID())) then fail("mended with 0.2 fabric") end
		Near(fail, "fabric after a refused mend", ix.stack.Count(inventory, "fabric"), 0.2, 1e-6)
		Expect(fail, "condition after a refused mend", ix.wear.GetCondition(coat), 10)

		-- material gone between start and finish
		local stack = NewStack(inventory, "fabric", 1)
		if (!ix.wear.StartRepair(bot, coat, "mend")) then fail("StartRepair refused with fabric") end
		ix.stack.Take(inventory, "fabric", 1.2)
		if (ix.wear.FinishRepair(bot, coat:GetID(), "mend", character:GetID())) then fail("mended after the fabric was gone") end
		Expect(fail, "condition after the fabric went", ix.wear.GetCondition(coat), 10)
		detail.stackLeft = IsValid(stack) and stack:GetData("quantity")

		-- the tool gone
		NewStack(inventory, "fabric", 1)
		kit:Remove()
		if (ix.wear.FinishRepair(bot, coat:GetID(), "mend", character:GetID())) then fail("mended without the sewing kit") end
		Near(fail, "fabric kept without the kit", ix.stack.Count(inventory, "fabric"), 1, 1e-6)
		GiveItem(inventory, "sewing_kit")

		-- the floor of the ceiling, and never below the condition the item had; a ruined item can be mended
		coat:SetData("conditionMax", 52)
		ix.wear.SetCondition(coat, 0)
		ix.wear.FinishRepair(bot, coat:GetID(), "mend", character:GetID())
		Expect(fail, "ceiling floor", ix.wear.GetCeiling(coat), 50)
		Expect(fail, "ruined item mended", ix.wear.GetCondition(coat), 25)

		-- the item gone before the action finished
		NewStack(inventory, "fabric", 1)
		local fabric = ix.stack.Count(inventory, "fabric")
		local id = coat:GetID()
		coat:Remove()
		if (ix.wear.FinishRepair(bot, id, "mend", character:GetID())) then fail("repaired an item that is gone") end
		Near(fail, "fabric kept when the item is gone", ix.stack.Count(inventory, "fabric"), fabric, 1e-6)

		-- another character's turn: the finished action belongs to the character that started it
		local boots = GiveItem(inventory, "work_boots")
		NewStack(inventory, "adhesive", 1)
		ix.wear.SetCondition(boots, 50)
		if (ix.wear.FinishRepair(bot, boots:GetID(), "mend", character:GetID() + 1)) then fail("finished a repair for another character") end
		ix.wear.FinishRepair(bot, boots:GetID(), "mend", character:GetID())
		Near(fail, "adhesive after mending boots", ix.stack.Count(inventory, "adhesive"), 0.8, 1e-6)
		Expect(fail, "boots after mending", ix.wear.GetCondition(boots), 75)

		-- armoured clothing: new plating from kevlar
		local uniform = GiveItem(inventory, "resistance_uniform")
		uniform:SetData("armor", 10)
		NewStack(inventory, "kevlar_roll", 1.5)
		if (!uniform.functions.wearPlate) then fail("the resistance uniform has no plating action") end
		if (!uniform.functions.wearMend) then fail("the resistance uniform has no Mend action") end
		ix.wear.FinishRepair(bot, uniform:GetID(), "plate", character:GetID())
		Expect(fail, "armour after plating", uniform:GetArmor(), 35)
		Near(fail, "kevlar after plating", ix.stack.Count(inventory, "kevlar_roll"), 0.5, 1e-6)
		Expect(fail, "condition untouched by plating", ix.wear.GetCondition(uniform), 100)
	end)

	return detail
end)

GWH.Check("wear: the level hook fires once per change across a boundary, and the wearer is told", function(fail)
	Scoped(function(defer)
		local bot, inventory = Setup(defer)
		local boots = Wear(bot, inventory, "work_boots")
		local calls = {}

		hook.Add("OnItemConditionLevelChanged", "gwh_wear", function(client, item, oldLevel, newLevel, cause)
			calls[#calls + 1] = {client = client, item = item, old = oldLevel, new = newLevel, cause = cause}
		end)
		defer(function() hook.Remove("OnItemConditionLevelChanged", "gwh_wear") end)

		WithConfig({wearEnabled = true}, function()
			ix.wear.Damage(boots, 5, "walk", bot)
			Expect(fail, "calls within pristine", #calls, 0)

			ix.wear.Damage(boots, 6, "walk", bot)
			Expect(fail, "calls after crossing into good", #calls, 1)

			if (calls[1]) then
				Expect(fail, "old level", calls[1].old, 1)
				Expect(fail, "new level", calls[1].new, 2)
				Expect(fail, "cause", calls[1].cause, "walk")
				Expect(fail, "client", calls[1].client, bot)
				Expect(fail, "item", calls[1].item, boots)
			end

			ix.wear.Damage(boots, 1, "walk", bot)
			Expect(fail, "calls within good", #calls, 1)

			-- 88 -> 38 skips worn: one call, good -> tattered, and the wearer is told
			local notices = S.Notices(bot, function() ix.wear.Damage(boots, 50, "damage", bot) end)
			Expect(fail, "calls after a big hit", #calls, 2)
			if (calls[2]) then
				Expect(fail, "big hit from", calls[2].old, 2)
				Expect(fail, "big hit to", calls[2].new, 4)
			end

			if (#notices != 1 or !string.find(notices[1] or "", "work boots are", 1, true)) then
				fail("notice for tattered boots: " .. table.concat(notices, " | "))
			end

			-- repairing back is a change too, cause "repair", and tells nothing
			notices = S.Notices(bot, function() ix.wear.Repair(boots, 60) end)
			Expect(fail, "calls after a repair", #calls, 3)
			if (calls[3]) then Expect(fail, "repair cause", calls[3].cause, "repair") end
			Expect(fail, "notices for a repair", #notices, 0)

			-- an item not worn is not told about
			boots.player = bot
			boots.functions.EquipUn.OnRun(boots)
			boots.player = nil
			notices = S.Notices(bot, function() ix.wear.Damage(boots, 70, "damage", bot) end)
			Expect(fail, "notices for an item not worn", #notices, 0)
		end)
	end)
end)

GWH.Check("wear: small wear stays in memory and is stored in steps", function(fail)
	Scoped(function(defer)
		local bot, inventory = Setup(defer)
		local boots = Wear(bot, inventory, "work_boots")
		local stored, quiet = 0, 0
		local SetData = boots.SetData

		-- on the instance, so only this item is watched
		boots.SetData = function(self, key, value, receivers, noSave, ...)
			if (key == "condition") then
				if (receivers == false and noSave) then
					quiet = quiet + 1
				else
					stored = stored + 1
				end
			end

			return SetData(self, key, value, receivers, noSave, ...)
		end
		defer(function() boots.SetData = nil end)

		WithConfig({wearEnabled = true}, function()
			-- ten steps of 0.04: 0.4 in all, under STORE_STEP and inside one level
			for _ = 1, 10 do
				ix.wear.Damage(boots, 0.04, "walk", bot)
			end

			Near(fail, "condition the server reads", ix.wear.GetCondition(boots), 99.6)
			Expect(fail, "stored writes under the step", stored, 0)
			Expect(fail, "memory-only writes under the step", quiet, 10)

			-- the step is reached: one stored write
			ix.wear.Damage(boots, 0.2, "walk", bot)
			Expect(fail, "stored writes at the step", stored, 1)

			-- a level boundary is stored at once however small the change (90 is the edge of like new)
			ix.wear.SetCondition(boots, 90.01)
			stored = 0
			ix.wear.Damage(boots, 0.02, "walk", bot)
			Expect(fail, "stored writes across a level boundary", stored, 1)
		end)
	end)
end)

GWH.Check("wear: the new items are registered, priced, not in business, and their recipes are real", function(fail)
	local craft = ix.plugin.list.ixcraft and ix.plugin.list.ixcraft.craft
	if (!craft) then return fail("ixcraft is not loaded") end

	local bot = GWH.Bot()
	local detail = {}

	for _, uniqueID in ipairs(NEW_ITEMS) do
		local item = ix.item.list[uniqueID]

		if (!item) then
			fail(uniqueID .. " is not registered")
			continue
		end

		if (!isnumber(item.price) or item.price <= 0) then fail(uniqueID .. " has no price") end
		if (bot and hook.Run("CanPlayerUseBusiness", bot, uniqueID) != false) then fail(uniqueID .. " is buyable through business") end

		if (ix.wear.IsWearable(item)) then
			if (item.base != "base_wearable") then fail(uniqueID .. " has base " .. tostring(item.base)) end
			if (!ix.item.list[item.repairMaterial]) then fail(uniqueID .. " repairs with unknown " .. tostring(item.repairMaterial)) end
			if (item.repairTool and !ix.item.list[item.repairTool]) then fail(uniqueID .. " needs unknown tool " .. tostring(item.repairTool)) end
		end

		local recipe = craft.recipes[uniqueID]

		if (!recipe) then
			fail(uniqueID .. " has no recipe")
			continue
		end

		for _, list in ipairs({recipe.requirements or {}, recipe.results or {}}) do
			for required in pairs(list) do
				if (!ix.item.list[required]) then fail(uniqueID .. "'s recipe names unknown item " .. required) end
			end
		end

		for _, tool in ipairs(recipe.tools or {}) do
			if (!ix.item.list[tool]) then fail(uniqueID .. "'s recipe names unknown tool " .. tool) end
		end

		if (!(recipe.results or {})[uniqueID]) then fail(uniqueID .. "'s recipe does not make it") end

		detail[uniqueID] = {price = item.price, part = item.wearPart, station = recipe.station}
	end

	return detail
end)
