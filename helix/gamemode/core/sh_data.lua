
--- Helper library for reading/writing files to the data folder.
-- @module ix.data

ix.data = ix.data or {}
ix.data.stored = ix.data.stored or {}

-- Create a folder to store data in.
file.CreateDir("helix")

--- Populates a file in the `data/helix` folder with some serialized data.
-- @realm shared
-- @string key Name of the file to save
-- @param value Some sort of data to save
-- @bool[opt=false] bGlobal Whether or not to write directly to the `data/helix` folder, or the `data/helix/schema` folder,
-- where `schema` is the name of the current schema.
-- @bool[opt=false] bIgnoreMap Whether or not to ignore the map and save in the schema folder, rather than
-- `data/helix/schema/map`, where `map` is the name of the current map.
function ix.data.Set(key, value, bGlobal, bIgnoreMap)
	-- Get the base path to write to.
	local path = "helix/" .. (bGlobal and "" or Schema.folder .. "/") .. (bIgnoreMap and "" or game.GetMap() .. "/")

	-- Create the schema folder if the data is not global.
	if (!bGlobal) then
		file.CreateDir("helix/" .. Schema.folder .. "/")
	end

	-- If we're not ignoring the map, create a folder for the map.
	file.CreateDir(path)
	-- Write the data using JSON encoding.
	file.Write(path .. key .. ".txt", util.TableToJSON({value}))

	-- Cache the data value here.
	ix.data.stored[key] = value

	return path
end

--- Retrieves the contents of a saved file in the `data/helix` folder.
-- @realm shared
-- @string key Name of the file to load
-- @param default Value to return if the file could not be loaded successfully
-- @bool[opt=false] bGlobal Whether or not the data is in the `data/helix` folder, or the `data/helix/schema` folder,
-- where `schema` is the name of the current schema.
-- @bool[opt=false] bIgnoreMap Whether or not to ignore the map and load from the schema folder, rather than
-- `data/helix/schema/map`, where `map` is the name of the current map.
-- @bool[opt=false] bRefresh Whether or not to skip the cache and forcefully load from disk.
-- @return Value associated with the key, or the default that was given if it doesn't exists
function ix.data.Get(key, default, bGlobal, bIgnoreMap, bRefresh)
	-- If it exists in the cache, return the cached value so it is faster.
	if (!bRefresh) then
		local stored = ix.data.stored[key]

		if (stored != nil) then
			return stored
		end
	end

	-- Get the path to read from.
	local path = "helix/" .. (bGlobal and "" or Schema.folder .. "/") .. (bIgnoreMap and "" or game.GetMap() .. "/")
	-- Read the data from a local file.
	local contents = file.Read(path .. key .. ".txt", "DATA")

	if (contents and contents != "") then
		local status, decoded = pcall(util.JSONToTable, contents)

		if (status and decoded) then
			local value = decoded[1]

			if (value != nil) then
				return value
			end
		end

		-- Backwards compatibility.
		-- This may be removed in the future.
		status, decoded = pcall(pon.decode, contents)

		if (status and decoded) then
			local value = decoded[1]

			if (value != nil) then
				return value
			end
		end
	end

	return default
end

--- Deletes the contents of a saved file in the `data/helix` folder.
-- @realm shared
-- @string key Name of the file to delete
-- @bool[opt=false] bGlobal Whether or not the data is in the `data/helix` folder, or the `data/helix/schema` folder,
-- where `schema` is the name of the current schema.
-- @bool[opt=false] bIgnoreMap Whether or not to ignore the map and delete from the schema folder, rather than
-- `data/helix/schema/map`, where `map` is the name of the current map.
-- @treturn bool Whether or not the deletion has succeeded
function ix.data.Delete(key, bGlobal, bIgnoreMap)
	-- Get the path to read from.
	local path = "helix/" .. (bGlobal and "" or Schema.folder .. "/") .. (bIgnoreMap and "" or game.GetMap() .. "/")
	-- Read the data from a local file.
	local contents = file.Read(path .. key .. ".txt", "DATA")

	if (contents and contents != "") then
		file.Delete(path .. key .. ".txt")
		ix.data.stored[key] = nil
		return true
	end

	return false
end

if (SERVER) then
	timer.Create("ixSaveData", 600, 0, function()
		hook.Run("SaveData")
	end)

	local queued, order = {}, {}

	--- Saves something at the end of this tick, once, however many times it is asked for before then. Both sides of a
	-- trade (a character's money and the container or character it came from) are saved in the same tick as the
	-- items that moved, which are written at once, so a crash can't keep one side and lose the other; and a value
	-- changed every frame is still saved only once a tick.
	-- @realm server
	-- @string key What is being saved, e.g. `"character 12"`: a later request under the same key replaces the earlier
	-- @func callback Function that saves it
	function ix.data.SaveSoon(key, callback)
		if (!queued[key]) then
			order[#order + 1] = key

			if (#order == 1) then
				timer.Simple(0, function() ix.data.SaveQueued() end)
			end
		end

		queued[key] = callback
	end

	--- Runs the saves queued with `ix.data.SaveSoon` now, in the order they were first asked for. Called at the end of
	-- each tick that queued any; an error in one is reported and the rest still run.
	-- @realm server
	-- @internal
	function ix.data.SaveQueued()
		local keys, callbacks = order, queued
		order, queued = {}, {}

		for _, key in ipairs(keys) do
			local bSaved, fault = xpcall(callbacks[key], debug.traceback)

			if (!bSaved) then
				ErrorNoHalt("[Helix] saving " .. tostring(key) .. " failed: " .. tostring(fault) .. "\n")
			end
		end
	end
end
