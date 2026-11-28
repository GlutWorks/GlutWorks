-- Logging off (logoff) and leaving the city (arriving): how safe a place is to leave from (areas, the hook,
-- dangerous over safe, the station), who may take the train out and from where, the choice on that train
-- of who comes in, joining with every character away, and the body left asleep by leaving anywhere else
-- (how long, searched, hurt, killed, and waking where it lies).

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
		local feet = IsValid(fixture) and Lib.SpawnPointUnder(fixture)

		if (feet) then fail(fixture:GetClass() .. " stands on the spawn point at " .. tostring(feet)) end
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

		-- (a player's Notify is a metatable method, so it's caught where it goes)
		Replace(defer, ix.util, "Notify", function(text, recipient) if (recipient == bot) then said[#said + 1] = text end end)

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

		-- someone fresh from a fight is turned away, even here
		bot.ixLogoffFight = CurTime()
		defer(function() bot.ixLogoffFight = nil end)
		Ask()
		bot.ixLogoffFight = nil
		if (departed != 1) then fail("someone fresh from a fight took the train out") end

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

-- ------------------------------------------------------------------ the sleeping body

-- Puts the bot on a spawn point where leaving is ordinary (neither safe nor dangerous); false when there's none.
local function StandSomewhereOrdinary(bot)
	for _, spawn in ipairs(ents.FindByClass("info_player_start")) do
		if (ix.logoff.GetSafety(bot, spawn:GetPos() + Vector(0, 0, 36)) == ix.logoff.ORDINARY) then
			bot:SetPos(spawn:GetPos())
			return true
		end
	end

	return false
end

-- Leaves `character` (one of the bot's, not its current one) asleep where the bot stands, as if they'd just
-- logged off from there, and puts the bot back as `current`. Returns the body.
local function FallAsleep(defer, bot, current, character, sleep)
	local L = ix.plugin.list.logoff
	local stood = bot:GetPos()

	-- (loading a character spawns them on a spawn point)
	Switch(bot, character)
	bot:SetPos(stood)

	local body = L:LeaveAsleep(bot, sleep)

	defer(function() if (IsValid(body)) then body:Remove() end end)
	Switch(bot, current)

	return body
end

-- Restores the bot as `current` with its inventory reaching it, after a check that switched characters.
local function BackAs(bot, current)
	if (!bot:Alive()) then bot:Spawn() end
	if (bot:GetCharacter() != current) then Switch(bot, current) end

	for _, inventory in ipairs(current:GetInventory(true)) do
		if (istable(inventory)) then inventory:AddReceiver(bot) end
	end
end

GWH.Check("logoff: leaving somewhere safe is clean, ordinary sleeps a while, dangerous or held the whole time", function(fail)
	local L = ix.plugin.list.logoff
	if (!L or !ix.area) then return {skipped = "logoff or areas not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	ResetBotFully(bot)

	Scoped(function(defer)
		local here = Vector(5000, 5000, 5000)
		local home = bot:GetPos()

		defer(function()
			bot:SetPos(home)
			bot.ixLogoffFight = nil
		end)

		WithAreas(defer, {
			gwhSafe = {"safe", here - Vector(100, 100, 100), here + Vector(100, 100, 100)},
			gwhDanger = {"dangerous", here + Vector(400, -100, -100), here + Vector(600, 100, 100)}
		})

		local function SleepAt(pos)
			bot:SetPos(pos - Vector(0, 0, 36))
			return ix.logoff.GetSleep(bot)
		end

		local timed = ix.config.Get("logoffSleepTime", 300)

		if (SleepAt(here) != nil) then fail("leaving somewhere safe sleeps (" .. tostring(SleepAt(here)) .. ")") end
		if (SleepAt(here + Vector(250, 0, 0)) != timed) then fail("leaving somewhere ordinary sleeps " .. tostring(SleepAt(here + Vector(250, 0, 0))) .. ", not " .. timed) end
		if (SleepAt(here + Vector(500, 0, 0)) != true) then fail("leaving somewhere dangerous does not sleep the whole time away") end

		-- just after a fight the body stays the whole time, even from somewhere safe, and can't leave cleanly
		bot.ixLogoffFight = CurTime()
		if (SleepAt(here) != true) then fail("leaving somewhere safe straight after a fight does not sleep the whole time away") end
		if (ix.logoff.MayLeaveCleanly(bot)) then fail("someone fresh from a fight may leave cleanly") end
		if (SleepAt(here + Vector(250, 0, 0)) != true) then fail("leaving somewhere ordinary after a fight sleeps only a while") end

		-- the fight is forgotten in time
		bot.ixLogoffFight = CurTime() - ix.config.Get("logoffFightMemory", 300) - 1
		if (SleepAt(here) != nil) then fail("a fight long past still holds the body") end

		-- a wanted system holds them through the hook
		bot.ixLogoffFight = nil
		hook.Add("ShouldSleepWhileAway", "gwh_logoff", function(client) if (client == bot) then return true end end)
		defer(function() hook.Remove("ShouldSleepWhileAway", "gwh_logoff") end)
		if (SleepAt(here) != true) then fail("someone the ShouldSleepWhileAway hook holds left cleanly") end
		hook.Remove("ShouldSleepWhileAway", "gwh_logoff")

		-- leaving the server falls asleep only when GetSleep says so
		local slept = {}

		Replace(defer, L, "LeaveAsleep", function(_, client, sleep) slept[#slept + 1] = sleep end)

		SleepAt(here)
		L:PlayerDisconnected(bot)
		SleepAt(here + Vector(250, 0, 0))
		L:PlayerDisconnected(bot)

		if (#slept != 1 or slept[1] != timed) then fail("leaving the server fell asleep " .. #slept .. " times (" .. tostring(slept[1]) .. "), not once for " .. timed) end
	end)
end)

GWH.Check("logoff: a body left asleep lies where its player stood, is searched, hurt, and wakes where it lies", function(fail)
	local L = ix.plugin.list.logoff
	if (!L) then return {skipped = "logoff not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	ResetBotFully(bot)

	local current = bot:GetCharacter()

	Scoped(function(defer)
		defer(function()
			BackAs(bot, current)
			bot.ixLogoffFight = nil
			bot.ixLogoffWaking = nil
			StandOnSpawn(bot)
		end)

		if (!StandSomewhereOrdinary(bot)) then return fail("no spawn point is ordinary to leave from") end

		local stood = bot:GetPos()
		local sleeper = NewCharacter(bot)
		local body = FallAsleep(defer, bot, current, sleeper, 300)

		if (!IsValid(body)) then return fail("no body was left") end
		if (ix.logoff.GetSleeper(sleeper) != body) then fail("the character's sleeping body is not the one left") end
		if (body:GetNetVar("asleep") == nil) then fail("the body is not marked asleep for those who see it") end
		if (body:GetPos():Distance(stood) > 64) then fail("the body lies " .. math.floor(body:GetPos():Distance(stood)) .. " units from where they stood") end

		local left = timer.TimeLeft("ixLogoffSleep" .. sleeper:GetID())
		if (!left or left < 299 or left > 300.5) then fail("an ordinary sleep lasts " .. tostring(left) .. " seconds, not 300") end

		-- someone else goes through its pockets: the sleeper's own inventory, through a search
		local inventory = sleeper:GetInventory()

		bot:SetPos(body:GetPos() + Vector(40, 0, 0))
		if (!L:Search(bot, body)) then fail("the sleeping body could not be searched") end
		if (!inventory.storageInfo or inventory.storageInfo.entity != body) then fail("searching did not open the sleeper's inventory") end
		L:CloseSearch(body)

		-- hurt, it keeps what's left, and whoever hurt it has been in a fight
		local health = body.ixSleeper.health
		local damage = DamageInfo()
		damage:SetDamage(30)
		damage:SetDamageType(DMG_BULLET)
		damage:SetAttacker(bot)
		damage:SetInflictor(bot)
		body:TakeDamageInfo(damage)

		if (body.ixSleeper.health != health - 30) then fail("a bullet of 30 left the body at " .. body.ixSleeper.health .. " of " .. health) end
		if (!bot.ixLogoffFight) then fail("hurting a sleeping body is no fight") end

		-- coming back wakes them where it lies, as hurt as it is, and the body goes
		body:SetPos(body:GetPos() + Vector(60, 0, 0))
		local lies = body:GetPos()

		L:PrePlayerLoadedCharacter(bot, sleeper)

		local place = bot.ixLogoffWaking and {bot.ixLogoffWaking.pos}

		-- (removed at the end of the tick)
		if (IsValid(body) and !body:IsMarkedForDeletion()) then fail("the body is still there once they're back") end
		if (!place or place[1]:Distance(lies) > 80) then fail("they wake at " .. tostring(place and place[1]) .. ", not where the body lay, " .. tostring(lies)) end
		if (!bot.ixLogoffWaking or bot.ixLogoffWaking.health != health - 30 or !bot.ixLogoffWaking.bSearched) then
			return fail("waking does not keep the body's health and that it was searched")
		end

		-- and, once loaded, puts them there (the bot stands as `current` here; Wake asks only the body)
		local told = {}

		Replace(defer, ix.util, "Notify", function(text, recipient) if (recipient == bot) then told[#told + 1] = text end end)
		bot:SetPos(stood + Vector(0, 300, 0))
		L:Wake(bot, bot.ixLogoffWaking)

		if (bot:GetPos():Distance(lies) > 80) then fail("woke at " .. tostring(bot:GetPos()) .. ", not where the body lay, " .. tostring(lies)) end
		if (bot:Health() != health - 30) then fail("woke with " .. bot:Health() .. " health, not the body's " .. (health - 30)) end
		if (#told != 1) then fail("waking after a search said " .. #told .. " things, not that the pockets were gone through") end

	end)
end)

GWH.Check("logoff: a body knocked out as its player leaves sleeps where it lay, apart from theirs", function(fail)
	local L = ix.plugin.list.logoff
	if (!L) then return {skipped = "logoff not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	ResetBotFully(bot)

	Scoped(function(defer)
		defer(function() ResetBotFully(bot) StandOnSpawn(bot) end)

		if (!StandSomewhereOrdinary(bot)) then return fail("no spawn point is ordinary to leave from") end

		bot:SetRagdolled(true, 30)

		local knocked = bot.ixRagdoll
		if (!IsValid(knocked)) then return fail("the bot could not be knocked out") end

		knocked:SetPos(knocked:GetPos() + Vector(50, 0, 0))

		local body = L:LeaveAsleep(bot, 300)
		defer(function() if (IsValid(body)) then body:Remove() end end)

		if (body == knocked) then fail("the knocked-out body itself was kept, which Helix removes as they go") end
		if (body:GetPos():Distance(knocked:GetPos()) > 32) then fail("the sleeping body is " .. math.floor(body:GetPos():Distance(knocked:GetPos())) .. " units from where the knocked-out one lay") end
		if (body:GetNetVar("player") != nil) then fail("the sleeping body still belongs to a player") end
	end)
end)

GWH.Check("logoff: a sleeping body killed is a corpse, and its character dies as they come back, leaving no second", function(fail)
	local L = ix.plugin.list.logoff
	if (!L) then return {skipped = "logoff not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	ResetBotFully(bot)

	local current = bot:GetCharacter()

	Scoped(function(defer)
		defer(function()
			BackAs(bot, current)
			bot.ixLogoffFight = nil
			ResetBotFully(bot)
			StandOnSpawn(bot)
		end)

		if (!StandSomewhereOrdinary(bot)) then return fail("no spawn point is ordinary to leave from") end

		local sleeper = NewCharacter(bot)
		local body = FallAsleep(defer, bot, current, sleeper, true)

		if (timer.Exists("ixLogoffSleep" .. sleeper:GetID())) then fail("a body asleep the whole time away has a timer to go") end

		local damage = DamageInfo()
		damage:SetDamage(1000)
		damage:SetDamageType(DMG_BULLET)
		damage:SetAttacker(bot)
		damage:SetInflictor(bot)
		body:TakeDamageInfo(damage)

		if (!IsValid(body)) then return fail("the killed body vanished") end
		if (body:GetNetVar("isDeadPlayer") != true or body:GetNetVar("asleep") != nil) then fail("the killed body is not a corpse") end
		if (ix.logoff.GetSleeper(sleeper)) then fail("the dead body still counts as asleep") end
		if (!sleeper:GetData("diedAsleep")) then fail("the character killed asleep is not marked so") end

		local corpses = ix.plugin.list.persistent_corpses

		if (corpses and ix.config.Get("persistentCorpses", true) and !table.HasValue(corpses.corpses, body)) then
			fail("the killed body does not lie and decay as a corpse")
		end

		-- they come back, and die, with no second body
		local before = #ents.FindByClass("prop_ragdoll")

		Switch(bot, sleeper)
		L:DieAsleep(bot, sleeper)

		if (bot:Alive()) then fail("someone killed in their sleep came back alive") end
		if (#ents.FindByClass("prop_ragdoll") != before) then fail("dying again as they came back left another body") end
		if (sleeper:GetData("diedAsleep")) then fail("the mark of dying asleep outlasts the death") end
	end)
end)
