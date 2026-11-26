-- Generic checks: the framework, schema and every plugin loaded, and all Lua parses.

GWH.Check("framework loaded", function(fail)
	if (!ix) then return fail("global `ix` is missing: helix did not load") end
	if (!Schema) then return fail("global `Schema` is missing: the schema did not load") end

	if (engine.ActiveGamemode() != (GWH.cfg.gamemode or "ixhl2rp")) then
		fail("active gamemode is " .. engine.ActiveGamemode())
	end

	return {
		schema = Schema.name,
		factions = table.Count(ix.faction.indices),
		classes = table.Count(ix.class.list),
		items = table.Count(ix.item.list),
		itemBases = table.Count(ix.item.base),
		commands = table.Count(ix.command.list),
		plugins = table.Count(ix.plugin.list)
	}
end)

GWH.Check("plugins on disk are loaded", function(fail)
	local loaded = ix.plugin.list
	local missing = {}

	for _, root in ipairs({"helix", engine.ActiveGamemode()}) do
		local files, folders = file.Find("gamemodes/" .. root .. "/plugins/*", "GAME")

		for _, v in ipairs(folders or {}) do
			if (!loaded[v] and !ix.plugin.unloaded[v]) then missing[#missing + 1] = root .. "/plugins/" .. v end
		end

		for _, v in ipairs(files or {}) do
			local id = string.StripExtension(v)

			if (string.GetExtensionFromFilename(v) == "lua" and !loaded[id] and !ix.plugin.unloaded[id]) then
				missing[#missing + 1] = root .. "/plugins/" .. v
			end
		end
	end

	for _, v in ipairs(missing) do fail("not loaded: " .. v) end
end)

-- The server never compiles cl_*.lua, so a syntax error there would only show up on a
-- client. Compiling every file here catches those without needing one.
GWH.Check("all gamemode lua compiles", function(fail)
	local count = 0

	local function Walk(dir)
		local files, folders = file.Find(dir .. "/*", "GAME")

		for _, v in ipairs(files or {}) do
			if (string.GetExtensionFromFilename(v) == "lua") then
				local path = dir .. "/" .. v
				local result = CompileString(file.Read(path, "GAME") or "", path, false)
				count = count + 1

				if (isstring(result)) then fail(result) end
			end
		end

		for _, v in ipairs(folders or {}) do Walk(dir .. "/" .. v) end
	end

	for _, root in ipairs(GWH.cfg.roots or {"helix", "ixhl2rp"}) do
		Walk("gamemodes/" .. root)
	end

	return {files = count}
end)
