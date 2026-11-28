-- Body map, persistent wounds and unified garments (body, wear, exposure, datapad): canonical
-- regions, hitgroup mapping, garment coverage, pockets and concealment, carry places, frisk order,
-- per-region persistent wounds, garment dry/wet weight, unified wear keeping pockets intact,
-- summer overheating thirst/stamina costs, smelter heat routes and non-lethal combat impairment.

local Lib = GWH.Lib
local Scoped, ResetBot, Fresh, GiveItem, Expect = Lib.Scoped, Lib.ResetBot, Lib.Fresh, Lib.GiveItem, Lib.Expect
local Replace, WithConfig, Plugin = Lib.Replace, Lib.WithConfig, Lib.Plugin
local S = Lib.NewS()

local function Near(fail, label, actual, expected, epsilon)
	if (!isnumber(actual) or math.abs(actual - expected) > (epsilon or 1e-4)) then
		fail(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function Clear(bot)
	if (ix.body and ix.body.ClearWounds) then
		ix.body.ClearWounds(bot)
	end

	for _, item in pairs(bot:GetCharacter():GetInventory():GetItems()) do
		if (item.data) then item.data.equip = nil end
	end

	Fresh(bot)
end

local function Setup(defer)
	local bot = GWH.Bot()
	if (!bot) then error("no bot") end

	ResetBot(bot)
	Clear(bot)

	defer(function()
		Clear(bot)
		ResetBot(bot)
	end)

	return bot, bot:GetCharacter():GetInventory()
end

local function FindPlace(groups, key)
	for _, place in ipairs(groups) do
		if (place.key == key) then
			return place
		end
	end
end

GWH.Check("body: hitgroups, DMG_FALL and frisk order use the canonical region set", function(fail)
	if (!ix.body) then return fail("ix.body is missing") end

	Expect(fail, "region count", #ix.body.REGIONS, 6)

	for _, region in ipairs(ix.body.REGIONS) do
		Expect(fail, "IsRegion " .. region, ix.body.IsRegion(region), true)
		if (!isstring(ix.body.REGION_LABELS[region])) then
			fail("missing label for region " .. region)
		end
	end

	Expect(fail, "rejects legacy hands", ix.body.IsRegion("hands"), false)
	Expect(fail, "rejects legacy back", ix.body.IsRegion("back"), false)
	Expect(fail, "rejects legacy left arm", ix.body.IsRegion("left arm"), false)

	local expectedHits = {
		{HITGROUP_HEAD, DMG_BULLET, "head"},
		{HITGROUP_CHEST, DMG_BULLET, "chest"},
		{HITGROUP_GENERIC, DMG_GENERIC, "chest"},
		{HITGROUP_STOMACH, DMG_BULLET, "waist"},
		{HITGROUP_LEFTARM, DMG_BULLET, "arms"},
		{HITGROUP_RIGHTARM, DMG_BULLET, "arms"},
		{HITGROUP_LEFTLEG, DMG_BULLET, "legs"},
		{HITGROUP_RIGHTLEG, DMG_BULLET, "legs"},
		{HITGROUP_GEAR, DMG_GENERIC, "chest"},
		{HITGROUP_GENERIC, DMG_FALL, "feet"},
		{HITGROUP_CHEST, DMG_FALL, "feet"}
	}

	for _, case in ipairs(expectedHits) do
		local region = ix.body.HitGroupToRegion(case[1], case[2])
		Expect(fail, "hitgroup " .. tostring(case[1]) .. " dmg " .. tostring(case[2]), region, case[3])
		Expect(fail, "mapped region is canonical", ix.body.IsRegion(region), true)
	end

	if (!ix.datapad or !istable(ix.datapad.searchOrder)) then
		return fail("ix.datapad.searchOrder is missing")
	end

	local seen = {}
	for _, region in ipairs(ix.datapad.searchOrder) do
		if (!ix.body.IsRegion(region)) then
			fail("searchOrder contains non-canonical region: " .. tostring(region))
		end
		seen[region] = true
	end

	for _, region in ipairs(ix.body.REGIONS) do
		if (!seen[region]) then
			fail("searchOrder does not cover canonical region: " .. region)
		end
	end

	Expect(fail, "searchOrder matches FRISK_ORDER length", #ix.datapad.searchOrder, #ix.body.REGIONS)

	-- A pocket definition without concealment is a plain pocket (hides nothing), not dropped.
	local plain = ix.body.GetItemPockets({name = "Test garment", pockets = {{region = "chest", capacity = 2}}})
	Expect(fail, "pocket without concealment is kept", #plain, 1)
	Expect(fail, "pocket without concealment defaults to 0", plain[1] and plain[1].concealment, 0)
end)

GWH.Check("body: garment coverage matches hit regions in outer-to-body order", function(fail)
	if (!ix.body or !ix.wear) then return fail("ix.body or ix.wear is missing") end

	Scoped(function(defer)
		local bot, inv = Setup(defer)
		local cap = GiveItem(inv, "wool_cap")
		local coat = GiveItem(inv, "winter_coat")
		local gloves = GiveItem(inv, "wool_gloves")
		local boots = GiveItem(inv, "work_boots")
		local uniform = GiveItem(inv, "rmedic_uniform")

		for _, item in ipairs({cap, coat, gloves, boots, uniform}) do
			item:SetData("equip", true)
		end

		local function IDs(region)
			local ids = {}
			for _, item in ipairs(ix.body.GetCoveringGarments(bot, region)) do
				ids[#ids + 1] = item.uniqueID
			end
			return table.concat(ids, ",")
		end

		Expect(fail, "head coverage", IDs(ix.body.HitGroupToRegion(HITGROUP_HEAD, DMG_BULLET)), "wool_cap")
		Expect(fail, "chest coverage", IDs(ix.body.HitGroupToRegion(HITGROUP_CHEST, DMG_BULLET)), "winter_coat,rmedic_uniform")
		Expect(fail, "waist coverage", IDs(ix.body.HitGroupToRegion(HITGROUP_STOMACH, DMG_BULLET)), "winter_coat,rmedic_uniform")
		Expect(fail, "arms coverage", IDs(ix.body.HitGroupToRegion(HITGROUP_LEFTARM, DMG_BULLET)), "winter_coat,rmedic_uniform,wool_gloves")
		Expect(fail, "legs coverage", IDs(ix.body.HitGroupToRegion(HITGROUP_RIGHTLEG, DMG_BULLET)), "rmedic_uniform")
		Expect(fail, "feet coverage", IDs(ix.body.HitGroupToRegion(HITGROUP_GENERIC, DMG_FALL)), "work_boots")
		Expect(fail, "gloves arms share", ix.body.GetRegionWearShare(gloves, "arms"), 0.5)
	end)
end)

GWH.Check("body: carry layout regions, garment pockets, concealment and lossless unequip", function(fail)
	if (!ix.body or !ix.datapad) then return fail("ix.body or ix.datapad is missing") end

	Scoped(function(defer)
		local bot, inv = Setup(defer)
		local char = bot:GetCharacter()
		local prefs = table.Copy(char:GetData("carryPrefs", {}))
		defer(function()
			char:SetData("carryPrefs", prefs)
		end)

		local function CheckLayoutValid(label, groups)
			for _, place in ipairs(groups) do
				if (!ix.body.IsRegion(place.region)) then
					fail(label .. ": place " .. tostring(place.key) .. " has non-canonical region " .. tostring(place.region))
				end
				if (!isnumber(place.concealment) or place.concealment < 0 or place.concealment > 1) then
					fail(label .. ": place " .. tostring(place.key) .. " has invalid concealment " .. tostring(place.concealment))
				end
			end
		end

		-- Base layout with no garments worn
		local bare = ix.datapad.Layout(inv)
		CheckLayoutValid("bare", bare)
		local baseBoot = FindPlace(bare, "boot")
		if (!baseBoot) then return fail("base boot place missing") end
		Expect(fail, "base boot region", baseBoot.region, "feet")
		Expect(fail, "base boot capacity", baseBoot.limit, 1)
		Expect(fail, "base boot concealment", baseBoot.concealment, 0.85)
		Expect(fail, "hands region", FindPlace(bare, "hands").region, "arms")

		-- Work boots override the boot key with 0.9 concealment
		local boots = GiveItem(inv, "work_boots")
		boots:SetData("equip", true)
		local withBoots = ix.datapad.Layout(inv)
		CheckLayoutValid("with boots", withBoots)
		local bootCount = 0
		for _, place in ipairs(withBoots) do
			if (place.key == "boot") then bootCount = bootCount + 1 end
		end
		Expect(fail, "single boot entry when wearing work_boots", bootCount, 1)
		local workBoot = FindPlace(withBoots, "boot")
		Expect(fail, "work_boots boot concealment", workBoot.concealment, 0.9)
		Expect(fail, "work_boots boot capacity", workBoot.limit, 1)
		Expect(fail, "work_boots boot sourceItem", workBoot.sourceItem, boots)

		-- Winter coat adds 4-cap outer + 1-cap hidden inner lining
		local coat = GiveItem(inv, "winter_coat")
		coat:SetData("equip", true)
		local withCoat = ix.datapad.Layout(inv)
		CheckLayoutValid("with coat", withCoat)
		local outerKey = "pkt_" .. coat.id .. "_outer"
		local liningKey = "pkt_" .. coat.id .. "_lining"
		local outer = FindPlace(withCoat, outerKey)
		local lining = FindPlace(withCoat, liningKey)
		if (!outer or !lining) then return fail("winter_coat pockets missing from layout") end
		Expect(fail, "winter_coat outer capacity", outer.limit, 4)
		Expect(fail, "winter_coat outer concealment", outer.concealment, 0.25)
		Expect(fail, "winter_coat outer region", outer.region, "chest")
		Expect(fail, "winter_coat lining capacity", lining.limit, 1)
		Expect(fail, "winter_coat lining concealment", lining.concealment, 0.75)
		Expect(fail, "winter_coat lining region", lining.region, "chest")

		-- Move items into winter_coat lining, verify limit, then unequip coat losslessly
		local bandage = GiveItem(inv, "bandage")
		local vial = GiveItem(inv, "health_vial")
		Expect(fail, "move bandage into coat lining", ix.datapad.Move(bot, bandage.id, liningKey), true)
		Expect(fail, "full lining refuses second item", ix.datapad.Move(bot, vial.id, liningKey), false)

		coat:SetData("equip", false)
		local afterUnequip = ix.datapad.Layout(inv)
		CheckLayoutValid("after coat unequip", afterUnequip)
		Expect(fail, "coat outer removed on unequip", FindPlace(afterUnequip, outerKey), nil)
		Expect(fail, "coat lining removed on unequip", FindPlace(afterUnequip, liningKey), nil)
		local fallbackPlace = ix.datapad.Locate(afterUnequip, bandage.id)
		if (!fallbackPlace) then
			fail("bandage lost after unequipping winter_coat")
		else
			Expect(fail, "fallback place has canonical region", ix.body.IsRegion(fallbackPlace.region), true)
		end

		-- Rain poncho adds 1-cap pouch
		local poncho = GiveItem(inv, "rain_poncho")
		poncho:SetData("equip", true)
		local withPoncho = ix.datapad.Layout(inv)
		CheckLayoutValid("with poncho", withPoncho)
		local pouch = FindPlace(withPoncho, "pkt_" .. poncho.id .. "_pouch")
		if (!pouch) then return fail("rain_poncho pouch missing") end
		Expect(fail, "rain_poncho pouch capacity", pouch.limit, 1)
		Expect(fail, "rain_poncho pouch concealment", pouch.concealment, 0.15)
		poncho:SetData("equip", false)

		-- Uniform pockets come from each uniform definition
		local medic = GiveItem(inv, "rmedic_uniform")
		medic:SetData("equip", true)
		local withMedic = ix.datapad.Layout(inv)
		CheckLayoutValid("with medic uniform", withMedic)
		local medicPkt = FindPlace(withMedic, "pkt_" .. medic.id .. "_chest")
		if (!medicPkt) then return fail("rmedic_uniform pocket missing") end
		Expect(fail, "rmedic_uniform pocket capacity", medicPkt.limit, 4)
		Expect(fail, "rmedic_uniform pocket concealment", medicPkt.concealment, 0.25)
		medic:SetData("equip", false)

		local resist = GiveItem(inv, "resistance_uniform")
		resist:SetData("equip", true)
		local withResist = ix.datapad.Layout(inv)
		CheckLayoutValid("with resistance uniform", withResist)
		local resistPkt = FindPlace(withResist, "pkt_" .. resist.id .. "_chest")
		if (!resistPkt) then return fail("resistance_uniform pocket missing") end
		Expect(fail, "resistance_uniform pocket capacity", resistPkt.limit, 3)
		Expect(fail, "resistance_uniform pocket concealment", resistPkt.concealment, 0.3)
		resist:SetData("equip", false)

		-- Cap and gloves define empty pockets and canonical worn regions
		local cap = GiveItem(inv, "wool_cap")
		local gloves = GiveItem(inv, "wool_gloves")
		cap:SetData("equip", true)
		gloves:SetData("equip", true)
		local withAccessories = ix.datapad.Layout(inv)
		CheckLayoutValid("with cap and gloves", withAccessories)
		local capPlace = ix.datapad.Locate(withAccessories, cap.id)
		local glovesPlace = ix.datapad.Locate(withAccessories, gloves.id)
		Expect(fail, "wool_cap worn region", capPlace and capPlace.region, "head")
		Expect(fail, "wool_gloves worn region", glovesPlace and glovesPlace.region, "arms")

		-- Bags use canonical carryRegion and concealment, never legacy "back"
		local suitcase = GiveItem(inv, "suitcase")
		local bagInv = suitcase:GetInventory()
		if (bagInv) then
			local withBag = ix.datapad.Layout(inv)
			CheckLayoutValid("with suitcase", withBag)
			local bagPlace = FindPlace(withBag, "bag" .. suitcase.id)
			if (!bagPlace) then
				fail("suitcase group missing from layout")
			else
				Expect(fail, "suitcase region", bagPlace.region, "arms")
				Expect(fail, "suitcase concealment", bagPlace.concealment, 0.5)
			end
		end
	end)
end)

GWH.Check("body: regional cut and gunshot wounds coexist, persist at full health and wear covering garments", function(fail)
	local bodyPlugin = Plugin("body", fail)
	if (!bodyPlugin or !ix.body or !ix.wear) then return fail("body or wear missing") end

	Scoped(function(defer)
		local bot, inv = Setup(defer)
		local coat = GiveItem(inv, "winter_coat")
		local uniform = GiveItem(inv, "resistance_uniform")
		local gloves = GiveItem(inv, "wool_gloves")

		for _, item in ipairs({coat, uniform, gloves}) do
			item:SetData("equip", true)
			ix.wear.SetCondition(item, 100)
		end

		local woundedEvents = {}
		local hookID = "gwhBodyWoundCheck"
		hook.Add("OnCharacterWounded", hookID, function(client, wound)
			if (client == bot) then
				woundedEvents[#woundedEvents + 1] = {region = wound.region, kind = wound.kind, severity = wound.severity}
			end
		end)
		defer(function() hook.Remove("OnCharacterWounded", hookID) end)

		local fakeHitGroup = HITGROUP_GENERIC
		local playerMeta = FindMetaTable("Player")
		Replace(defer, playerMeta, "LastHitGroup", function(self)
			if (self == bot) then return fakeHitGroup end
			return HITGROUP_GENERIC
		end)

		local function DeliverHit(hitGroup, dmgType, amount)
			fakeHitGroup = hitGroup
			local dmg = DamageInfo()
			dmg:SetDamage(amount)
			dmg:SetDamageType(dmgType)
			hook.Run("EntityTakeDamage", bot, dmg)
			hook.Run("PostEntityTakeDamage", bot, dmg, true)
		end

		WithConfig({bodyWoundsEnabled = true, wearEnabled = true, wearDamageScale = 1}, function()
			-- Gunshot to left leg -> legs wound + damages resistance_uniform (covers legs), not coat/gloves
			DeliverHit(HITGROUP_LEFTLEG, DMG_BULLET, 25)
			local legWound = ix.body.GetWound(bot, "legs")
			if (!legWound) then return fail("leg gunshot wound was not created") end
			Expect(fail, "leg wound kind", legWound.kind, "gunshot")
			Expect(fail, "leg wound state", legWound.state, "open")
			Expect(fail, "leg wound severity", legWound.severity, 55)

			local uniformAfterLeg = ix.wear.GetCondition(uniform)
			if (!(uniformAfterLeg < 100)) then fail("leg gunshot did not wear resistance_uniform") end
			Expect(fail, "leg gunshot left coat untouched", ix.wear.GetCondition(coat), 100)
			Expect(fail, "leg gunshot left gloves untouched", ix.wear.GetCondition(gloves), 100)

			-- Cut to right arm -> arms wound coexists with legs wound + wears coat, uniform, gloves
			DeliverHit(HITGROUP_RIGHTARM, DMG_SLASH, 20)
			local armWound = ix.body.GetWound(bot, "arms")
			if (!armWound) then return fail("arm cut wound was not created") end
			Expect(fail, "arm wound kind", armWound.kind, "cut")
			Expect(fail, "arm wound state", armWound.state, "open")
			Expect(fail, "arm wound severity", armWound.severity, 44)

			-- Leg wound is still intact alongside arm wound
			local legStill = ix.body.GetWound(bot, "legs")
			if (!legStill or legStill.kind != "gunshot") then fail("arm cut overwrote leg gunshot wound") end

			if (!(ix.wear.GetCondition(coat) < 100)) then fail("arm cut did not wear winter_coat") end
			if (!(ix.wear.GetCondition(uniform) < uniformAfterLeg)) then fail("arm cut did not wear resistance_uniform") end
			if (!(ix.wear.GetCondition(gloves) < 100)) then fail("arm cut did not wear wool_gloves") end

			Expect(fail, "OnCharacterWounded fired twice", #woundedEvents, 2)

			-- Restoring full health does NOT clear persistent wounds
			bot:SetHealth(bot:GetMaxHealth())
			if (!ix.body.GetWound(bot, "legs") or !ix.body.GetWound(bot, "arms")) then
				fail("wounds cleared when health reached 100")
			end
		end)
	end)
end)

GWH.Check("body: arm aim shake, leg slowdown, SetupMove and bandage treatment with visible healing", function(fail)
	local bodyPlugin = Plugin("body", fail)
	if (!bodyPlugin or !ix.body) then return fail("body plugin missing") end

	Scoped(function(defer)
		local bot, inv = Setup(defer)
		local char = bot:GetCharacter()

		local treatedCount, healedEvents = 0, {}
		local hookID = "gwhBodyTreatCheck"
		hook.Add("OnWoundTreated", hookID, function(client)
			if (client == bot) then treatedCount = treatedCount + 1 end
		end)
		hook.Add("OnWoundHealed", hookID, function(client, region, kind)
			if (client == bot) then healedEvents[#healedEvents + 1] = {region = region, kind = kind} end
		end)
		defer(function()
			hook.Remove("OnWoundTreated", hookID)
			hook.Remove("OnWoundHealed", hookID)
			if (IsValid(bot)) then
				timer.Remove("ixAct" .. bot:SteamID64())
				bot.ixBodyTreating = nil
			end
		end)

		local function MakeMoveData(base)
			local speeds = {client = base, max = base}
			return speeds, {
				GetMaxClientSpeed = function() return speeds.client end,
				SetMaxClientSpeed = function(_, v) speeds.client = v end,
				GetMaxSpeed = function() return speeds.max end,
				SetMaxSpeed = function(_, v) speeds.max = v end
			}
		end

		WithConfig({bodyWoundsEnabled = true, bodyWoundHealTime = 100}, function()
			Expect(fail, "uninjured arm shake", ix.body.GetArmShake(bot), 0)
			Expect(fail, "uninjured leg scale", ix.body.GetLegSpeedScale(bot), 1)

			-- Inflict severe leg gunshot (80) and severe arm cut (80)
			ix.body.AddWound(bot, "legs", "gunshot", 80)
			ix.body.AddWound(bot, "arms", "cut", 80)

			local openShake = ix.body.GetArmShake(bot)
			local openScale = ix.body.GetLegSpeedScale(bot)
			if (!(openShake > 0.5)) then fail("arm wound did not raise GetArmShake: " .. tostring(openShake)) end
			if (!(openScale < 0.8)) then fail("leg wound did not lower GetLegSpeedScale: " .. tostring(openScale)) end

			-- SetupMove scales speed and returns nil
			local speeds, mv = MakeMoveData(200)
			if (bodyPlugin:SetupMove(bot, mv) != nil) then fail("SetupMove returned a non-nil value") end
			if (!(speeds.client < 200 and math.abs(speeds.client - 200 * openScale) < 0.01)) then
				fail("SetupMove did not scale MaxClientSpeed to " .. tostring(200 * openScale) .. ", got " .. tostring(speeds.client))
			end
			if (!(speeds.max < 200 and math.abs(speeds.max - 200 * openScale) < 0.01)) then
				fail("SetupMove did not scale MaxSpeed")
			end

			-- Apply bandage starts timed treatment and defers consumption (returns false)
			local bandage1 = GiveItem(inv, "bandage")
			local bandage2 = GiveItem(inv, "bandage")
			bot:SetHealth(60)
			bandage1.player = bot
			local applyResult = bandage1.functions.Apply.OnRun(bandage1, {region = "legs"})
			bandage1.player = nil
			Expect(fail, "bandage Apply returns false while starting timed bind", applyResult, false)
			if (!bot.ixBodyTreating) then fail("bandage Apply did not start ixBodyTreating") end
			if (!inv:GetItemByID(bandage1.id, false)) then fail("bandage consumed before timed action finished") end

			-- Completing treatment consumes bandage1, restores health, dresses legs wound, halves leg penalty immediately
			timer.Remove("ixAct" .. bot:SteamID64())
			local treated = ix.body.FinishTreatWound(bot, bandage1, "legs", char:GetID())
			if (!treated or treated.state != "dressed") then fail("FinishTreatWound did not dress legs wound") end
			if (inv:GetItemByID(bandage1.id, false)) then fail("FinishTreatWound did not consume bandage") end
			Expect(fail, "bandage treatment restored +20 HP", bot:Health(), 80)
			Expect(fail, "OnWoundTreated fired once", treatedCount, 1)

			local dressedScale = ix.body.GetLegSpeedScale(bot)
			if (!(dressedScale > openScale and dressedScale < 1)) then
				fail("dressing leg wound did not immediately ease GetLegSpeedScale: open=" .. openScale .. " dressed=" .. dressedScale)
			end

			-- Treat arms wound too and check immediate shake halving
			local treatedArm = ix.body.FinishTreatWound(bot, bandage2, "arms", char:GetID())
			if (!treatedArm or treatedArm.state != "dressed") then fail("FinishTreatWound did not dress arms wound") end
			local dressedShake = ix.body.GetArmShake(bot)
			if (!(dressedShake > 0 and dressedShake < openShake)) then
				fail("dressing arm wound did not immediately ease GetArmShake: open=" .. openShake .. " dressed=" .. dressedShake)
			end
			if (math.abs(dressedShake - openShake * 0.5) > 0.001) then
				fail("dressed arm shake was not halved: expected " .. (openShake * 0.5) .. ", got " .. dressedShake)
			end

			-- Visible healing across bands via WoundTick (healTime = 100s => 1 severity/sec)
			Expect(fail, "initial severity word", ix.body.GetWoundSeverityWord(ix.body.GetWound(bot, "legs").severity), "severe")
			bodyPlugin:WoundTick(bot, char, 30) -- 80 -> 50 (moderate)
			Expect(fail, "severity word after 30s tick", ix.body.GetWoundSeverityWord(ix.body.GetWound(bot, "legs").severity), "moderate")
			bodyPlugin:WoundTick(bot, char, 30) -- 50 -> 20 (minor)
			Expect(fail, "severity word after 60s tick", ix.body.GetWoundSeverityWord(ix.body.GetWound(bot, "legs").severity), "minor")

			-- Re-hitting a dressed wound reopens it
			ix.body.AddWound(bot, "arms", "cut", 25)
			local reopened = ix.body.GetWound(bot, "arms")
			Expect(fail, "re-hit wound reopens", reopened and reopened.state, "open")
			Expect(fail, "re-hit wound increases severity", reopened and reopened.severity, 45)
			ix.body.TreatWound(bot, "arms")

			-- Finish healing both wounds completely
			bodyPlugin:WoundTick(bot, char, 60)
			Expect(fail, "legs wound cleared after full heal", ix.body.GetWound(bot, "legs"), nil)
			Expect(fail, "arms wound cleared after full heal", ix.body.GetWound(bot, "arms"), nil)
			Expect(fail, "arm shake zero after heal", ix.body.GetArmShake(bot), 0)
			Expect(fail, "leg scale 1 after heal", ix.body.GetLegSpeedScale(bot), 1)
			Expect(fail, "OnWoundHealed fired for both wounds", #healedEvents, 2)

			-- Bandage with NO open wounds preserves instant +20 HP behavior
			local bandage3 = GiveItem(inv, "bandage")
			bot:SetHealth(50)
			bandage3.player = bot
			local plainResult = bandage3.functions.Apply.OnRun(bandage3)
			bandage3.player = nil
			Expect(fail, "bandage with no open wounds does not return false", plainResult, nil)
			Expect(fail, "bandage with no open wounds restores +20 HP", bot:Health(), 70)
		end)
	end)
end)

GWH.Check("body: dressed wounds heal through fractional severity; bandages work from storage and the world", function(fail)
	local bodyPlugin = Plugin("body", fail)
	if (!bodyPlugin or !ix.body) then return fail("body plugin missing") end

	Scoped(function(defer)
		local bot, inv = Setup(defer)
		local char = bot:GetCharacter()

		defer(function()
			if (IsValid(bot)) then
				timer.Remove("ixAct" .. bot:SteamID64())
				bot.ixBodyTreating = nil
			end
		end)

		-- At an 1800s heal time a 5s tick heals ~0.28 severity: a severity-1 dressed wound must keep
		-- its fraction between ticks and finish healing instead of being clamped back to 1 forever.
		WithConfig({bodyWoundsEnabled = true, bodyWoundHealTime = 1800}, function()
			ix.body.AddWound(bot, "feet", "cut", 1)
			ix.body.TreatWound(bot, "feet")

			bodyPlugin:WoundTick(bot, char, 5)
			local ticking = ix.body.GetWound(bot, "feet")
			if (!ticking) then return fail("dressed severity-1 wound vanished after one small tick") end
			if (!(ticking.severity < 1)) then
				fail("fractional severity was clamped back to 1: " .. tostring(ticking.severity))
			end

			for _ = 1, 4 do bodyPlugin:WoundTick(bot, char, 5) end
			Expect(fail, "fractional dressed wound finishes healing", ix.body.GetWound(bot, "feet"), nil)
		end)

		-- A bandage lying in the world in reach can be applied: finishing the bind consumes it there.
		WithConfig({bodyWoundsEnabled = true, bodyWoundHealTime = 100}, function()
			local worldBandage = GiveItem(inv, "bandage")
			local worldID = worldBandage.id
			worldBandage:Transfer(0, nil, nil, bot)
			local ent = worldBandage:GetEntity()
			if (IsValid(ent)) then ent:SetPos(bot:GetPos() + Vector(30, 0, 10)) end

			defer(function()
				local leftover = ix.item.instances[worldID]
				if (leftover) then leftover:Remove() end
				if (IsValid(ent)) then ent:Remove() end
			end)

			ix.body.AddWound(bot, "legs", "cut", 40)
			worldBandage.player = bot
			local started = worldBandage.functions.Apply.OnRun(worldBandage, {region = "legs"})
			worldBandage.player = nil
			Expect(fail, "world bandage Apply starts the timed bind", started, false)
			if (!bot.ixBodyTreating) then fail("world bandage Apply did not start ixBodyTreating") end

			timer.Remove("ixAct" .. bot:SteamID64())
			local treated = ix.body.FinishTreatWound(bot, worldBandage, "legs", char:GetID())
			if (!treated or treated.state != "dressed") then fail("world bandage did not dress the wound") end
			Expect(fail, "world bandage consumed", ix.item.instances[worldID], nil)
			-- Entity removal lands next tick; the safe flag is what the consume sets now.
			Expect(fail, "world bandage entity marked safe for removal", IsValid(ent) and ent.ixIsSafe, true)
			ix.body.ClearWounds(bot)
		end)

		-- A bandage in open storage can be applied; once the storage is closed it no longer counts.
		local prop = ents.Create("prop_physics")
		prop:SetModel("models/props_junk/wood_crate001a.mdl")
		prop:SetPos(bot:GetPos() + Vector(50, 0, 10))
		prop:Spawn()
		local physics = prop:GetPhysicsObject()
		if (IsValid(physics)) then physics:EnableMotion(false) end
		local crate = ix.inventory.Create(4, 4, 2100400001)

		defer(function()
			if (crate.storageInfo) then ix.storage.Close(crate) end
			for _, item in pairs(crate:GetItems()) do item:Remove() end
			ix.item.inventories[crate:GetID()] = nil
			if (IsValid(prop)) then prop:Remove() end
		end)

		WithConfig({bodyWoundsEnabled = true, bodyWoundHealTime = 100}, function()
			local storageBandage = GiveItem(crate, "bandage")
			ix.storage.Open(bot, crate, {entity = prop, name = "crate"})

			ix.body.AddWound(bot, "arms", "cut", 40)
			local treated = ix.body.FinishTreatWound(bot, storageBandage, "arms", char:GetID())
			if (!treated or treated.state != "dressed") then fail("storage bandage did not dress the wound") end
			Expect(fail, "storage bandage consumed", crate:GetItemByID(storageBandage.id, false), nil)
			ix.body.ClearWounds(bot)

			local closedBandage = GiveItem(crate, "bandage")
			ix.storage.Close(crate, bot)
			ix.body.AddWound(bot, "chest", "cut", 40)
			Expect(fail, "bandage in closed storage cannot treat", ix.body.FinishTreatWound(bot, closedBandage, "chest", char:GetID()), false)
			local stillOpen = ix.body.GetWound(bot, "chest")
			Expect(fail, "wound stays open when bandage is out of reach", stillOpen and stillOpen.state, "open")
			if (!crate:GetItemByID(closedBandage.id, false)) then fail("unreachable bandage was consumed") end
			ix.body.ClearWounds(bot)
		end)
	end)
end)

GWH.Check("body: datapad ReadBody, /Feel reporting, admin commands and death clearing", function(fail)
	local bodyPlugin = Plugin("body", fail)
	if (!bodyPlugin or !ix.body or !ix.datapad) then return fail("body or datapad missing") end

	Scoped(function(defer)
		local bot = Setup(defer)
		local char = bot:GetCharacter()

		WithConfig({bodyWoundsEnabled = true, bodyWoundHealTime = 100}, function()
			bot:SetHealth(bot:GetMaxHealth())
			ix.body.AddWound(bot, "legs", "gunshot", 75)

			-- Datapad ReadBody exposes active wounds even at full health
			local readOpen = ix.datapad.ReadBody(bot)
			if (!istable(readOpen.wounds) or !readOpen.wounds.legs) then
				return fail("datapad ReadBody missing open legs wound")
			end
			Expect(fail, "ReadBody legs wound state open", readOpen.wounds.legs.state, "open")
			Expect(fail, "ReadBody legs wound kind gunshot", readOpen.wounds.legs.kind, "gunshot")

			-- /Feel reports open wound and replaces "You feel fine."
			local immersion = ix.plugin.Get("immersion")
			if (immersion and isfunction(immersion.DescribeCondition)) then
				local feelOpen = immersion:DescribeCondition(bot)
				if (!string.find(feelOpen, "gunshot", 1, true) or !string.find(feelOpen, "legs", 1, true)) then
					fail("/Feel did not report open leg gunshot: " .. tostring(feelOpen))
				end
				if (string.find(feelOpen, L("feelFine", bot), 1, true)) then
					fail("/Feel kept 'You feel fine.' while wounded: " .. tostring(feelOpen))
				end
			end

			-- Dressing transitions both ReadBody and /Feel to healing state
			ix.body.TreatWound(bot, "legs")
			local readDressed = ix.datapad.ReadBody(bot)
			Expect(fail, "ReadBody legs wound state dressed", readDressed.wounds.legs and readDressed.wounds.legs.state, "dressed")

			if (immersion and isfunction(immersion.DescribeCondition)) then
				local feelDressed = immersion:DescribeCondition(bot)
				if (!string.find(feelDressed, "bound", 1, true) or !string.find(feelDressed, "healing", 1, true)) then
					fail("/Feel did not report dressed healing wound: " .. tostring(feelDressed))
				end
			end

			-- Full heal clears ReadBody and /Feel
			bodyPlugin:WoundTick(bot, char, 120)
			local readHealed = ix.datapad.ReadBody(bot)
			Expect(fail, "ReadBody legs wound cleared after heal", readHealed.wounds.legs, nil)
			Expect(fail, "DescribeWounds nil after heal", bodyPlugin:DescribeWounds(bot), nil)

			-- Admin commands registered and functional
			if (!ix.command.list.charsetwound or !ix.command.list.charclearwounds) then
				fail("admin wound commands missing")
			else
				ix.command.list.charsetwound:OnRun(bot, char, "arms", "cut", 60)
				local setWound = ix.body.GetWound(bot, "arms")
				Expect(fail, "CharSetWound created arms cut", setWound and setWound.kind, "cut")
				Expect(fail, "CharSetWound severity", setWound and setWound.severity, 60)

				ix.command.list.charclearwounds:OnRun(bot, char)
				Expect(fail, "CharClearWounds cleared wounds", ix.body.GetWound(bot, "arms"), nil)
			end

			-- Death clears all wounds and resets felt effects
			ix.body.AddWound(bot, "legs", "gunshot", 80)
			ix.body.AddWound(bot, "arms", "cut", 70)
			hook.Run("PlayerDeath", bot, bot, bot)
			Expect(fail, "death cleared legs wound", ix.body.GetWound(bot, "legs"), nil)
			Expect(fail, "death cleared arms wound", ix.body.GetWound(bot, "arms"), nil)
			Expect(fail, "death reset leg scale", ix.body.GetLegSpeedScale(bot), 1)
			Expect(fail, "death reset arm shake", ix.body.GetArmShake(bot), 0)
		end)
	end)
end)

GWH.Check("body: garments unify carryWeight and wet weight scales with effective waterproofing", function(fail)
	if (!ix.wear or !ix.datapad) then return fail("ix.wear or ix.datapad missing") end

	local expectedWeights = {
		winter_coat = 2.4,
		rain_poncho = 0.4,
		work_boots = 1.8,
		wool_cap = 0.2,
		wool_gloves = 0.2,
		resistance_uniform = 3.8,
		rmedic_uniform = 1.6
	}

	Expect(fail, "OUTFIT_DEFAULTS carryWeight", ix.wear.OUTFIT_DEFAULTS.carryWeight, 1.6)

	for uniqueID, expected in SortedPairs(expectedWeights) do
		local def = ix.item.list[uniqueID]
		if (!def) then
			fail("missing garment definition: " .. uniqueID)
		else
			if (!isnumber(def.carryWeight) or def.carryWeight <= 0) then
				fail(uniqueID .. " lacks a positive carryWeight")
			end
			Near(fail, uniqueID .. " carryWeight", def.carryWeight, expected)
		end
	end

	-- Every wearable registered in the gamemode has a positive carryWeight
	for uniqueID, def in SortedPairs(ix.item.list) do
		if (ix.wear.IsWearable(def) and (!isnumber(def.carryWeight) or def.carryWeight <= 0)) then
			fail("wearable " .. uniqueID .. " has no positive carryWeight")
		end
	end

	Scoped(function(defer)
		local bot, inv = Setup(defer)
		local char = bot:GetCharacter()
		local wetness = char.GetWetness and char:GetWetness() or 0
		defer(function()
			if (char.SetWetness) then char:SetWetness(wetness) end
		end)

		local coat = GiveItem(inv, "winter_coat")
		local spareCoat = GiveItem(inv, "winter_coat")
		local poncho = GiveItem(inv, "rain_poncho")

		-- Dry weights
		Near(fail, "dry winter_coat weight", ix.wear.GetWeight(coat, 0), 2.4)
		Near(fail, "dry rain_poncho weight", ix.wear.GetWeight(poncho, 0), 0.4)

		-- Soaked absorbent coat gets noticeably heavier; new poncho barely gains weight
		local soakedCoat = ix.wear.GetWeight(coat, 100)
		local soakedNewPoncho = ix.wear.GetWeight(poncho, 100)
		Near(fail, "soaked new winter_coat", soakedCoat, 2.4 * (1 + 0.45 * (1 - 0.2)))
		Near(fail, "soaked new rain_poncho", soakedNewPoncho, 0.4 * (1 + 0.45 * (1 - 0.9)))
		if (!(soakedCoat - 2.4 > 0.8 and soakedNewPoncho - 0.4 < 0.05)) then
			fail("wet absorption did not distinguish absorbent coat from waterproof poncho")
		end

		-- Worn/tattered rain poncho loses waterproofing and soaks up more water weight
		ix.wear.SetCondition(poncho, 15)
		local wornEff = ix.wear.GetEffectiveness(15)
		local soakedWornPoncho = ix.wear.GetWeight(poncho, 100)
		Near(fail, "soaked tattered rain_poncho", soakedWornPoncho, 0.4 * (1 + 0.45 * (1 - 0.9 * wornEff)))
		if (!(soakedWornPoncho > soakedNewPoncho + 0.05)) then
			fail("tattered poncho did not absorb more water weight than a new poncho")
		end

		ix.wear.SetCondition(poncho, 0)
		Near(fail, "soaked ruined rain_poncho", ix.wear.GetWeight(poncho, 100), 0.4 * 1.45)

		-- Datapad Weight (1-arg and 2-arg) and Layout reflect wet weight only for equipped garments
		coat:SetData("equip", true)
		if (char.SetWetness) then char:SetWetness(100) end

		Near(fail, "datapad 1-arg equipped soaked coat", ix.datapad.Weight(coat), soakedCoat)
		Near(fail, "datapad 1-arg unequipped spare coat stays dry", ix.datapad.Weight(spareCoat), 2.4)
		Near(fail, "datapad 2-arg explicit dry override", ix.datapad.Weight(coat, 0), 2.4)
		Near(fail, "datapad 2-arg unequipped spare coat stays dry", ix.datapad.Weight(spareCoat, 100), 2.4)

		-- Wet weight can push total carried load from Light (< 12 kg) into Loaded (>= 12 kg)
		spareCoat:Remove()
		poncho:Remove()
		ix.stack.Give(inv, "metal_scrap", 9.2) -- 2.4 + 9.2 = 11.6 kg dry (Light), 3.264 + 9.2 = 12.464 kg soaked (Loaded)
		local dryKg = ix.datapad.Total(ix.datapad.Layout(inv, 0))
		local wetKg = ix.datapad.Total(ix.datapad.Layout(inv, 100))
		local dryBandName, dryBand = ix.datapad.LoadBand(dryKg)
		local wetBandName, wetBand = ix.datapad.LoadBand(wetKg)
		Expect(fail, "dry kit is Light", dryBandName, "Light")
		Expect(fail, "dry kit band 1", dryBand, 1)
		Expect(fail, "soaked kit crosses into Loaded", wetBandName, "Loaded")
		Expect(fail, "soaked kit band 2", wetBand, 2)
	end)
end)

GWH.Check("body: worn garments degrade rain, warmth and armour together while keeping pockets intact", function(fail)
	local exposure = Plugin("exposure", fail)
	if (!exposure or !ix.wear or !ix.datapad) then return fail("exposure, wear or datapad missing") end

	Scoped(function(defer)
		local bot, inv = Setup(defer)
		local char = bot:GetCharacter()
		local snapshot = S.Snapshot(bot)
		local temp, wet = char:GetTemperature(), char:GetWetness()
		local prefs = table.Copy(char:GetData("carryPrefs", {}))
		defer(function()
			S.Restore(bot, snapshot)
			char:SetTemperature(temp)
			char:SetWetness(wet)
			char:SetData("carryPrefs", prefs)
			bot:SetArmor(0)
		end)

		S.Become(bot, FACTION_CITIZEN)
		local rainEnv = {air = 8, outdoors = true, precipitation = 0.8, wind = 0.4, heat = 0, water = 0}

		WithConfig({wearEnabled = true, exposureEnabled = true}, function()
			-- Winter coat degrades warmth and rain protection while keeping both pockets and stowed items
			local coat = GiveItem(inv, "winter_coat")
			coat:SetData("equip", true)
			local bandage = GiveItem(inv, "bandage")
			local vial = GiveItem(inv, "health_vial")
			local outerKey = "pkt_" .. coat.id .. "_outer"
			local liningKey = "pkt_" .. coat.id .. "_lining"

			Expect(fail, "stow vial in coat outer", ix.datapad.Move(bot, vial.id, outerKey), true)
			Expect(fail, "stow bandage in coat lining", ix.datapad.Move(bot, bandage.id, liningKey), true)

			local newClothing = exposure:GetClothing(bot)
			Near(fail, "new coat warmth", newClothing.warmth, 18)
			Near(fail, "new coat waterproof", newClothing.waterproof, 0.2)

			for _, cond in ipairs({10, 0}) do
				ix.wear.SetCondition(coat, cond)
				local wornClothing = exposure:GetClothing(bot)
				if (!(wornClothing.warmth < newClothing.warmth)) then
					fail("coat warmth did not drop at condition " .. cond)
				end
				if (!(wornClothing.waterproof < newClothing.waterproof)) then
					fail("coat waterproof did not drop at condition " .. cond)
				end
				local afterRain = exposure:UpdateWetness(0, rainEnv, wornClothing.waterproof, 60)
				if (!(afterRain > 0)) then
					fail("worn coat at condition " .. cond .. " did not let rain through")
				end

				local groups = ix.datapad.Layout(inv)
				local outerPlace = FindPlace(groups, outerKey)
				local liningPlace = FindPlace(groups, liningKey)
				if (!outerPlace or !liningPlace) then
					fail("coat pockets disappeared at condition " .. cond)
				else
					Expect(fail, "outer capacity intact at " .. cond, outerPlace.limit, 4)
					Expect(fail, "lining capacity intact at " .. cond, liningPlace.limit, 1)
				end

				local vialPlace = ix.datapad.Locate(groups, vial.id)
				local bandagePlace = ix.datapad.Locate(groups, bandage.id)
				Expect(fail, "vial stayed in coat outer at " .. cond, vialPlace and vialPlace.key, outerKey)
				Expect(fail, "bandage stayed in coat lining at " .. cond, bandagePlace and bandagePlace.key, liningKey)
			end

			coat:SetData("equip", false)

			-- Rain poncho: new blocks rain and resists soaked wear; tattered lets rain through and suffers soaked wear; ruined keeps pouch
			local poncho = GiveItem(inv, "rain_poncho")
			poncho:SetData("equip", true)
			local pouchKey = "pkt_" .. poncho.id .. "_pouch"
			Expect(fail, "stow bandage in poncho pouch", ix.datapad.Move(bot, bandage.id, pouchKey), true)

			local newPonchoCloth = exposure:GetClothing(bot)
			Near(fail, "new poncho waterproof", newPonchoCloth.waterproof, 0.9)
			Expect(fail, "new poncho blocks rain", exposure:UpdateWetness(0, rainEnv, newPonchoCloth.waterproof, 60), 0)
			exposure:ApplyEffects(bot, char, 0, 80, 3600, false)
			Expect(fail, "new poncho resists soaked wear", ix.wear.GetCondition(poncho), 100)

			ix.wear.SetCondition(poncho, 15)
			local tatteredPonchoCloth = exposure:GetClothing(bot)
			if (!(tatteredPonchoCloth.waterproof < 0.5)) then
				fail("tattered poncho waterproof stayed >= 0.5: " .. tostring(tatteredPonchoCloth.waterproof))
			end
			if (!(exposure:UpdateWetness(0, rainEnv, tatteredPonchoCloth.waterproof, 60) > 0)) then
				fail("tattered poncho did not let rain through")
			end
			exposure:ApplyEffects(bot, char, 0, 80, 3600, false)
			if (!(ix.wear.GetCondition(poncho) < 15)) then
				fail("tattered poncho letting rain through did not suffer soaked wear")
			end

			ix.wear.SetCondition(poncho, 0)
			local ruinedPonchoGroups = ix.datapad.Layout(inv)
			local ruinedPouch = FindPlace(ruinedPonchoGroups, pouchKey)
			Expect(fail, "ruined poncho pouch stays intact", ruinedPouch != nil, true)
			local bandageInPouch = ix.datapad.Locate(ruinedPonchoGroups, bandage.id)
			Expect(fail, "bandage stays in ruined poncho pouch", bandageInPouch and bandageInPouch.key, pouchKey)
			poncho:SetData("equip", false)

			-- Resistance uniform: armour capacity and warmth wear down together while uniform pockets stay intact
			local uniform = GiveItem(inv, "resistance_uniform")
			uniform:SetData("equip", true)
			local uniKey = "pkt_" .. uniform.id .. "_chest"
			Expect(fail, "stow vial in uniform chest", ix.datapad.Move(bot, vial.id, uniKey), true)

			local newUniWarmth = exposure:GetClothing(bot).warmth
			Expect(fail, "new uniform armour capacity", uniform:GetArmorCapacity(), 50)

			ix.wear.SetCondition(uniform, 30)
			Expect(fail, "worn uniform armour capacity", uniform:GetArmorCapacity(), math.floor(50 * 0.75))
			if (!(exposure:GetClothing(bot).warmth < newUniWarmth)) then
				fail("worn uniform did not lose warmth alongside armour")
			end

			ix.wear.SetCondition(uniform, 0)
			Expect(fail, "ruined uniform armour capacity", uniform:GetArmorCapacity(), 0)
			Near(fail, "ruined uniform warmth back to faction base", exposure:GetClothing(bot).warmth, 8)
			local uniGroups = ix.datapad.Layout(inv)
			Expect(fail, "ruined uniform keeps pocket", FindPlace(uniGroups, uniKey) != nil, true)
			local vialInUni = ix.datapad.Locate(uniGroups, vial.id)
			Expect(fail, "vial stays in ruined uniform pocket", vialInUni and vialInUni.key, uniKey)
		end)
	end)
end)

GWH.Check("body: winter coat in summer drains thirst and stamina; dry smelter route vs wet route", function(fail)
	local exposure = Plugin("exposure", fail)
	local survival = Plugin("survivaladditions", fail)
	if (!exposure or !survival or !ix.weather or !ix.smelting) then
		return fail("exposure, survivaladditions, weather or smelting missing")
	end

	Scoped(function(defer)
		local bot, inv = Setup(defer)
		local char = bot:GetCharacter()
		local snapshot = S.Snapshot(bot)
		local temp, wet = char:GetTemperature(), char:GetWetness()
		local hunger, thirst = char:GetHunger(), char:GetThirst()
		defer(function()
			S.Restore(bot, snapshot)
			char:SetTemperature(temp)
			char:SetWetness(wet)
			char:SetHunger(hunger)
			char:SetThirst(thirst)
			bot:SetLocalVar("stm", 100)
		end)

		S.Become(bot, FACTION_CITIZEN)

		WithConfig({
			weatherMeanTemperature = 12, weatherSeasonSwing = 6, weatherDaySwing = 5,
			exposureEnabled = true, exposureAdjustTime = 20,
			hungerthirstEnabled = true, thirstLossTime = 90,
			needsLowThreshold = 25, needsLowStaminaScale = 0.5
		}, function()
			local clear = ix.weather.types.clear
			local summerAir = ix.weather.ComputeTemperature(15, 7.5, clear.temperature)
			local summerWalk = {air = summerAir, outdoors = true, precipitation = 0, wind = clear.wind, heat = 0, sprinting = false, water = 0}
			local summerSprint = {air = summerAir, outdoors = true, precipitation = 0, wind = clear.wind, heat = 0, sprinting = true, water = 0}

			-- Bare citizen in summer sun stays comfortable with full stamina regen and no extra thirst drain
			char:SetHunger(100)
			char:SetThirst(100)
			char:SetTemperature(0)
			local bareTarget = exposure:GetTarget(exposure:GetStress(exposure:GetFeltTemperature(summerWalk, 0), exposure:GetClothing(bot).warmth))
			Expect(fail, "bare summer level comfortable", ix.exposure.GetLevel(bareTarget), 0)
			Expect(fail, "comfortable stamina regen unchanged", hook.Run("AdjustStaminaOffset", bot, 2), nil)

			-- Wearing a winter coat in summer sun pushes into hot (standing) and overheating (sprinting)
			local coat = GiveItem(inv, "winter_coat")
			coat:SetData("equip", true)

			local coatWarmth = exposure:GetClothing(bot).warmth
			local standTarget = exposure:GetTarget(exposure:GetStress(exposure:GetFeltTemperature(summerWalk, 0), coatWarmth))
			local sprintTarget = exposure:GetTarget(exposure:GetStress(exposure:GetFeltTemperature(summerSprint, 0), coatWarmth))
			if (!(ix.exposure.GetLevel(standTarget) >= 2)) then
				fail("winter coat standing in summer sun only reached target " .. tostring(standTarget))
			end
			if (!(ix.exposure.GetLevel(sprintTarget) >= 3)) then
				fail("winter coat sprinting in summer sun only reached target " .. tostring(sprintTarget))
			end

			-- At hot (level +2): thirst drains faster AND stamina regen slows via AdjustStaminaOffset
			char:SetTemperature(standTarget)
			char:SetThirst(80)
			local hotFx = exposure:ApplyEffects(bot, char, standTarget, 0, 60, false)
			if (!(hotFx.thirst > 0)) then fail("winter coat in summer sun did not drain thirst") end
			Near(fail, "hot stamina regen scale", hook.Run("AdjustStaminaOffset", bot, 2), 2 * 0.70)
			Expect(fail, "stamina drain negative offset untouched", hook.Run("AdjustStaminaOffset", bot, -1), nil)

			-- Composing low thirst (0.5) + hot (0.70) without hook-swallowing
			char:SetThirst(10)
			Near(fail, "composed low thirst + hot regen", hook.Run("AdjustStaminaOffset", bot, 2), 2 * 0.5 * 0.70)
			char:SetThirst(80)

			-- Pushing into overheating (level +3): regen drops to 0.50 AND moving actively drains stamina
			char:SetTemperature(sprintTarget)
			Near(fail, "overheating stamina regen scale", hook.Run("AdjustStaminaOffset", bot, 2), 2 * 0.50)
			if (bot.ConsumeStamina) then
				bot:SetLocalVar("stm", 100)
				local overheatFx = exposure:ApplyEffects(bot, char, sprintTarget, 0, 5, true)
				if (!(overheatFx.stamina > 0)) then
					fail("overheating in summer winter coat did not actively drain stamina while moving")
				end
			end

			-- Dry route past a running smelter vs wet route
			local smelter = ents.Create("ix_station_smelter")
			if (!IsValid(smelter)) then return fail("could not spawn ix_station_smelter") end
			smelter:SetPos(bot:GetPos() + Vector(60, 0, 0))
			smelter:Spawn()
			defer(function() if (IsValid(smelter)) then smelter:Remove() end end)

			-- Idle smelter adds no heat; fueled running smelter warms nearby character
			Near(fail, "idle smelter adds no heat", ix.exposure.GetHeatAt(bot:WorldSpaceCenter(), bot), 0, 1e-2)
			ix.smelting.Restore(smelter, {fuel = 20, queue = {{"iron_ore", 1}}})
			local smelterHeat = ix.exposure.GetHeatAt(bot:WorldSpaceCenter(), bot)
			if (!(smelterHeat > 5)) then
				fail("running smelter gave too little heat at 60 units: " .. tostring(smelterHeat))
			end

			local dryRouteEnv = {air = 6, outdoors = false, precipitation = 0, wind = 0, heat = smelterHeat, water = 0}
			local wetRouteEnv = {air = 6, outdoors = true, precipitation = 0.7, wind = 0.45, heat = 0, water = 0}

			-- Cold soaked character dries and warms quickly past the smelter, vs getting wetter/colder on the wet route
			local dryRouteWet = exposure:UpdateWetness(70, dryRouteEnv, 0.1, 120)
			local wetRouteWet = exposure:UpdateWetness(70, wetRouteEnv, 0.1, 120)
			if (!(dryRouteWet < 55 and wetRouteWet > 70)) then
				fail(string.format("smelter route wetness %.1f vs wet route %.1f", dryRouteWet, wetRouteWet))
			end

			local dryWarmTarget = exposure:GetTarget(exposure:GetStress(exposure:GetFeltTemperature(dryRouteEnv, dryRouteWet), 8))
			local tempAfterSmelter = exposure:ApproachTemperature(-60, dryWarmTarget, 120, dryRouteEnv.heat)
			local wetColdTarget = exposure:GetTarget(exposure:GetStress(exposure:GetFeltTemperature(wetRouteEnv, wetRouteWet), 8))
			local tempAfterRain = exposure:ApproachTemperature(-60, wetColdTarget, 120, 0)
			if (!(tempAfterSmelter > -40 and tempAfterRain < -60)) then
				fail(string.format("smelter route temp %.1f vs wet route %.1f", tempAfterSmelter, tempAfterRain))
			end

			-- Wearing a winter coat next to a running smelter in a mild workshop (15 °C) overheats while bare stays below hot
			local workshopEnv = {air = 15, outdoors = false, precipitation = 0, wind = 0, heat = smelterHeat, water = 0}
			local bareBySmelter = exposure:GetTarget(exposure:GetStress(exposure:GetFeltTemperature(workshopEnv, 0), 8))
			local coatBySmelter = exposure:GetTarget(exposure:GetStress(exposure:GetFeltTemperature(workshopEnv, 0), coatWarmth))
			if (!(ix.exposure.GetLevel(bareBySmelter) < 2 and ix.exposure.GetLevel(coatBySmelter) >= 2)) then
				fail(string.format("smelter workshop bare=%.1f vs coat=%.1f", bareBySmelter, coatBySmelter))
			end
		end)
	end)
end)

GWH.Check("body: exposureLethal stays off while extreme exposure impairs combat readiness", function(fail)
	local exposure = Plugin("exposure", fail)
	if (!exposure or !ix.exposure) then return fail("exposure plugin missing") end

	-- exposureLethal must default to false
	local stored = ix.config.stored.exposureLethal
	Expect(fail, "exposureLethal default is false", stored and stored.default, false)

	-- Stamina regen scale across the full temperature spectrum
	Expect(fail, "regen scale comfortable", ix.exposure.GetStaminaRegenScale(0), 1)
	Expect(fail, "regen scale warm", ix.exposure.GetStaminaRegenScale(30), 1)
	Expect(fail, "regen scale chilly", ix.exposure.GetStaminaRegenScale(-30), 1)
	Expect(fail, "regen scale hot", ix.exposure.GetStaminaRegenScale(60), 0.70)
	Expect(fail, "regen scale overheating", ix.exposure.GetStaminaRegenScale(80), 0.50)
	Expect(fail, "regen scale freezing", ix.exposure.GetStaminaRegenScale(-80), 0.50)
	Expect(fail, "regen scale heatstroke", ix.exposure.GetStaminaRegenScale(95), 0.30)
	Expect(fail, "regen scale hypothermic", ix.exposure.GetStaminaRegenScale(-95), 0.30)

	-- Speed scale still slows freezing/hypothermic and keeps 1 in heat
	if (!(ix.exposure.GetSpeedScale(-80) < 1 and ix.exposure.GetSpeedScale(-100) < ix.exposure.GetSpeedScale(-80))) then
		fail("freezing/hypothermic did not slow movement")
	end
	Expect(fail, "speed scale in heat remains 1", ix.exposure.GetSpeedScale(100), 1)

	Scoped(function(defer)
		local bot = Setup(defer)
		local char = bot:GetCharacter()
		local snapshot = S.Snapshot(bot)
		local temp, wet = char:GetTemperature(), char:GetWetness()
		defer(function()
			S.Restore(bot, snapshot)
			char:SetTemperature(temp)
			char:SetWetness(wet)
			bot:SetHealth(bot:GetMaxHealth())
			bot:SetLocalVar("stm", 100)
		end)

		S.Become(bot, FACTION_CITIZEN)

		WithConfig({exposureEnabled = true, exposureDamage = 5, exposureLethal = false, hungerthirstEnabled = false}, function()
			-- Extreme cold drops health down to healthFloor (10) without killing
			bot:SetHealth(18)
			char:SetTemperature(-100)
			exposure:ApplyEffects(bot, char, -100, 0, 5, false)
			exposure:ApplyEffects(bot, char, -100, 0, 5, false)
			exposure:ApplyEffects(bot, char, -100, 0, 5, false)
			Expect(fail, "hypothermia stops at health floor", bot:Health(), ix.exposure.tuning.healthFloor)
			Expect(fail, "hypothermia does not kill with exposureLethal off", bot:Alive(), true)
			Near(fail, "hypothermic stamina regen heavily impaired", hook.Run("AdjustStaminaOffset", bot, 2), 2 * 0.30)

			-- Extreme heat also stops at healthFloor (10) without killing, and impairs stamina regen + moving stamina
			bot:SetHealth(18)
			char:SetTemperature(100)
			exposure:ApplyEffects(bot, char, 100, 0, 5, false)
			exposure:ApplyEffects(bot, char, 100, 0, 5, false)
			exposure:ApplyEffects(bot, char, 100, 0, 5, false)
			Expect(fail, "heatstroke stops at health floor", bot:Health(), ix.exposure.tuning.healthFloor)
			Expect(fail, "heatstroke does not kill with exposureLethal off", bot:Alive(), true)
			Near(fail, "heatstroke stamina regen heavily impaired", hook.Run("AdjustStaminaOffset", bot, 2), 2 * 0.30)

			if (bot.ConsumeStamina) then
				bot:SetLocalVar("stm", 100)
				local strokeFx = exposure:ApplyEffects(bot, char, 100, 0, 5, true)
				if (!(strokeFx.stamina >= 20)) then
					fail("heatstroke moving stamina drain too low: " .. tostring(strokeFx.stamina))
				end
			end

			-- Climate-sealed faction (OTA) ignores exposure stamina penalties
			S.Become(bot, FACTION_OTA)
			char:SetTemperature(100)
			Expect(fail, "sealed faction unaffected by exposure stamina scale", hook.Run("AdjustStaminaOffset", bot, 2), nil)
		end)
	end)
end)

GWH.Check("body: quick pocket/belt access vs slow bag and hidden pocket rummaging", function(fail)
	local datapad = Plugin("datapad", fail)
	if (!datapad or !ix.datapad) then return fail("datapad plugin missing") end

	Scoped(function(defer)
		local bot, inv = Setup(defer)
		defer(function()
			ix.datapad.CancelTimedAccess(bot)
			bot:SetNetVar("restricted", nil)
		end)

		local coat = GiveItem(inv, "winter_coat")
		local boots = GiveItem(inv, "work_boots")
		local bag = GiveItem(inv, "suitcase")
		coat:SetData("equip", true)
		boots:SetData("equip", true)

		local groups = ix.datapad.Layout(inv)
		local belt = FindPlace(groups, "belt")
		local sling = FindPlace(groups, "sling")
		local hands = FindPlace(groups, "hands")
		local pockets = FindPlace(groups, "pockets")
		local outer = FindPlace(groups, "pkt_" .. coat.id .. "_outer")
		local lining = FindPlace(groups, "pkt_" .. coat.id .. "_lining")
		local boot = FindPlace(groups, "boot")
		local bagPlace = FindPlace(groups, "bag" .. bag.id)

		if (!belt or !sling or !hands or !pockets or !outer or !lining or !boot or !bagPlace) then
			return fail("expected carry places missing from layout")
		end

		-- Quick access (0s): belt, sling, hands, trouser pockets, outer garment pockets
		Expect(fail, "belt accessTime", ix.datapad.GetAccessTime(belt), 0)
		Expect(fail, "sling accessTime", ix.datapad.GetAccessTime(sling), 0)
		Expect(fail, "hands accessTime", ix.datapad.GetAccessTime(hands), 0)
		Expect(fail, "pockets accessTime", ix.datapad.GetAccessTime(pockets), 0)
		Expect(fail, "winter coat outer accessTime", ix.datapad.GetAccessTime(outer), 0)

		-- Hidden pockets (1.2s) and bags (>= 2s, 2.8s)
		Near(fail, "winter coat lining accessTime", ix.datapad.GetAccessTime(lining), 1.2)
		Near(fail, "boot lining accessTime", ix.datapad.GetAccessTime(boot), 1.2)
		Near(fail, "suitcase bag accessTime", ix.datapad.GetAccessTime(bagPlace), ix.datapad.BAG_ACCESS_TIME)
		if (!(ix.datapad.GetAccessTime(bagPlace) >= 2)) then
			fail("bag access time should be >= 2s, got " .. tostring(ix.datapad.GetAccessTime(bagPlace)))
		end

		for _, place in ipairs(groups) do
			Near(fail, "layout stored accessTime for " .. place.key, place.accessTime, ix.datapad.GetAccessTime(place))
		end

		-- Quick StartTimedAccess executes immediately without rummaging state
		local quickRan = false
		ix.datapad.StartTimedAccess(bot, pockets, "Quick", function() quickRan = true end)
		Expect(fail, "quick access ran immediately", quickRan, true)
		Expect(fail, "quick access does not set datapadRummaging", bot:GetNetVar("datapadRummaging"), nil)

		-- Slow StartTimedAccess sets datapadRummaging and strips attack/sprint in StartCommand
		local slowRan = false
		ix.datapad.StartTimedAccess(bot, bagPlace, "Digging into suitcase...", function() slowRan = true end)
		Expect(fail, "bag access deferred", slowRan, false)
		Expect(fail, "bag access sets datapadRummaging", bot:GetNetVar("datapadRummaging"), bagPlace.name)

		local stripped = {}
		local fakeCmd = {RemoveKey = function(_, key) stripped[key] = true end}
		datapad:StartCommand(bot, fakeCmd)
		Expect(fail, "rummaging strips IN_ATTACK", stripped[IN_ATTACK], true)
		Expect(fail, "rummaging strips IN_ATTACK2", stripped[IN_ATTACK2], true)
		Expect(fail, "rummaging strips IN_SPEED", stripped[IN_SPEED], true)

		-- Heavy hit cancels rummaging
		local dmg = DamageInfo()
		dmg:SetDamage(20)
		dmg:SetDamageType(DMG_CLUB)
		datapad:PostEntityTakeDamage(bot, dmg, true)
		Expect(fail, "heavy hit cancels datapadRummaging", bot:GetNetVar("datapadRummaging"), nil)

		-- Restraint cancels rummaging
		ix.datapad.StartTimedAccess(bot, boot, "Reaching into boot...", function() end)
		Expect(fail, "boot access sets datapadRummaging", bot:GetNetVar("datapadRummaging"), boot.name)
		datapad:OnPlayerRestricted(bot)
		Expect(fail, "restraint cancels datapadRummaging", bot:GetNetVar("datapadRummaging"), nil)

		-- Wrapped PerformInventoryAction: using a quick pocket item runs immediately, bag item starts rummaging
		local quickVial = GiveItem(inv, "health_vial")
		local bagVial = GiveItem(inv, "health_vial")
		local quickPlace = ix.datapad.Locate(ix.datapad.Layout(inv), quickVial.id)
		if (!quickPlace or quickPlace.key != "pockets") then
			Expect(fail, "move quickVial to pockets", ix.datapad.Move(bot, quickVial.id, "pockets"), true)
		end
		Expect(fail, "move bagVial to suitcase", ix.datapad.Move(bot, bagVial.id, bagPlace.key), true)

		bot:SetHealth(50)
		ix.item.PerformInventoryAction(bot, "Apply", quickVial.id, quickVial.invID)
		Expect(fail, "pocket health_vial applied immediately", bot:Health() > 50, true)
		Expect(fail, "pocket action does not set rummaging", bot:GetNetVar("datapadRummaging"), nil)

		bot:SetHealth(50)
		ix.item.PerformInventoryAction(bot, "Apply", bagVial.id, bagVial.invID)
		Expect(fail, "bag health_vial waits for rummage", bot:Health(), 50)
		Expect(fail, "bag action sets datapadRummaging", bot:GetNetVar("datapadRummaging"), bagPlace.name)
		ix.datapad.CancelTimedAccess(bot)

		-- RequestMove out of a bag starts timed rummaging rather than moving instantly
		ix.datapad.RequestMove(bot, bagVial.id, "pockets")
		Expect(fail, "RequestMove from bag sets datapadRummaging", bot:GetNetVar("datapadRummaging"), bagPlace.name)
		ix.datapad.CancelTimedAccess(bot)
	end)
end)

GWH.Check("body: slung rifle is visible on sling and clears when bagged or held", function(fail)
	if (!ix.datapad) then return fail("ix.datapad missing") end

	Scoped(function(defer)
		local bot, inv = Setup(defer)
		local bag = GiveItem(inv, "suitcase")
		local ar2 = GiveItem(inv, "ar2")
		if (!bag or !ar2) then return fail("could not create suitcase or ar2") end

		local ar2Place = ix.datapad.Locate(ix.datapad.Layout(inv), ar2.id)
		Expect(fail, "ar2 auto-files onto sling", ar2Place and ar2Place.key, "sling")
		ix.datapad.UpdateSlungWeapon(bot)
		local slung = bot:GetNetVar("ixSlungWeapon")
		if (!istable(slung)) then
			return fail("expected ixSlungWeapon to be set when rifle is on sling")
		end
		Expect(fail, "slung weapon class", slung.class, ar2.class)
		Expect(fail, "slung weapon model", slung.model, ar2:GetModel())
		Expect(fail, "slung weapon name", slung.name, ar2:GetName())

		-- Holding the rifle as active weapon hides the slung copy on the back
		ix.datapad.UpdateSlungWeapon(bot, ar2.class)
		Expect(fail, "holding active rifle clears ixSlungWeapon", bot:GetNetVar("ixSlungWeapon"), nil)

		-- Switching back to hands restores the slung rifle
		ix.datapad.UpdateSlungWeapon(bot, "ix_hands")
		local restored = bot:GetNetVar("ixSlungWeapon")
		Expect(fail, "unholstered back to hands restores ixSlungWeapon", istable(restored) and restored.class, ar2.class)

		-- Moving the rifle into a suitcase clears ixSlungWeapon, moving back to sling restores it
		Expect(fail, "move ar2 into suitcase", ix.datapad.Move(bot, ar2.id, "bag" .. bag.id), true)
		Expect(fail, "bagged rifle clears ixSlungWeapon", bot:GetNetVar("ixSlungWeapon"), nil)
		Expect(fail, "move ar2 back to sling", ix.datapad.Move(bot, ar2.id, "sling"), true)
		local reslung = bot:GetNetVar("ixSlungWeapon")
		Expect(fail, "re-slung rifle restores ixSlungWeapon", istable(reslung) and reslung.class, ar2.class)
	end)
end)

GWH.Check("body: thorough frisk finds hidden and boot lining last; hasty frisk misses and blocks them", function(fail)
	if (!ix.datapad) then return fail("ix.datapad missing") end

	Scoped(function(defer)
		local searcher = GWH.Bot()
		local subject = Lib.OtherBot()
		if (!searcher or !subject) then return fail("need two bots for frisk check") end

		local savedPos, savedRestricted = subject:GetPos(), subject:GetNetVar("restricted")
		ResetBot(searcher)
		ResetBot(subject)
		Clear(searcher)
		Clear(subject)
		subject:SetPos(searcher:GetPos() + Vector(36, 0, 0))
		subject:SetNetVar("restricted", true)

		defer(function()
			ix.datapad.EndFrisk(searcher)
			subject:SetNetVar("restricted", savedRestricted)
			subject:SetPos(savedPos)
			Clear(searcher)
			Clear(subject)
			ResetBot(searcher)
			ResetBot(subject)
		end)

		local subInv = subject:GetCharacter():GetInventory()
		local coat = GiveItem(subInv, "winter_coat")
		local boots = GiveItem(subInv, "work_boots")
		coat:SetData("equip", true)
		boots:SetData("equip", true)

		local pistol = GiveItem(subInv, "pistol")
		local bandage = GiveItem(subInv, "bandage")
		local vial = GiveItem(subInv, "health_vial")
		local cid = GiveItem(subInv, "cid")
		local liningKey = "pkt_" .. coat.id .. "_lining"

		-- Place items directly via data since subject is restricted
		pistol:SetData("carryPlace", "belt")
		bandage:SetData("carryPlace", "pockets")
		vial:SetData("carryPlace", liningKey)
		cid:SetData("carryPlace", "boot")

		local subGroups = ix.datapad.Layout(subInv)
		local beltPlace = FindPlace(subGroups, "belt")
		local liningPlace = FindPlace(subGroups, liningKey)
		local bootPlace = FindPlace(subGroups, "boot")

		Expect(fail, "FriskFindsPlace belt thorough", ix.datapad.FriskFindsPlace(beltPlace, "thorough"), true)
		Expect(fail, "FriskFindsPlace belt hasty", ix.datapad.FriskFindsPlace(beltPlace, "hasty"), true)
		Expect(fail, "FriskFindsPlace coat lining thorough", ix.datapad.FriskFindsPlace(liningPlace, "thorough"), true)
		Expect(fail, "FriskFindsPlace coat lining hasty", ix.datapad.FriskFindsPlace(liningPlace, "hasty"), false)
		Expect(fail, "FriskFindsPlace boot lining thorough", ix.datapad.FriskFindsPlace(bootPlace, "thorough"), true)
		Expect(fail, "FriskFindsPlace boot lining hasty", ix.datapad.FriskFindsPlace(bootPlace, "hasty"), false)

		local thoroughPlan, thoroughStep = ix.datapad.BuildFriskPlan(subInv, "thorough")
		local hastyPlan, hastyStep = ix.datapad.BuildFriskPlan(subInv, "hasty")
		Expect(fail, "hasty plan has 6 standard stages", #hastyPlan, 6)
		if (!(#thoroughPlan > #hastyPlan)) then
			fail("thorough plan should append hidden pocket stages after standard regions")
		end
		if (!(hastyStep < thoroughStep)) then
			fail("hasty step duration should be faster than thorough")
		end
		Expect(fail, "last thorough stage is hidden boot lining", thoroughPlan[#thoroughPlan].hidden and thoroughPlan[#thoroughPlan].placeKey, "boot")
		Expect(fail, "second-to-last thorough stage is hidden coat lining", thoroughPlan[#thoroughPlan - 1].hidden and thoroughPlan[#thoroughPlan - 1].placeKey, liningKey)

		-- Run thorough frisk to completion: visible items first, coat lining then boot lining LAST
		Expect(fail, "begin thorough frisk", ix.datapad.BeginFrisk(searcher, subject, "thorough"), true)
		local session = ix.datapad.GetFriskSession(searcher)
		if (!session) then return fail("thorough frisk session missing") end
		local t = CurTime()
		for _ = 1, #thoroughPlan + 1 do
			t = t + thoroughStep + 0.1
			ix.datapad.UpdateFrisks(t)
		end
		Expect(fail, "thorough frisk completed", session.complete, true)
		local indexByID = {}
		for idx, row in ipairs(session.foundOrder) do
			indexByID[row.id] = idx
		end
		if (!indexByID[pistol.id] or !indexByID[bandage.id] or !indexByID[vial.id] or !indexByID[cid.id]) then
			return fail("thorough frisk did not find all items")
		end
		if (!(indexByID[pistol.id] < indexByID[vial.id] and indexByID[bandage.id] < indexByID[vial.id])) then
			fail("thorough frisk did not find visible items before hidden coat lining")
		end
		if (!(indexByID[vial.id] < indexByID[cid.id])) then
			fail("thorough frisk did not find coat lining (0.75) before work boot lining (0.90)")
		end
		Expect(fail, "thorough storage has no foundIDs filter", subInv.storageInfo and subInv.storageInfo.datapadFoundIDs, nil)
		ix.datapad.EndFrisk(searcher)

		-- Run hasty frisk to completion: misses coat lining and boot lining and blocks taking them
		Expect(fail, "begin hasty frisk", ix.datapad.BeginFrisk(searcher, subject, "hasty"), true)
		local hastySession = ix.datapad.GetFriskSession(searcher)
		if (!hastySession) then return fail("hasty frisk session missing") end
		for _ = 1, #hastyPlan + 1 do
			t = t + hastyStep + 0.1
			ix.datapad.UpdateFrisks(t)
		end
		Expect(fail, "hasty frisk completed", hastySession.complete, true)
		Expect(fail, "hasty frisk finds belt pistol", hastySession.foundIDs[pistol.id], true)
		Expect(fail, "hasty frisk finds pocket bandage", hastySession.foundIDs[bandage.id], true)
		Expect(fail, "hasty frisk misses coat lining vial", hastySession.foundIDs[vial.id], nil)
		Expect(fail, "hasty frisk misses boot lining cid", hastySession.foundIDs[cid.id], nil)

		local okVial, whyVial = ix.datapad.Move(searcher, vial.id, "auto")
		Expect(fail, "hasty frisk blocks taking missed coat lining item", okVial, false)
		Expect(fail, "hasty frisk refusal reason", whyVial, "notAllowed")
		local okCid = ix.datapad.Move(searcher, cid.id, "auto")
		Expect(fail, "hasty frisk blocks taking missed boot lining item", okCid, false)
		Expect(fail, "CanPlayerInteractItem blocks missed boot item", hook.Run("CanPlayerInteractItem", searcher, "move", cid.id), false)
		Expect(fail, "hasty frisk allows taking discovered bandage", ix.datapad.Move(searcher, bandage.id, "auto"), true)
	end)
end)

GWH.Check("body: heavier carry load scales footstep sound and triggers heavy breathing", function(fail)
	if (!ix.datapad) then return fail("ix.datapad missing") end

	-- Band 1 (Light): quiet steps, no heavy breath
	Expect(fail, "light band footstep quiet", ix.datapad.GetFootstepSound(1, 0, false), nil)
	Expect(fail, "light band no heavy breath", ix.datapad.ShouldEmitHeavyBreath(1, 20, 120), false)

	-- Band 2 (Loaded): louder step on foot 0 when uncrouched, silent when crouched, heavy breath only when winded
	local loaded0 = ix.datapad.GetFootstepSound(2, 0, false)
	if (!istable(loaded0)) then return fail("loaded band foot 0 should emit gear sound") end
	Expect(fail, "loaded band foot 0 level", loaded0.level, 65)
	Near(fail, "loaded band foot 0 volume", loaded0.volume, 0.38)
	Expect(fail, "loaded band foot 1 silent", ix.datapad.GetFootstepSound(2, 1, false), nil)
	Expect(fail, "loaded band crouched silent", ix.datapad.GetFootstepSound(2, 0, true), nil)
	Expect(fail, "loaded band steady breath at high stamina", ix.datapad.ShouldEmitHeavyBreath(2, 60, 100), false)
	Expect(fail, "loaded band heavy breath when winded", ix.datapad.ShouldEmitHeavyBreath(2, 30, 0), true)

	-- Band 3 (Heavy): louder on BOTH feet, crouched creak on foot 0, heavy breath when moving or below 65 stamina
	local heavy0 = ix.datapad.GetFootstepSound(3, 0, false)
	local heavy1 = ix.datapad.GetFootstepSound(3, 1, false)
	local heavyCrouch0 = ix.datapad.GetFootstepSound(3, 0, true)
	if (!istable(heavy0) or !istable(heavy1) or !istable(heavyCrouch0)) then
		return fail("heavy band missing expected footstep sounds")
	end
	if (!(heavy0.level > loaded0.level and heavy0.volume > loaded0.volume)) then
		fail("heavy band footstep not louder than loaded band")
	end
	Expect(fail, "heavy band foot 0 level", heavy0.level, 76)
	Expect(fail, "heavy band foot 1 level", heavy1.level, 76)
	Expect(fail, "heavy band crouched foot 0 creak level", heavyCrouch0.level, 56)
	Expect(fail, "heavy band crouched foot 1 silent", ix.datapad.GetFootstepSound(3, 1, true), nil)

	Expect(fail, "heavy band calm when standing at full stamina", ix.datapad.ShouldEmitHeavyBreath(3, 100, 0), false)
	Expect(fail, "heavy band heavy breath while moving", ix.datapad.ShouldEmitHeavyBreath(3, 100, 80), true)
	Expect(fail, "heavy band heavy breath when winded", ix.datapad.ShouldEmitHeavyBreath(3, 55, 0), true)
end)
