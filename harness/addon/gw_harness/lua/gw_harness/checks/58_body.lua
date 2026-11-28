-- Body map and persistent wounds (body): canonical regions, hitgroup mapping, garment coverage,
-- garment pockets and concealment, carry places, frisk order, and per-region persistent wounds
-- with garment wear, felt arm/leg effects, bandage treatment, visible recovery and /Feel reporting.

local Lib = GWH.Lib
local Scoped, ResetBot, Fresh, GiveItem, Expect = Lib.Scoped, Lib.ResetBot, Lib.Fresh, Lib.GiveItem, Lib.Expect
local Replace, WithConfig, Plugin = Lib.Replace, Lib.WithConfig, Lib.Plugin

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

