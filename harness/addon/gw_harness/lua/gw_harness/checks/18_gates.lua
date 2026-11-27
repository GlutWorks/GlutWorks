-- Gates (ix.item.CanInteract and ix.menu.CanInteract, our changes to Helix in UPSTREAM.md): the limits every item
-- action and entity menu choice needs are the core's, checked before CanPlayerInteractItem and
-- CanPlayerInteractEntity, so something returning true from those hooks can't lift them. Each check adds such a
-- hook and sends what a client would, through the receivers a real client reaches.

local Lib = GWH.Lib
local Scoped, ReceiveReads, Expect = Lib.Scoped, Lib.ReceiveReads, Lib.Expect
local ResetBotFully, RemoveAll = Lib.ResetBotFully, Lib.RemoveAll
local S = Lib.NewS()

-- A hook that says yes to everything, removed when the check ends.
local function AllowAll(defer, name)
	hook.Add(name, "gwh_allow_all", function() return true end)
	defer(function() hook.Remove(name, "gwh_allow_all") end)
end

GWH.Check("gates: a hook saying yes can't let a tied or dead player use an item", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = bot:GetCharacter():GetInventory()

	Scoped(function(defer)
		defer(function() ResetBotFully(bot) RemoveAll(inventory, "water") end)
		AllowAll(defer, "CanPlayerInteractItem")

		for _, state in ipairs({"tied", "dead"}) do
			ResetBotFully(bot)
			RemoveAll(inventory, "water")
			inventory:Add("water")

			local water = inventory:HasItem("water")

			if (state == "tied") then
				-- SetRestricted keeps the weapons it removes, and removal takes effect at the end of the tick; untied
				-- in the same tick (the next ResetBotFully), Give would hand back weapons the bot still has
				bot:StripWeapons()
				bot:SetRestricted(true)
			else
				bot:Kill()
			end

			Expect(fail, "CanInteract for a " .. state .. " player", ix.item.CanInteract(bot, "Drink", water:GetID()), false)

			bot.ixItemNetTokens = nil
			ReceiveReads("ixInventoryAction", bot, {
				ReadString = {"Drink"}, ReadUInt = {water:GetID(), inventory:GetID()}, ReadTable = {{}}
			})

			if (!inventory:GetItemByID(water:GetID())) then
				fail("a " .. state .. " player drank, with a hook saying yes")
			end
		end
	end)
end)

GWH.Check("gates: a hook saying yes can't let a player choose a menu option from across the map", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBotFully(bot)
		AllowAll(defer, "CanPlayerInteractEntity")

		local chosen = 0
		local prop = ents.Create("prop_physics")
		prop:SetModel("models/props_junk/wood_crate001a.mdl")
		prop:SetPos(bot:GetPos() + Vector(0, 300, 0))
		prop:Spawn()
		prop.OnSelecttest = function() chosen = chosen + 1 end
		defer(function() prop:Remove() end)

		Expect(fail, "CanInteract 300 units away", ix.menu.CanInteract(bot, prop, "test", {}), false)

		S.Net("ixEntityMenuSelect", bot, {prop, "test", {}})
		Expect(fail, "options chosen from 300 units away", chosen, 0)

		-- and from beside it, the same choice goes through
		prop:SetPos(bot:GetShootPos() + bot:GetAimVector() * 40)
		S.Net("ixEntityMenuSelect", bot, {prop, "test", {}})
		Expect(fail, "options chosen from beside it", chosen, 1)
	end)
end)

GWH.Check("gates: a large entity is reached at its surface, not its origin", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBotFully(bot)

		-- a long container: its origin is far from the bot, its near end isn't
		local prop = ents.Create("prop_physics")
		prop:SetModel("models/props_wasteland/cargo_container01.mdl")
		prop:Spawn()
		defer(function() prop:Remove() end)

		local mins, maxs = prop:OBBMins(), prop:OBBMaxs()
		prop:SetPos(bot:GetShootPos() + Vector(-mins.x + 60, 0, 0) - Vector(0, 0, (mins.z + maxs.z) / 2))

		local eyes = bot:GetShootPos()
		local origin = math.Round(eyes:Distance(prop:GetPos()))
		local surface = math.Round(eyes:Distance(prop:NearestPoint(eyes)))

		if (origin <= ix.menu.reach) then
			return fail("the container's origin is only " .. origin .. " units away; the check needs it further")
		end

		Expect(fail, "CanInteract " .. surface .. " units from its surface, " .. origin .. " from its origin",
			ix.menu.CanInteract(bot, prop, "test", {}), true)

		return {origin = origin, surface = surface}
	end)
end)
