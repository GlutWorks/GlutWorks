-- Registry dump for `harness/gw dump`. With config.mode == "dump" the server writes what the
-- gamemode registered (items after bases and plugins are applied, recipes, commands, config
-- and so on) to data/gw_harness/registry.json once it has settled, then quits. The host side
-- adds source files and cross-references; this file only reports what the game holds.

GWH = GWH or {}

local DIR = "gw_harness"

--- Turns a value into something util.TableToJSON can hold: vectors, angles and colours
-- become strings, entities their class, functions are dropped (nil) and a table already
-- being converted further up becomes "<cycle>".
local function Plain(value, seen, depth)
	if (IsColor(value)) then return string.format("%d %d %d %d", value.r, value.g, value.b, value.a) end
	if (isvector(value)) then return string.format("%g %g %g", value.x, value.y, value.z) end
	if (isangle(value)) then return string.format("%g %g %g", value.p, value.y, value.r) end
	if (isentity(value)) then return IsValid(value) and value:GetClass() or "NULL" end
	if (isfunction(value)) then return nil end
	if (isnumber(value) or isstring(value) or isbool(value) or value == nil) then return value end
	if (!istable(value)) then return tostring(value) end

	seen = seen or {}
	depth = depth or 0

	if (seen[value]) then return "<cycle>" end
	if (depth > 6) then return "<table>" end

	seen[value] = true

	local out = {}

	for k, v in pairs(value) do
		local plain = Plain(v, seen, depth + 1)

		if (plain != nil) then
			out[(isnumber(k) or isstring(k)) and k or tostring(k)] = plain
		end
	end

	seen[value] = nil

	return out
end

GWH.DumpPlain = Plain

