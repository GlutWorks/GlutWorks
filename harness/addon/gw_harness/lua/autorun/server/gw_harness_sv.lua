-- GlutWorks test harness, server side.
-- Mounted into the sandboxed server only by `harness/gw`; never shipped to a live server.
-- Reads data/gw_harness/config.json, runs the registered checks once the gamemode has
-- settled, writes data/gw_harness/result.json, then quits when config.quit is set.

if (!SERVER) then return end

GWH = GWH or {}

local DIR = "gw_harness"
file.CreateDir(DIR)

include("gw_harness/rpc.lua")

GWH.cfg = util.JSONToTable(file.Read(DIR .. "/config.json", "DATA") or "{}") or {}
GWH.checks = {}

AddCSLuaFile("gw_harness/rpc.lua")

hook.Add("OnLuaError", "gw_harness", function(err, realm, stack, name)
	GWH.errors[#GWH.errors + 1] = {
		error = tostring(err),
		realm = tostring(realm),
		addon = name and tostring(name) or nil,
		stack = stack,
		during = GWH.current
	}
end)

--- Registers a check. `fn(fail)` reports each problem with fail(message); a thrown error
-- also counts as a failure. The return value, if any, is stored as the check's detail.
function GWH.Check(name, fn)
	GWH.checks[#GWH.checks + 1] = {name = name, fn = fn}
end

function GWH.Bot()
	for _, v in ipairs(player.GetBots()) do
		if (v:GetCharacter()) then return v end
	end
end

local function WriteResult(result)
	file.Write(DIR .. "/result.json", util.TableToJSON(result, true))
end

function GWH.Run()
	local results = {}
	local only = GWH.cfg.only

	for _, check in ipairs(GWH.checks) do
		if (!only or string.find(check.name, only, 1, true)) then
			local failures = {}
			local started = SysTime()
			GWH.current = check.name

			local ok, detail = xpcall(check.fn, function(err)
				return debug.traceback(tostring(err), 2)
			end, function(message)
				failures[#failures + 1] = tostring(message)
			end)

			if (!ok) then
				failures[#failures + 1] = "check threw: " .. tostring(detail)
				detail = nil
			end

			results[#results + 1] = {
				name = check.name,
				ok = #failures == 0,
				failures = failures,
				detail = detail,
				seconds = math.Round(SysTime() - started, 3)
			}
		end
	end

	GWH.current = nil

	return results
end

local function Finish()
	local results = GWH.Run()

	-- Let errors raised from timers and net callbacks started by the checks surface.
	timer.Simple(GWH.cfg.linger or 3, function()
		WriteResult({
			done = true,
			map = game.GetMap(),
			gamemode = engine.ActiveGamemode(),
			checks = results,
			errors = GWH.errors
		})

		if (GWH.cfg.quit) then
			timer.Simple(0.5, engine.CloseServer)
		end
	end)
end

hook.Add("InitPostEntity", "gw_harness", function()
	print("gw_harness ready")

	if (GWH.cfg.mode != "smoke") then return end

	WriteResult({done = false, stage = "settling"})

	timer.Simple(GWH.cfg.settle or 5, function()
		if (GWH.cfg.bot != false) then
			RunConsoleCommand("bot")
		end

		timer.Simple(2, Finish)
	end)
end)

-- In a play session the tester is the only human and needs admin commands to set up scenarios.
hook.Add("PlayerInitialSpawn", "gw_harness", function(client)
	if (GWH.cfg.mode == "play" and !client:IsBot()) then
		client:SetUserGroup("superadmin")
	end
end)

--- Runs the checks on demand during a play session.
GWH.Op("checks", function()
	return GWH.Run()
end)

for _, name in ipairs(file.Find("gw_harness/checks/*.lua", "LUA")) do
	include("gw_harness/checks/" .. name)
end
