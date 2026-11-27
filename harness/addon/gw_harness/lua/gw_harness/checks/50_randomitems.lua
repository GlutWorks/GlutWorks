-- Children and child dispensers (randomitems): opening a child gives its contents once, dispensers save and load
-- across a map cleanup, and one ration ID gets one child per interval.

local Lib = GWH.Lib
local Scoped, Replace, GiveItem, ItemEntities = Lib.Scoped, Lib.Replace, Lib.GiveItem, Lib.ItemEntities
local NewItemEntities = Lib.NewItemEntities

GWH.Check("hygiene: opening a child gives its contents once", function(fail)
	return Scoped(function(defer)
		local client = GWH.Bot()
		local inventory = client:GetCharacter():GetInventory()
		local child = GiveItem(inventory, "baby")
		local count = {meat_chunk = inventory:GetItemCount("meat_chunk"), infant_skull = inventory:GetItemCount("infant_skull")}

		defer(function()
			for item in inventory:Iter() do
				if (count[item.uniqueID] or item.uniqueID == "baby") then item:Remove() end
			end
		end)

		local id = child:GetID()
		ix.item.PerformInventoryAction(client, "Open", id, inventory:GetID())
		ix.item.PerformInventoryAction(client, "Open", id, inventory:GetID())

		for uniqueID, had in pairs(count) do
			local gained = inventory:GetItemCount(uniqueID) - had
			if (gained != 1) then fail("expected 1 " .. uniqueID .. ", got " .. gained) end
		end
	end)
end)

-- Entities removed earlier in this frame, by this or another check, are still findable.
local function Dispensers()
	local result = {}

	for _, v in ipairs(ents.FindByClass("ix_childdispenser")) do
		if (!v:IsMarkedForDeletion()) then result[#result + 1] = v end
	end

	return result
end

local function SavedDispensers()
	ix.data.stored.randomitems = nil
	return ix.plugin.list.randomitems:GetData()
end

GWH.Check("hygiene: child dispensers save and load", function(fail)
	return Scoped(function(defer)
		local plugin = ix.plugin.list.randomitems

		defer(function()
			plugin.bCleaningUp = true
			for _, v in ipairs(Dispensers()) do v:Remove() end
			plugin.bCleaningUp = false
			plugin:SetData({})
		end)

		for _, v in ipairs(Dispensers()) do v:Remove() end

		local scripted = scripted_ents.GetStored("ix_childdispenser").t
		local first = scripted:SpawnFunction(GWH.Bot(), {HitPos = Vector(100, 200, 300), HitNormal = Vector(1, 0, 0)})
		local second = scripted:SpawnFunction(GWH.Bot(), {HitPos = Vector(400, 200, 300), HitNormal = Vector(0, 1, 0)})
		second:SetEnabled(false)
		plugin:SaveData()

		if (#SavedDispensers() != 2) then return fail("expected 2 saved dispensers, got " .. #SavedDispensers()) end

		-- A map cleanup removes them after saving. Entities run OnRemove a frame after removal, so it is called here.
		plugin:PreCleanupMap()
		plugin:SetData({})
		first:OnRemove()

		if (#SavedDispensers() != 0) then fail("removal during a map cleanup wrote over the save") end

		plugin:SaveData()
		first:Remove()
		second:Remove()

		plugin:LoadData()
		local loaded = Dispensers()
		if (#loaded != 2) then return fail("expected 2 loaded dispensers, got " .. #loaded) end

		table.sort(loaded, function(a, b) return a:GetPos().x < b:GetPos().x end)

		if (loaded[1]:GetPos():Distance(Vector(100, 200, 300)) > 1) then fail("position was not restored") end
		if (math.abs(math.AngleDifference(loaded[2]:GetAngles().y, 90)) > 1) then fail("angles were not restored") end
		if (loaded[1]:GetEnabled() != true or loaded[2]:GetEnabled() != false) then fail("enabled state was not restored") end

		plugin:SetData({})
		loaded[1]:OnRemove()
		if (#SavedDispensers() == 0) then fail("removing a dispenser by hand does not update the save") end
	end)
end)

GWH.Check("hygiene: one ration ID gets one child per interval", function(fail)
	return Scoped(function(defer)
		local client = GWH.Bot()
		local inventory = client:GetCharacter():GetInventory()
		local plugin = ix.plugin.list.randomitems
		local team = client:Team()
		client:SetTeam(FACTION_CITIZEN)

		local cid = inventory:HasItem("cid")
		local given = !cid
		cid = cid or GiveItem(inventory, "cid")
		local nextRationTime = cid:GetData("nextRationTime")
		cid:SetData("nextRationTime", nil)

		local before = ItemEntities()
		local dispensers = {}

		defer(function()
			client:SetTeam(team)
			cid:SetData("nextRationTime", nextRationTime)
			if (given) then cid:Remove() end

			for _, v in ipairs(NewItemEntities(before)) do v:Remove() end

			plugin.bCleaningUp = true
			for _, v in ipairs(dispensers) do v:Remove() end
			plugin.bCleaningUp = false
			plugin:SetData({})
		end)

		for i = 1, 2 do
			local dispenser = ents.Create("ix_childdispenser")
			dispenser:SetPos(Vector(i * 200, 0, 300))
			dispenser:Spawn()
			dispensers[i] = dispenser
		end

		-- run the dispenser's delays by hand
		local queue = {}
		Replace(defer, timer, "Simple", function(delay, callback) queue[#queue + 1] = callback end)

		dispensers[1]:Use(client)
		table.remove(queue, 1)() -- ID check passes; the dispenser starts preparing
		dispensers[2]:Use(client)
		table.remove(queue)() -- the second ID check happens before the first dispenser has finished

		local steps = 0

		while (queue[1] and steps < 50) do
			table.remove(queue, 1)()
			steps = steps + 1
		end

		local children = 0

		for _, v in ipairs(NewItemEntities(before)) do
			if (v:GetItemID() == "baby") then children = children + 1 end
		end

		if (children != 1) then fail("expected 1 child from two dispensers, got " .. children) end
	end)
end)