local function SortedKeys(tbl, filter)
	local keys = {}

	for k, v in pairs(tbl or {}) do
		if (!filter or filter(k, v)) then
			keys[#keys + 1] = tostring(k)
		end
	end

	table.sort(keys)

	return keys
end

--- Describes a definition table: every scalar field, the fields named in `tables` converted
-- whole, the names of its functions as `methods`, and the names of its other table fields
-- as `tableFields` so a reader knows they exist without the dump carrying all of them.
local function Describe(definition, tables, skip)
	local out, methods, others = {}, {}, {}

	for k, v in pairs(definition) do
		if (!isstring(k) or (skip and skip[k])) then
			continue
		end

		if (isfunction(v)) then
			methods[#methods + 1] = k
		elseif (tables and tables[k]) then
			out[k] = Plain(v)
		elseif (istable(v) and !IsColor(v)) then
			others[#others + 1] = k
		else
			out[k] = Plain(v)
		end
	end

	table.sort(methods)
	table.sort(others)
	out.methods = methods
	out.tableFields = #others > 0 and others or nil

	return out
end

local function Source(fn)
	local info = debug.getinfo(fn, "S")

	return info and info.short_src
end

--- The gamemode file a scripted class was defined in, found from the source of its
-- functions, or nil when it comes from an addon or the base game.
local function GamemodeFile(definition)
	for _, v in SortedPairs(definition) do
		if (isfunction(v)) then
			local path = Source(v) or ""
			local relative = path:match("^gamemodes/(.+)$")

			if (relative and (relative:find("^helix/") or relative:find("^" .. engine.ActiveGamemode() .. "/"))) then
				return relative
			end
		end
	end
end

local ITEM_TABLES = {factions = true, classes = true, iconCam = true, exRender = true}
local ITEM_SKIP = {functions = true, hooks = true, postHooks = true, baseTable = true, data = true}

local function Item(item)
	local out = Describe(item, ITEM_TABLES, ITEM_SKIP)

	out.functions = SortedKeys(item.functions)
	out.hooks = #SortedKeys(item.hooks) > 0 and SortedKeys(item.hooks) or nil
	out.postHooks = #SortedKeys(item.postHooks) > 0 and SortedKeys(item.postHooks) or nil
	out.stackable = ix.stack and ix.stack.IsStackable(item) or nil

	return out
end

local function Items()
	local out = {}

	for id, item in pairs(ix.item.base) do out[id] = Item(item) end
	for id, item in pairs(ix.item.list) do out[id] = Item(item) end

	return out
end

local function Plugins()
	local out = {}
	local skip = {folder = true, plugin = true, paths = true, loading = true, license = true}

	local function Add(id, plugin)
		local entry = {
			uniqueID = id,
			name = plugin.name,
			author = plugin.author,
			description = plugin.description,
			folder = plugin.folder,
			parent = istable(plugin.plugin) and plugin.plugin.uniqueID or nil,
			paths = istable(plugin.paths) and plugin.paths or nil,
			hooks = SortedKeys(plugin, function(k, v) return isstring(k) and isfunction(v) end)
		}

		for k, v in pairs(plugin) do
			if (isstring(k) and !skip[k] and entry[k] == nil and !istable(v) and !isfunction(v)) then
				entry[k] = Plain(v)
			end
		end

		out[id] = entry
	end

	for id, plugin in pairs(ix.plugin.list) do Add(id, plugin) end
	if (Schema) then Add("schema", Schema) out.schema.folder = engine.ActiveGamemode() .. "/schema" end

	for id in pairs(ix.plugin.unloaded or {}) do
		if (!out[id]) then out[id] = {uniqueID = id, disabled = true} end
	end

	return out
end

local RECIPE_TABLES = {requirements = true, interchangeable_req = true, results = true, tools = true}

local function Crafting()
	local craft = ix.plugin.list.ixcraft and ix.plugin.list.ixcraft.craft

	if (!craft) then return {}, {} end

	local recipes, stations = {}, {}

	for id, recipe in pairs(craft.recipes or {}) do
		local entry = Describe(recipe, RECIPE_TABLES, {preHooks = true, postHooks = true})

		-- Defaults live on the recipe metatable, so read them through it.
		for _, key in ipairs({"name", "description", "category", "model", "station", "stationRange", "flag", "skin"}) do
			entry[key] = Plain(recipe[key])
		end

		entry.uniqueID = id
		entry.requirements = Plain(recipe.requirements or {})
		entry.interchangeable_req = recipe.interchangeable_req and Plain(recipe.interchangeable_req) or nil
		entry.results = Plain(recipe.results or {})
		entry.tools = Plain(recipe.tools or {})
		entry.preHooks = recipe.preHooks and SortedKeys(recipe.preHooks) or nil
		entry.postHooks = recipe.postHooks and SortedKeys(recipe.postHooks) or nil
		recipes[id] = entry
	end

	for id, station in pairs(craft.stations or {}) do
		local entry = Describe(station, {smelting = true})

		entry.uniqueID = id
		entry.name = station.name
		entry.description = station.description
		entry.model = station.model
		entry.entity = "ix_station_" .. id
		entry.recipes = {}

		for recipeID, recipe in SortedPairs(craft.recipes or {}) do
			if (recipe.station == id) then entry.recipes[#entry.recipes + 1] = recipeID end
		end

		stations[id] = entry
	end

	return recipes, stations
end

local function Commands()
	local out = {}

	for key, command in pairs(ix.command.list) do
		out[key] = {
			name = command.name,
			aliasOf = (isstring(command.name) and command.name:lower() != key) and command.name:lower() or nil,
			description = command.description,
			syntax = command.syntax,
			arguments = istable(command.argumentNames) and command.argumentNames or nil,
			adminOnly = command.adminOnly or false,
			superAdminOnly = command.superAdminOnly or false,
			privilege = "Helix - " .. (isstring(command.privilege) and command.privilege or tostring(command.name)),
			plugin = istable(command.plugin) and command.plugin.uniqueID or nil
		}
	end

	return out
end

local function Config()
	local out = {}

	for key, config in pairs(ix.config.stored) do
		local data = istable(config.data) and config.data or {}

		out[key] = {
			key = key,
			type = ix.type and ix.type[config.type] or config.type,
			default = Plain(config.default),
			value = Plain(config.value),
			description = config.description,
			category = data.category,
			data = Plain(data)
		}
	end

	return out
end

local function Factions()
	local out = {}

	for _, faction in pairs(ix.faction.indices) do
		local entry = Describe(faction, {models = true})

		entry.uniqueID = faction.uniqueID
		entry.index = faction.index
		out[faction.uniqueID] = entry
	end

	return out
end

local function Classes()
	local out = {}

	for index, class in pairs(ix.class.list) do
		local entry = Describe(class)
		local faction = ix.faction.indices[class.faction]

		entry.index = index
		entry.faction = faction and faction.uniqueID or class.faction
		out[class.uniqueID or tostring(index)] = entry
	end

	return out
end

local function Flags()
	local out = {}

	for flag, info in pairs(ix.flag.list) do
		out[flag] = {flag = flag, description = info.description}
	end

	return out
end

--- Every scripted entity and weapon class. The host keeps the ones that come from the
-- checkout: a class with no functions of its own (one that only sets fields over its Base)
-- cannot be traced to a file from in here, so the host matches class names to files.
local function Entities()
	local out = {}

	local function Add(kind, class, definition)
		out[class] = {
			class = class,
			kind = kind,
			PrintName = definition.PrintName,
			Base = definition.Base,
			Type = definition.Type,
			Category = definition.Category,
			Spawnable = definition.Spawnable,
			AdminOnly = definition.AdminOnly,
			model = isstring(definition.model) and definition.model or nil,
			source = GamemodeFile(definition)
		}
	end

	for class in pairs(scripted_ents.GetList()) do
		local stored = scripted_ents.GetStored(class)
		if (stored and stored.t) then Add("entity", class, stored.t) end
	end

	for _, weapon in ipairs(weapons.GetList()) do
		local stored = weapons.GetStored(weapon.ClassName)
		if (stored) then Add("weapon", weapon.ClassName, stored) end
	end

	return out
end

local function Hooks()
	local out = {}

	for name, cache in pairs(HOOKS_CACHE or {}) do
		local owners = {}

		for plugin in pairs(cache) do
			owners[#owners + 1] = istable(plugin) and tostring(plugin.uniqueID) or tostring(plugin)
		end

		out[name] = owners
	end

	for name, value in pairs(Schema or {}) do
		if (isstring(name) and isfunction(value)) then
			out[name] = out[name] or {}
			table.insert(out[name], "schema")
		end
	end

	for _, owners in pairs(out) do table.sort(owners) end

	return out
end

--- Builds the whole registry. Each section is built on its own, so one that throws is
-- reported in `errors` and the others are still written.
function GWH.Registry()
	local registry, errors = {}, {}
	local recipes, stations

	local sections = {
		plugins = Plugins,
		items = Items,
		recipes = function() recipes, stations = Crafting() return recipes end,
		stations = function() return stations or select(2, Crafting()) end,
		commands = Commands,
		config = Config,
		factions = Factions,
		classes = Classes,
		flags = Flags,
		entities = Entities,
		hooks = Hooks
	}

	for _, name in ipairs({"plugins", "items", "recipes", "stations", "commands", "config", "factions", "classes",
		"flags", "entities", "hooks"}) do
		local ok, result = xpcall(sections[name], function(err) return debug.traceback(tostring(err), 2) end)

		if (ok) then
			registry[name] = result
		else
			registry[name] = {}
			errors[#errors + 1] = name .. ": " .. tostring(result)
		end
	end

	registry.meta = {
		gamemode = engine.ActiveGamemode(),
		map = game.GetMap(),
		errors = errors
	}

	return registry
end

hook.Add("InitPostEntity", "gw_harness_dump", function()
	if (GWH.cfg.mode != "dump") then return end

	timer.Simple(GWH.cfg.settle or 3, function()
		local registry = GWH.Registry()
		local counts = {}

		for name, section in pairs(registry) do
			if (name != "meta") then counts[name] = table.Count(section) end
		end

		file.Write(DIR .. "/registry.json", util.TableToJSON(registry))
		file.Write(DIR .. "/result.json", util.TableToJSON({done = true, counts = counts, errors = GWH.errors}))

		timer.Simple(0.5, engine.CloseServer)
	end)
end)
