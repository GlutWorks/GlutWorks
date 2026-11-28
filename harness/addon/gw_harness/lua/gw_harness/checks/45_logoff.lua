-- Logging off (logoff) and leaving the city (arriving): how safe a place is to leave from (areas, the hook,
-- dangerous over safe, the station), who may take the train out and from where, the choice on that train
-- of who comes in, and joining with every character away.

local Lib = GWH.Lib
local Scoped, Replace, ResetBot, StandOnSpawn = Lib.Scoped, Lib.Replace, Lib.ResetBot, Lib.StandOnSpawn
local ResetBotFully = Lib.ResetBotFully
local NewCharacter, Switch, Receive = Lib.NewCharacter, Lib.Switch, Lib.Receive

-- Areas for the length of a check, nothing sent to clients: {name = {type, mins, maxs}}.
local function WithAreas(defer, areas)
	local stored = ix.area.stored

	ix.area.stored = table.Copy(stored)
	defer(function() ix.area.stored = stored end)

	for name, area in pairs(areas) do
		ix.area.stored[name] = {type = area[1], startPosition = area[2], endPosition = area[3], properties = {}}
	end
end

GWH.Check("logoff: a place is safe, ordinary or dangerous, and dangerous wins", function(fail)
	if (!ix.logoff or !ix.area) then return {skipped = "logoff or areas not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		local here = Vector(5000, 5000, 5000)

		WithAreas(defer, {
			gwhSafe = {"safe", here - Vector(100, 100, 100), here + Vector(100, 100, 100)},
			gwhDanger = {"dangerous", here + Vector(50, 50, -100), here + Vector(150, 150, 100)}
		})

		local function Safety(pos) return ix.logoff.GetSafety(bot, pos) end

		if (Safety(here) != "safe") then fail("inside a safe area is " .. Safety(here)) end
		if (Safety(here + Vector(80, 80, 0)) != "dangerous") then fail("where safe and dangerous overlap is not dangerous") end
		if (Safety(here + Vector(400, 0, 0)) != "ordinary") then fail("outside both is " .. Safety(here + Vector(400, 0, 0))) end

		-- a plugin's answer counts, and dangerous still wins over it
		hook.Add("GetLogOffSafety", "gwh_logoff", function(client, pos)
			if (pos:Distance(here + Vector(400, 0, 0)) < 1 or pos:Distance(here + Vector(80, 80, 0)) < 1) then return "safe" end
		end)
		defer(function() hook.Remove("GetLogOffSafety", "gwh_logoff") end)

		if (Safety(here + Vector(400, 0, 0)) != "safe") then fail("a plugin's safe place is not safe") end
		if (Safety(here + Vector(80, 80, 0)) != "dangerous") then fail("a plugin's safe answer beat a dangerous area") end
	end)

	local P = ix.plugin.list.arriving

	if (P) then
		local platform = P:GetPlatform()

		if (ix.logoff.GetSafety(bot, platform.origin + Vector(0, 0, 36)) != "safe") then fail("the station is not safe to leave from") end
	end
end)

