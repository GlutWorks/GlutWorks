-- Exercise the same actions as the held tools, including attachment to custom collision geometry.
local Lib = GWH.Lib
GWH.Check("fieldworks: cut angled stock, attach, restore, reclaim and place a bench", function()
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
			return Lib.Live("ix_build_stock")
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
		local start = game.GetMap() == "gm_construct" and Vector(75, 0, -75) or bot:GetPos() + Vector(140, 180, 80)
		local ground = util.TraceLine({start = start, endpos = start - Vector(0, 0, 512), mask = MASK_SOLID_BRUSHONLY}).HitPos
		local function coords(v) return {x = v.x, y = v.y, z = v.z} end
		local function act(kind, pos, from, step, target, mode, edge, width, cost)
			bot:SetPos(from)
			local item = kind == "workbench" and kit or tools
			local data = coords(pos)
			data.kind, data.step, data.yaw = kind, step or 0, 0
			data.target = IsValid(target) and target:EntIndex() or 0
			if (edge) then data.edge, data.width, data.mode, data.cost = coords(edge), coords(width), mode, cost end
			return ix.item.PerformInventoryAction(bot, kind == "workbench" and "place" or "build", item.id, item.invID, data)
		end
		local stand = ground - Vector(65, 20, 0)
		local wood = ix.stack.Count(inv, "wooden_scrap")
		local metal = ix.stack.Count(inv, "metal_scrap")
		local along, side = Vector(0.8, 0.6, 0), Vector(-0.6, 0.8, 0)
		local b, c = ground + along * 74, ground + side * 26
		local function deck(cost)
			return act("timber", ground, stand, 0, nil, "surface", b, c, cost)
		end
		deck(0.1)
		assert(#live() == 0 and ix.stack.Count(inv, "wooden_scrap") == wood, "charged a different price than quoted")
		local feedback = Lib.NewS().Notices(bot, function() deck(0.7) end)
		local floor = live()[1]
		assert(floor and floor:GetSize():Distance(Vector(74, 26, 5)) < 0.1, "custom deck missing: " .. table.concat(feedback, ", "))
		assert(math.abs(floor:GetForward():Dot(along)) > 0.999, "deck was rotated onto a grid")
		assert(math.abs(ix.stack.Count(inv, "wooden_scrap") - (wood - 0.7)) < 0.001)
		deck(0.7)
		assert(#live() == 1 and math.abs(ix.stack.Count(inv, "wooden_scrap") - (wood - 0.7)) < 0.001, "overlap spent scrap")

		local anchor = ground + along * 8 + side * 8 + Vector(0, 0, 5)
		local anchorTrace = util.TraceLine({start = anchor + Vector(0, 0, 20), endpos = anchor - Vector(0, 0, 2)})
		assert(anchorTrace.Entity == floor, "custom collision did not match the deck")
		local function attach()
			act("sheet", anchor, stand, 0, floor, "upright", anchor + Vector(0, 0, 63), anchor + Vector(0, 13, 7), 0.2)
		end
		feedback = Lib.NewS().Notices(bot, attach)
		local panel
		for _, ent in ipairs(live()) do if (ent:GetStock() == "sheet") then panel = ent end end
		assert(panel and panel:GetSize():Distance(Vector(63, 13, 3)) < 0.1, "attached cut failed: " .. table.concat(feedback, ", "))
		assert(plugin:SupportsCut(floor) and !floor:CanRecover(Lib.OtherBot()))
		floor:OnOptionSelected(bot, "", "recover")
		assert(!floor:IsMarkedForDeletion(), "recovered an occupied support")
		local ramp = assert(plugin:CutPose("timber", ground, b + Vector(0, 0, 30), c, vector_up, nil))
		assert(ramp.ang:Forward().z > 0.3 and ramp.ang:Up().z > 0.8, "span flattened an inclined cut")

		local oldID, oldPos = floor.fieldID, panel:GetPos()
		for _, ent in ipairs(live()) do ent:Remove() end
		saved[#saved + 1] = {kind = "frame", foot = ground + Vector(0, 300, 0), turn = 1, owner = bot:GetCharacter():GetID()}
		plugin:LoadData()
		local legacy = Lib.Live("ix_fieldpiece")[1]
		assert(legacy and legacy:GetKind() == "frame", "old frame did not restore")
		defer(function() legacy:Remove() end)
		for _, ent in ipairs(live()) do
			if (ent.fieldID == oldID) then floor = ent else panel = ent end
		end
		assert(#live() == 2 and panel:GetPos():Distance(oldPos) < 0.1 and plugin:SupportsCut(floor), "lost dimensions or attachments on restore")
		bot:SetPos(stand + Vector(22, 0, 0))
		panel:OnOptionSelected(bot, "", "recover")
		panel:OnOptionSelected(bot, "", "recover")
		floor:OnOptionSelected(bot, "", "recover")
		assert(#live() == 0 and ix.stack.Count(inv, "wooden_scrap") == wood and ix.stack.Count(inv, "metal_scrap") == metal,
			"recovery did not return the original charge exactly once")

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
	end)
end)
