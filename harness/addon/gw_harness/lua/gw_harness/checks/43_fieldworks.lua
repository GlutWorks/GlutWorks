-- Ordinary carried-item actions build on chosen ground. Check material accounting, different
-- joints, an open doorway, weather cover, reversible edits, persistence and kit ownership.
local Lib = GWH.Lib
GWH.Check("fieldworks: handcraft, snap, clad, shelter, salvage and place a bench", function()
	Lib.Scoped(function(defer)
		local plugin = ix.plugin.list.fieldworks
		assert(plugin, "fieldworks is unavailable")
		local bot = GWH.Bot()
		Lib.ResetBotFully(bot)
		local old = bot:GetPos()
		defer(function() bot:SetPos(old) end)
		local inv = bot:GetCharacter():GetInventory()
		local saved
		Lib.Replace(defer, plugin, "SetData", function(_, data) saved = data end)
		Lib.Replace(defer, plugin, "GetData", function() return saved end)
		local function live()
			return Lib.Live("ix_fieldpiece")
		end
		defer(function() for _, e in ipairs(live()) do e:Remove() end end)
		for _, id in ipairs({"wooden_scrap", "metal_scrap"}) do
			local before = ix.stack.Count(inv, id)
			defer(function()
				local extra = ix.stack.Count(inv, id) - before
				if (extra > 0) then ix.stack.Take(inv, id, extra) end
				if (extra < 0) then ix.stack.Give(inv, id, -extra) end
			end)
			assert(ix.stack.Give(inv, id, 12))
		end
		local craft = ix.plugin.list.ixcraft.craft
		local scrap = inv:GetItemsByUniqueID("metal_scrap")[1]
		ix.item.PerformInventoryAction(bot, "handTools", scrap.id, scrap.invID)
		local tools = inv:GetItemsByUniqueID("carpentry_tools")[1]
		assert(tools, "metal scrap did not craft tools")
		defer(function() if (ix.item.instances[tools.id]) then tools:Remove() end end)
		assert(craft.CraftRecipe(bot, "pack_workbench"), "hand tools could not make first bench")
		local kit = inv:GetItemsByUniqueID("workbench")[1]
		assert(kit, "kit did not arrive")

		Lib.StandOnSpawn(bot)
		local start = bot:GetPos() + Vector(140, 180, 80)
		local ground = util.TraceLine({start = start, endpos = start - Vector(0, 0, 512), mask = MASK_SOLID_BRUSHONLY}).HitPos
		local function act(kind, pos, from, step, target)
			bot:SetPos(from)
			local item = kind == "workbench" and kit or tools
			return ix.item.PerformInventoryAction(bot, kind == "workbench" and "place" or "build", item.id, item.invID,
				{kind = kind, x = pos.x, y = pos.y, z = pos.z, target = IsValid(target) and target:EntIndex() or 0, step = step or 0})
		end
		local stand = ground - Vector(65, 20, 0)
		local function part(kind, where)
			for _, entity in ipairs(live()) do
				if (entity:GetKind() == kind and entity:GetFoot():Distance(where) < 3) then return entity end
			end
		end
		local wood = ix.stack.Count(inv, "wooden_scrap")
		act("frame", ground, stand)
		local frame = part("frame", ground)
		assert(frame, "missing free-standing frame")
		assert(ix.stack.Count(inv, "wooden_scrap") == wood - 1)
		local function doorway()
			return util.TraceHull({start = ground + Vector(-32, 0, 0.1), endpos = ground + Vector(32, 0, 0.1),
				mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_PLAYERSOLID, filter = bot}).Hit
		end
		assert(!doorway(), "open frame blocks a standing player")
		local post = ground + Vector(-3, 44, 60)
		act("frame", post, stand, 1, frame)
		assert(part("frame", ground + Vector(48, 48, 0)), "corner did not snap")
		act("frame", post, stand, 3, frame)
		local opposite = part("frame", ground + Vector(96, 0, 0))
		assert(opposite, "parallel support did not snap")
		act("boards", post, stand, 0, frame)
		assert(frame:GetKind() == "boards" and doorway(), "cladding did not close the doorway")
		bot:SetPos(stand)
		local neighbor = Lib.OtherBot()
		assert(!frame:CanSalvage(neighbor), "another character could reclaim the builder's wall")
		frame:OnOptionSelected(bot, "", "salvage_boards")
		frame:OnOptionSelected(bot, "", "salvage_boards") -- stale selection after the boards came off
		assert(!frame:IsMarkedForDeletion(), "a stale cladding choice dismantled the open frame")
		assert(frame:GetKind() == "frame" and !doorway(), "removing cladding did not reopen doorway")
		act("roof", post, stand, 0, frame)
		local roof = part("roof", ground + Vector(48, 0, 0))
		assert(roof and plugin:HoldsRoof(frame), "roof or support missing")
		local head = ground + Vector(48, 0, 64)
		assert(util.TraceLine({start = head, endpos = head + Vector(0, 0, 64)}).Entity == roof)
		frame:OnOptionSelected(bot, "", "salvage_frame")
		assert(!frame:IsMarkedForDeletion(), "removed an occupied support")
		local metal = ix.stack.Count(inv, "metal_scrap")
		act("roof", post, stand, 0, frame)
		assert(ix.stack.Count(inv, "metal_scrap") == metal, "duplicate roof cost material")
		act("workbench", ground, ground + Vector(330, 0, 0), 1)
		assert(inv:GetItemByID(kit.id), "lost an out-of-reach kit")
		local spot = ground + Vector(48, -115, 0)
		act("workbench", spot, spot - Vector(60, 0, 0), 1)
		assert(!inv:GetItemByID(kit.id), "successful placement kept kit")
		local bench
		for _, entity in ipairs(Lib.Live("ix_station_workbench")) do
			if (entity:GetPos():Distance(spot) < 10) then bench = entity end
		end
		assert(bench and bench:IsBench() and bench:CanPickUp(bot) and math.abs(bench:GetAngles().y - 90) < 1)
		defer(function() bench:Remove() end)
		local count = #live()
		for _, entity in ipairs(live()) do entity:Remove() end
		plugin:LoadData()
		assert(#live() == count and part("roof", roof:GetFoot()), "layout did not survive restore")
	end)
end)
