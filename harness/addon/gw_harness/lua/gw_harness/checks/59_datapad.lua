-- Carry locations, whole-instance transfers, quantity merges and the restraint boundary; which
-- body region each bone of a character model counts for, and where a blow landed.
local lib = GWH.Lib

GWH.Check("datapad: every bone of a character model counts for the region a hit on it does, feet and sides apart", function(fail)
	local models = {"models/player/group01/male_07.mdl"}
	for _, faction in pairs(ix.faction.indices) do
		for _, model in ipairs(faction.models or {}) do
			model = istable(model) and model[1] or model
			if (isstring(model) and util.IsValidModel(model)) then models[#models + 1] = model end
		end
	end
	local expected = {
		["ValveBiped.Bip01_Head1"] = {"head"}, ["ValveBiped.Bip01_Spine2"] = {"chest"},
		["ValveBiped.Bip01_Pelvis"] = {"waist"}, ["ValveBiped.Bip01_L_Hand"] = {"arms", -1},
		["ValveBiped.Bip01_R_Forearm"] = {"arms", 1}, ["ValveBiped.Bip01_L_Calf"] = {"legs", -1},
		["ValveBiped.Bip01_R_Foot"] = {"feet", 1}, ["ValveBiped.Bip01_L_Toe0"] = {"feet", -1}
	}
	for _, model in ipairs(models) do
		local ent = ents.Create("prop_dynamic")
		ent:SetModel(model)
		ent:Spawn()
		local map = ix.datapad.BoneMap(ent)
		if (!map) then
			fail(model .. " has no bone map")
		else
			local seen = {}
			for i = 0, map.count - 1 do
				if (!ix.body.IsRegion(map.region[i])) then fail(model .. " bone " .. map.name[i] .. " has no region") end
				seen[map.region[i] or ""] = true
			end
			for _, region in ipairs(ix.body.REGIONS) do
				if (!seen[region]) then fail(model .. " has no bone for " .. region) end
			end
			for name, want in pairs(expected) do
				local i = map.index[name]
				if (i) then
					lib.Expect(fail, model .. " " .. name, map.region[i], want[1])
					lib.Expect(fail, model .. " " .. name .. " side", map.side[i], want[2])
				end
			end
		end
		ent:Remove()
	end
end)

GWH.Check("datapad: a blow that lands at a place is kept on the bone it struck, region by region, until respawn", function(fail)
	local bot = GWH.Bot()
	local plugin = lib.Plugin("datapad", fail)
	if (!plugin) then return end
	lib.Scoped(function(defer)
		lib.ResetBot(bot)
		defer(function()
			bot:SetNetVar("datapadPoints", nil)
			bot:SetNetVar("datapadHit", nil)
		end)
		local group = HITGROUP_GENERIC
		lib.Replace(defer, FindMetaTable("Player"), "LastHitGroup", function() return group end)
		local function blow(hitGroup, kind, pos)
			group = hitGroup
			local dmg = DamageInfo()
			dmg:SetDamage(5)
			dmg:SetDamageType(kind)
			if (pos) then dmg:SetDamagePosition(pos) end
			plugin:PostEntityTakeDamage(bot, dmg, true)
		end
		local forearm = bot:LookupBone("ValveBiped.Bip01_L_Forearm")
		local hand = bot:LookupBone("ValveBiped.Bip01_L_Hand")
		if (!forearm or !hand) then return fail("the bot's model has no left forearm") end
		local mid = (bot:GetBonePosition(forearm) + bot:GetBonePosition(hand)) * 0.5
		blow(HITGROUP_LEFTARM, DMG_BULLET, mid)
		local points = bot:GetNetVar("datapadPoints") or {}
		lib.Expect(fail, "shot forearm is the struck bone", points.arms and points.arms.bone, "ValveBiped.Bip01_L_Forearm")
		if (points.arms) then
			local back = bot:GetBoneMatrix(forearm) * points.arms.at
			if (back:Distance(mid) > 0.5) then fail("the kept point is " .. back:Distance(mid) .. " units from the impact") end
		end
		blow(HITGROUP_GENERIC, DMG_FALL)
		points = bot:GetNetVar("datapadPoints") or {}
		lib.Expect(fail, "a fall leaves the feet without a point", points.feet, nil)
		lib.Expect(fail, "the arm's point outlasts a fall", points.arms != nil, true)
		lib.Expect(fail, "the body reading carries the points", ix.datapad.ReadBody(bot).points.arms != nil, true)
		blow(HITGROUP_CHEST, DMG_BULLET, bot:GetPos() + Vector(0, 0, 200))
		points = bot:GetNetVar("datapadPoints") or {}
		lib.Expect(fail, "an impact far from the body leaves no point", points.chest, nil)
		plugin:PlayerSpawn(bot)
		lib.Expect(fail, "respawn clears the points", bot:GetNetVar("datapadPoints"), nil)
	end)
end)

GWH.Check("datapad: old items, pocket placement and a tied reader", function(fail)
	local bot = GWH.Bot()
	lib.Scoped(function(defer)
		lib.ResetBot(bot)
		local char = bot:GetCharacter()
		local prefs = table.Copy(char:GetData("carryPrefs", {}))
		defer(function()
			bot:SetNetVar("restricted", nil)
			char:SetData("carryPrefs", prefs)
			lib.Fresh(bot)
		end)

		local inv = lib.Fresh(bot)
		local item = lib.GiveItem(inv, "bandage")
		item:SetData("carryPlace", "coatFromAnOldOutfit")
		local groups = ix.datapad.Layout(inv)
		lib.Expect(fail, "legacy item is visible", ix.datapad.Locate(groups, item.id) != nil, true)
		lib.Expect(fail, "move into boot", ix.datapad.Move(bot, item.id, "boot"), true)
		lib.Expect(fail, "location persisted", item:GetData("carryPlace"), "boot")
		lib.Expect(fail, "preferred aid location", char:GetData("carryPrefs")[item.category], "boot")
		local second = lib.GiveItem(inv, "health_vial")
		lib.Expect(fail, "full boot refuses second item", ix.datapad.Move(bot, second.id, "boot"), false)
		bot:SetNetVar("restricted", true)
		lib.Expect(fail, "tied player cannot take item out", ix.datapad.Move(bot, item.id, "hands"), nil)
		lib.Expect(fail, "boot still holds the item", item:GetData("carryPlace"), "boot")
	end)
end)

GWH.Check("datapad: a storage take merges only its own quantity and ends at close", function(fail)
	local bot = GWH.Bot()
	lib.Scoped(function(defer)
		lib.ResetBot(bot)
		local inv = lib.Fresh(bot)
		local crate = ix.inventory.Create(3, 3, 2100500001)
		local ent = ents.Create("prop_physics")
		ent:SetModel("models/props_junk/wood_crate001a.mdl")
		ent:SetPos(bot:GetPos() + Vector(45, 0, 0))
		ent:Spawn()
		defer(function()
			ix.storage.Close(crate)
			for _, item in pairs(crate:GetItems()) do item:Remove() end
			ix.item.inventories[crate:GetID()] = nil
			ent:Remove()
			lib.Fresh(bot)
		end)
		ix.stack.Give(inv, "metal_scrap", 1.5)
		ix.stack.Give(crate, "metal_scrap", 2.5)
		local stack = ix.stack.GetStacks(crate, "metal_scrap")[1]
		ix.storage.Open(bot, crate, {entity = ent, name = "Crate"})
		lib.Expect(fail, "merged into a partial stack", ix.datapad.Move(bot, stack.id, "auto"), true)
		lib.Expect(fail, "combined kilograms", ix.stack.Count(inv, "metal_scrap"), 4)
		lib.Expect(fail, "crate is empty", ix.stack.Count(crate, "metal_scrap"), 0)
		local item = lib.GiveItem(crate, "bandage")
		ix.storage.Close(crate, bot)
		lib.Expect(fail, "closed crate refuses another take", ix.datapad.Move(bot, item.id, "auto"), nil)
		lib.Expect(fail, "item still in crate", item.invID, crate:GetID())
	end)
end)

GWH.Check("datapad: stopping a frisk leaves the subject's inventory private", function(fail)
	local bot = GWH.Bot()
	lib.Scoped(function(defer)
		lib.ResetBot(bot)
		local subject = lib.OtherBot()
		local pos, restricted = subject:GetPos(), subject:GetNetVar("restricted")
		lib.ResetBot(subject)
		subject:SetPos(bot:GetPos() + Vector(36, 0, 0))
		subject:SetNetVar("restricted", true)
		defer(function()
			ix.datapad.EndFrisk(bot)
			subject:SetNetVar("restricted", restricted)
			subject:SetPos(pos)
		end)
		local inv = subject:GetCharacter():GetInventory()
		lib.Expect(fail, "a frisk begins in reach", ix.datapad.BeginFrisk(bot, subject), true)
		lib.Expect(fail, "no early access", inv:OnCheckAccess(bot), false)
		ix.datapad.EndFrisk(bot)
		lib.Expect(fail, "aborted search opened no storage", bot.ixOpenStorage, nil)
		subject:SetNetVar("restricted", nil)
		lib.Expect(fail, "free subject cannot be searched", ix.datapad.BeginFrisk(bot, subject), false)
	end)
end)
