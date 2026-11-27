-- Admin tools (admincontext, bodygroupmanager, spawnmenu_itemtab): the context menu properties, the bodygroup
-- editor and the spawn menu's item tab check the sender's permission and the target.

local Lib = GWH.Lib
local OtherBot, Scoped, Receive = Lib.OtherBot, Lib.Scoped, Lib.Receive
local NewCharacter, Switch, ItemEntities = Lib.NewCharacter, Lib.Switch, Lib.ItemEntities
local NewItemEntities = Lib.NewItemEntities

local function MakeAdmin(defer, client)
	local group = client:GetUserGroup()
	client:SetUserGroup("superadmin")
	defer(function() client:SetUserGroup(group) end)
end

GWH.Check("hygiene: admin context receivers check permission and target", function(fail)
	return Scoped(function(defer)
		local sender, target = GWH.Bot(), OtherBot()
		local character = target:GetCharacter()
		local description = character:GetDescription()
		defer(function() character:SetDescription(description) end)

		local prop = ents.Create("prop_physics")
		prop:SetModel("models/props_junk/watermelon01.mdl")
		prop:Spawn()
		prop:SetHealth(7)
		defer(function() prop:Remove() end)

		local function Run(name, entity, value)
			local property = properties.List[name]
			Receive(function(length, client) property:Receive(length, client) end, sender, {entity, value})
		end

		local names = {"ixviewplayerproperty", "ixsethealthproperty", "ixsetarmorproperty", "ixsetdescriptionproperty"}

		target:Spawn()
		target:SetHealth(80)
		target:SetArmor(5)
		sender.ixStrReqs = {}

		for _, name in ipairs(names) do Run(name, target, 25) end

		if (target:Health() != 80) then fail("a non-admin changed health") end
		if (target:Armor() != 5) then fail("a non-admin changed armor") end
		if (!table.IsEmpty(sender.ixStrReqs)) then fail("a non-admin was asked for a new description") end

		MakeAdmin(defer, sender)

		for _, name in ipairs(names) do
			Run(name, prop, 25)
			Run(name, NULL, 25)
			Run(name, game.GetWorld(), 25)
		end

		if (prop:Health() != 7) then fail("a prop's health was changed") end
		if (!table.IsEmpty(sender.ixStrReqs)) then fail("a description was requested for a non-player") end

		Run("ixviewplayerproperty", target)
		Run("ixsethealthproperty", target, 25)
		Run("ixsetarmorproperty", target, 255)
		if (target:Health() != 25) then fail("an admin could not set health") end
		if (target:Armor() != 100) then fail("armor was not capped at 100, got " .. target:Armor()) end

		Run("ixsetdescriptionproperty", target)
		local _, callback = next(sender.ixStrReqs)
		if (!callback) then return fail("an admin was not asked for a description") end

		callback("short")
		if (character:GetDescription() != description) then fail("an invalid description was accepted") end

		callback("A person of entirely unremarkable appearance.")
		if (character:GetDescription() != "A person of entirely unremarkable appearance.") then
			fail("an admin could not set a description")
		end

		defer(function() Switch(target, character) end)
		Switch(target, NewCharacter(target))
		callback("This arrives after the target changed character.")
		if (character:GetDescription() != "A person of entirely unremarkable appearance.") then
			fail("a description was applied after the target switched character")
		end
	end)
end)

GWH.Check("hygiene: bodygroup and item spawn receivers", function(fail)
	return Scoped(function(defer)
		local sender, target = GWH.Bot(), OtherBot()
		local character = target:GetCharacter()
		local groups = character:GetData("groups")
		defer(function() character:SetData("groups", groups) end)
		character:SetData("groups", nil)

		local setGroups = net.Receivers.ixbodygrouptableset
		local spawnItem = net.Receivers.spawnmenuspawnitem
		local before = ItemEntities()
		defer(function()
			for _, v in ipairs(NewItemEntities(before)) do v:Remove() end
		end)

		Receive(setGroups, sender, {target, {[0] = 0}})
		if (character:GetData("groups") != nil) then fail("a non-admin saved bodygroups") end

		Receive(spawnItem, sender, {"paper"})
		if (#NewItemEntities(before) != 0) then fail("a non-admin spawned an item") end

		MakeAdmin(defer, sender)

		Receive(setGroups, sender, {target, {[0] = 0, [200] = 1, [-1] = 0, [0.5] = 0, junk = "junk"}})
		local saved = character:GetData("groups") or {}
		if (table.Count(saved) != 1 or saved[0] != 0) then
			fail("expected only the real bodygroup to be saved, got " .. util.TableToJSON(saved))
		end
		Receive(setGroups, sender, {game.GetWorld(), {}})

		Receive(spawnItem, sender, {"no_such_item"})
		if (#NewItemEntities(before) != 0) then fail("an unknown item id spawned something") end

		Receive(spawnItem, sender, {"paper"})
		if (#NewItemEntities(before) != 1) then fail("an admin could not spawn an item") end
	end)
end)
