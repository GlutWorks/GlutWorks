-- File-based request/response channel between `harness/gw play ...` and the game.
-- The host drops <realm>_req_<id>.json into data/gw_harness; the matching realm runs the
-- named op and writes <realm>_res_<id>.json. Nothing here listens on the network.

GWH = GWH or {}
GWH.ops = GWH.ops or {}
GWH.errors = GWH.errors or {}
GWH.ASYNC = GWH.ASYNC or {}

local REALM = SERVER and "sv" or "cl"
local DIR = "gw_harness"

file.CreateDir(DIR)

--- Registers an op. `fn(request, reply)` returns its result, or returns GWH.ASYNC and
-- calls reply(result) later.
function GWH.Op(name, fn)
	GWH.ops[name] = fn
end

--- Converts any Lua value into something util.TableToJSON can represent.
function GWH.Plain(value, depth)
	depth = depth or 0

	if (isvector(value)) then return {math.Round(value.x, 1), math.Round(value.y, 1), math.Round(value.z, 1)} end
	if (isangle(value)) then return {math.Round(value.p, 1), math.Round(value.y, 1), math.Round(value.r, 1)} end
	if (isentity(value)) then return IsValid(value) and (value:GetClass() .. "#" .. value:EntIndex()) or "NULL" end
	if (isnumber(value) or isstring(value) or isbool(value) or value == nil) then return value end

	if (istable(value)) then
		if (depth > 5) then return "<table>" end

		local out, count = {}, 0

		for k, v in pairs(value) do
			count = count + 1
			if (count > 200) then out["..."] = "truncated" break end

			out[(isnumber(k) or isstring(k)) and k or tostring(k)] = GWH.Plain(v, depth + 1)
		end

		return out
	end

	return tostring(value)
end

local function Respond(id, payload)
	file.Write(DIR .. "/" .. REALM .. "_res_" .. id .. ".json", util.TableToJSON(payload))
end

local function Handle(request)
	local id = tostring(request.id)
	local op = GWH.ops[request.op]

	if (!op) then return Respond(id, {ok = false, error = "unknown op " .. tostring(request.op)}) end

	local ok, result = xpcall(op, function(err)
		return debug.traceback(tostring(err), 2)
	end, request, function(late)
		Respond(id, {ok = true, result = GWH.Plain(late)})
	end)

	if (!ok) then
		Respond(id, {ok = false, error = result})
	elseif (result != GWH.ASYNC) then
		Respond(id, {ok = true, result = GWH.Plain(result)})
	end
end

timer.Create("gw_harness_rpc", 0.05, 0, function()
	for _, name in ipairs(file.Find(DIR .. "/" .. REALM .. "_req_*.json", "DATA")) do
		local path = DIR .. "/" .. name
		local request = util.JSONToTable(file.Read(path, "DATA") or "")

		file.Delete(path)

		if (request) then Handle(request) end
	end
end)

--- Runs a chunk of Lua. An expression's value, or the chunk's return value, is the result.
GWH.Op("lua", function(request)
	local fn = CompileString("return " .. request.code, "gw_rpc", false)

	if (!isfunction(fn)) then
		fn = CompileString(request.code, "gw_rpc", false)
	end

	if (!isfunction(fn)) then error(tostring(fn), 0) end

	return fn()
end)

--- Returns the Lua errors seen in this realm since the last call.
GWH.Op("errors", function()
	local errors = GWH.errors
	GWH.errors = {}

	return errors
end)
