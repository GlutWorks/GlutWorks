-- A surveyed bay must open for players, retain its sections and use the ordinary owned workbench.
local Lib = GWH.Lib

GWH.Check("fieldworks: excavate a bay, raise shelter and assemble a real bench", function()
	Lib.Scoped(function(defer)
		local plugin = ix.plugin.list.fieldworks
		local bot = GWH.Bot()
		Lib.ResetBotFully(bot)
		local inventory = bot:GetCharacter():GetInventory()
		local before = bot:GetPos()
		local saved
		Lib.Replace(defer, plugin, "SetData", function(_, data) saved = data end)
		Lib.Replace(defer, plugin, "GetData", function() return saved end)
		defer(function() bot:SetPos(before) end)
		-- gm_construct's level grass, away from spawn and the other content checks.
		local origin = Vector(850, 320, -143.96875)
		bot:SetPos(origin - Vector(50, 0, 0))
		local site, why = plugin:Survey(origin, 0, true)
		assert(IsValid(site), why)
		defer(function() if (IsValid(site)) then site:Remove() end end)
		assert(!plugin:Survey(origin, 0, false), "surveyed the same space twice")
		assert(!site:CanBuild("left"), "could build before excavating")

		local function PassageBlocked(x)
			local start = origin + Vector(x, 48, 4)
			return util.TraceHull({start = start, endpos = start + Vector(48, 0, 0),
				mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), filter = bot, mask = MASK_PLAYERSOLID}).Hit
		end
		assert(PassageBlocked(4), "a standing player could already enter the packed rock")
		local rocks = {}
		for _, rock in ipairs(ents.FindByClass("ix_fieldpiece")) do
			if (rock.fieldSite == site) then rocks[rock.sectionFlag] = rock end
		end
		for _, flag in ipairs({16, 32}) do
			local rock = rocks[flag]
			bot:SetPos(rock:GetPos() - Vector(80, 0, 48))
			local hit = DamageInfo()
			hit:SetAttacker(bot)
			hit:SetInflictor(bot)
			hit:SetDamage(10)
			hit:SetDamageType(DMG_CLUB)
			for i = 1, 3 do rock:TakeDamageInfo(hit) end
			assert(!site:HasSection(flag), "rock did not clear")
		end
		assert(!PassageBlocked(4) and !PassageBlocked(100), "a mined section still blocks player movement")

		bot:SetPos(origin - Vector(42, 0, 0))
		assert(!site:CanBuild("roof"), "roof available without supports")
		for id, amount in pairs({wooden_scrap = 5, metal_scrap = 10}) do
			assert(ix.stack.Give(inventory, id, amount))
			defer(function() Lib.RemoveAll(inventory, id) end)
		end
		local wood = ix.stack.Count(inventory, "wooden_scrap")
		for _, key in ipairs({"left", "left", "right", "back", "roof"}) do
			site:OnOptionSelected(bot, "", key)
		end
		assert(site:GetSections() == 15, "some shelter sections missing: " .. site:GetSections())
		assert(ix.stack.Count(inventory, "wooden_scrap") == wood - 5, "wall materials charged incorrectly")
		local inside = origin + Vector(100, 48, 65)
		local above = util.TraceLine({start = inside, endpos = inside + Vector(0, 0, 60), mask = MASK_SOLID})
		assert(IsValid(above.Entity) and above.Entity.sectionFlag == 8, "roof does not cover the bay")

		local metal = ix.stack.Count(inventory, "metal_scrap")
		site:OnOptionSelected(bot, "", "bench")
		site:OnOptionSelected(bot, "", "bench")
		assert(ix.stack.Count(inventory, "metal_scrap") == metal - 4, "bench cost, or blocked placement charged again")
		local bench
		for _, entity in ipairs(Lib.Live("ix_station_workbench")) do
			if (entity:GetPos():DistToSqr(origin + Vector(180, 48, 0)) < 16 * 16) then bench = entity end
		end
		assert(IsValid(bench) and bench:IsBench() and bench:CanPickUp(bot), "missing owned crafting station")
		defer(function() bench:Remove() end)

		site:Remove()
		plugin:LoadData()
		local restored
		for _, candidate in ipairs(Lib.Live("ix_fieldsite")) do
			if (candidate:GetPos():Distance(origin) < 21) then restored = candidate end
		end
		assert(IsValid(restored), "site missing after restore")
		defer(function() restored:Remove() end)
		assert(restored:GetSections() == 15, "site progress changed on restore")
		local count = 0
		for _, child in ipairs(ents.FindByClass("ix_fieldpiece")) do
			if (child.fieldSite == restored) then count = count + 1 end
		end
		assert(count == 4, "restore duplicated rock or lost a shelter section")
	end)
end)
