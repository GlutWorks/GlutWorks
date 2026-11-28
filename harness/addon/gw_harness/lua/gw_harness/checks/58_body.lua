-- Body map (body): canonical regions, hitgroup mapping, garment coverage, garment pockets and concealment,
-- carry places and frisk order sharing one vocabulary with no translation between plugins.

local Lib = GWH.Lib
local Scoped, ResetBot, Fresh, GiveItem, Expect = Lib.Scoped, Lib.ResetBot, Lib.Fresh, Lib.GiveItem, Lib.Expect

local function Clear(bot)
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