GWH.Check("arriving: only someone with papers, somewhere safe, takes the train out", function(fail)
	local P = ix.plugin.list.arriving
	if (!P or !ix.logoff) then return {skipped = "arriving or logoff not loaded"} end
	if (!P.train or !IsValid(P.departures)) then return {skipped = "no train or departures on this map"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	-- (earlier checks leave the shared bot tied or knocked about: on its feet and free, as anyone leaving)
	ResetBotFully(bot)

	local character = bot:GetCharacter()
	local gate = P.departures

	-- the station's fixtures collide as boxes with no physics object, so nothing moving loose things takes them
	for _, fixture in ipairs({gate, P.desk and P.desk[2]}) do
		if (IsValid(fixture) and IsValid(fixture:GetPhysicsObject())) then fail(fixture:GetClass() .. " has a physics object") end
	end

	-- and none stands on a spawn point, where players would spawn inside it
	for _, fixture in ipairs({gate, P.desk and P.desk[1], P.desk and P.desk[2]}) do
		if (IsValid(fixture)) then
			for _, spawn in ipairs(ents.FindByClass("info_player_start")) do
				local here = fixture:WorldToLocal(spawn:GetPos() + Vector(0, 0, 36))
				local mins, maxs = fixture:OBBMins() - Vector(20, 20, 0), fixture:OBBMaxs() + Vector(20, 20, 0)

				if (here:WithinAABox(mins, maxs)) then
					fail(fixture:GetClass() .. " stands on the spawn point at " .. tostring(spawn:GetPos()))
				end
			end
		end
	end

	Scoped(function(defer)
		local name, arrival = character:GetName(), character:GetData("arrival")
		local departed = 0

		defer(function()
			character:SetName(name)
			character:SetData("arrival", arrival)
			StandOnSpawn(bot)
		end)
		Replace(defer, P, "Depart", function() departed = departed + 1 end)

		local said = {}

		Replace(defer, bot, "Notify", function(_, text) said[#said + 1] = text end)

		local function Ask()
			bot.ixNextDepart = nil
			Receive(net.Receivers["ixarrivingdepart"], bot, {gate})
		end

		character:SetData("arrival", nil)

		-- in front of the booth, clear of its body (it reaches 75 forward)
		bot:SetPos(gate:GetPos() + gate:GetForward() * 110)

		character:SetName("")
		Ask()
		if (departed != 0) then fail("someone without papers took the train out") end

		character:SetName("Gwh Leaver")
		Ask()
		if (departed != 1) then
			return fail("someone with papers at the departures could not leave (" .. table.concat(said, "; ") .. "; the place is "
				.. ix.logoff.GetSafety(bot) .. ", the booth at " .. tostring(gate:GetPos()) .. ")")
		end

		-- the same booth in a dangerous place turns them away
		WithAreas(defer, {gwhDanger = {"dangerous", gate:GetPos() - Vector(300, 300, 300), gate:GetPos() + Vector(300, 300, 300)}})
		Ask()
		if (departed != 1) then fail("someone left the city from a dangerous place") end
	end)
end)

GWH.Check("arriving: on the train out you choose who comes in, and the one who left stays away", function(fail)
	local P = ix.plugin.list.arriving
	if (!P) then return {skipped = "arriving not loaded"} end
	if (!P.train) then return {skipped = "no train on this map"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	ResetBot(bot)

	local current = bot:GetCharacter()

	Scoped(function(defer)
		defer(function()
			if (bot:GetCharacter() != current) then Switch(bot, current) end

			for _, inventory in ipairs(current:GetInventory(true)) do
				if (istable(inventory)) then inventory:AddReceiver(bot) end
			end

			current:SetData("arrival", nil)
			P:UpdateTransmit()
			StandOnSpawn(bot)
		end)
		Replace(defer, bot, "ixCharList", bot.ixCharList)

		local other = NewCharacter(bot)

		hook.Add("CanPlayerUseCharacter", "gwh_leaving", function(client, character)
			if (character == current or character == other) then return true end
		end)
		defer(function() hook.Remove("CanPlayerUseCharacter", "gwh_leaving") end)

		bot.ixCharList = {current:GetID(), other:GetID()}
		current:SetData("arrival", P.states.leaving)

		if (P:ChooseWhoComesIn(bot, 999999999)) then fail("a character that isn't theirs was let in") end
		if (bot:GetCharacter() != current) then return fail("a refused choice changed who they are") end

		if (!P:ChooseWhoComesIn(bot, other:GetID())) then return fail("their other character could not be chosen") end
		if (bot:GetCharacter() != other) then return fail("the chosen character was not loaded") end
		if (P:GetState(current) != P.states.away) then fail("the one who left is " .. tostring(P:GetState(current)) .. ", not away") end
		if (P:GetState(other) != P.states.aboard) then fail("the chosen one is " .. tostring(P:GetState(other)) .. ", not riding in") end
		if (P:ChooseWhoComesIn(bot, current:GetID())) then fail("someone already riding in chose again") end

		-- choosing the one who's leaving keeps them: they ride back in
		other:SetData("arrival", P.states.leaving)
		if (!P:ChooseWhoComesIn(bot, other:GetID()) or P:GetState(other) != P.states.aboard) then
			fail("choosing yourself again did not ride you back in")
		end

		other:SetData("arrival", nil)
	end)
end)

GWH.Check("arriving: joining with every character away puts you on the train out", function(fail)
	local P = ix.plugin.list.arriving
	if (!P) then return {skipped = "arriving not loaded"} end
	if (!P.train) then return {skipped = "no train on this map"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	ResetBot(bot)

	local current = bot:GetCharacter()

	Scoped(function(defer)
		defer(function()
			if (bot:GetCharacter() != current) then Switch(bot, current) end

			for _, inventory in ipairs(current:GetInventory(true)) do
				if (istable(inventory)) then inventory:AddReceiver(bot) end
			end

			P:UpdateTransmit()
			StandOnSpawn(bot)
		end)
		Replace(defer, bot, "ixCharList", bot.ixCharList)

		local older, newer = NewCharacter(bot), NewCharacter(bot)

		hook.Add("CanPlayerUseCharacter", "gwh_away", function(client, character)
			if (character == older or character == newer) then return true end
		end)
		defer(function() hook.Remove("CanPlayerUseCharacter", "gwh_away") end)

		older.vars.lastJoinTime, newer.vars.lastJoinTime = 100, 200
		older:SetData("arrival", P.states.away)
		newer:SetData("arrival", P.states.away)
		bot.ixCharList = {older:GetID(), newer:GetID()}

		P:Arrive(bot)

		if (bot:GetCharacter() != newer) then return fail("joined as " .. tostring(bot:GetCharacter()) .. ", not the latest away") end
		if (P:GetState(newer) != P.states.leaving) then fail("joining with all away is " .. tostring(P:GetState(newer)) .. ", not on the train out") end
		if (!P:IsAboard(bot)) then fail("someone on the train out is not aboard") end
	end)
end)
