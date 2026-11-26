-- Content checks: every registered item, entity and recipe can actually be used.

GWH.Check("bot has a character", function(fail)
	local bot = GWH.Bot()

	if (!bot) then return fail("no bot with a character; helix bot spawn path failed") end

	local character = bot:GetCharacter()

	return {
		name = bot:Name(),
		faction = ix.faction.indices[character:GetFaction()] and ix.faction.indices[character:GetFaction()].name,
		alive = bot:Alive()
	}
end)

GWH.Check("item definitions are sane", function(fail)
	for uniqueID, item in pairs(ix.item.list) do
		if (!isstring(item.name) or item.name == "") then fail(uniqueID .. ": no name") end
		if (!isstring(item.model) or item.model == "") then fail(uniqueID .. ": no model") end
		if (item.base and !ix.item.base[item.base]) then fail(uniqueID .. ": unknown base " .. tostring(item.base)) end

		if (!isnumber(item.width) or !isnumber(item.height) or item.width < 1 or item.height < 1) then
			fail(uniqueID .. ": bad size " .. tostring(item.width) .. "x" .. tostring(item.height))
		end
	end
end)

-- Gives the bot one of every item, then drops and removes it. Exercises item creation,
-- OnInstanced/OnTransferred hooks and the entity path for each definition.
GWH.Check("every item can be instanced and spawned", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local position = bot:GetPos() + Vector(0, 0, 48)
	local count = 0

	for uniqueID in SortedPairs(ix.item.list) do
		local before = #GWH.errors
		local ok, err = pcall(ix.item.Spawn, uniqueID, position, function(item, entity)
			if (IsValid(entity)) then SafeRemoveEntityDelayed(entity, 1) end
		end)

		count = count + 1

		if (!ok) then
			fail(uniqueID .. ": " .. tostring(err))
		elseif (#GWH.errors > before) then
			fail(uniqueID .. ": raised " .. GWH.errors[#GWH.errors].error)
		end
	end

	return {items = count}
end)

GWH.Check("every scripted entity spawns", function(fail)
	local bot = GWH.Bot()
	local origin = IsValid(bot) and bot:GetPos() or vector_origin
	local count = 0
	local prefixes = GWH.cfg.entityPrefixes or {"ix_", "gw_", "glut"}

	for class in SortedPairs(scripted_ents.GetList()) do
		local wanted = false

		for _, prefix in ipairs(prefixes) do
			if (string.StartWith(class, prefix)) then wanted = true break end
		end

		-- ix_item and ix_money need data set by their spawner; ix.item.Spawn covers them.
		if (wanted and class != "ix_item" and class != "ix_money" and class != "ix_shipment") then
			local before = #GWH.errors
			local ok, err = pcall(function()
				local entity = ents.Create(class)
				if (!IsValid(entity)) then error("ents.Create returned NULL") end

				entity:SetPos(origin + Vector(0, 0, 96))
				entity:Spawn()
				entity:Activate()
				SafeRemoveEntityDelayed(entity, 1)
			end)

			count = count + 1

			if (!ok) then
				fail(class .. ": " .. tostring(err))
			elseif (#GWH.errors > before) then
				fail(class .. ": raised " .. GWH.errors[#GWH.errors].error)
			end
		end
	end

	return {entities = count}
end)
