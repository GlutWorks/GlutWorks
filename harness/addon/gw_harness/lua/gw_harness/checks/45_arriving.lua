-- Arriving (arriving): the names the intake desk takes and refuses, how a body is seen, characters made and
-- chosen only by the server, the train set built over open sky and walkable, the mirror's choices and the
-- cabin door, the citizen loadout leaving the papers to the desk, and the desk's name, number and papers.

local Lib = GWH.Lib
local Scoped, Replace, ResetBot, StandOnSpawn = Lib.Scoped, Lib.Replace, Lib.ResetBot, Lib.StandOnSpawn
local NewCharacter, Switch = Lib.NewCharacter, Lib.Switch

local function Plugin()
	return ix.plugin.list.arriving
end

GWH.Check("arriving: a name is two or three words of letters, written as a name", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end

	local free = function() return false end
	local cases = {
		{"ada black", "Ada Black"},
		{"Mary-Jane o'neil.", "Mary-Jane O'Neil"},
		{"seamus mcKay", "Seamus Mckay"},
		{"Seamus McKay", "Seamus McKay"},
		{"John Paul Jones", "John Paul Jones"},
		{"Bob", false, "oneWord"},
		{"a b c d", false, "tooMany"},
		{"xX_sniper_Xx 99", false, "notLetters"},
		{"J Smith", false, "tooShortOrLong"},
		{"Brrr Smith", false, "notAName"},
		{"Aaaaron Smith", false, "notAName"}
	}

	for _, case in ipairs(cases) do
		local name, refusal = P:CheckName(case[1], free)

		if (case[2]) then
			if (name != case[2]) then fail(case[1] .. " was kept as " .. tostring(name) .. " (" .. tostring(refusal) .. ")") end
		elseif (name or refusal != case[3]) then
			fail(case[1] .. " gave " .. tostring(name or refusal) .. ", not " .. case[3])
		end

		if (refusal and !P.refusals[refusal]) then fail("the clerk has no words for " .. refusal) end
	end

	local name, refusal = P:CheckName("ada black", function(candidate) return candidate == "Ada Black" end)

	if (name or refusal != "taken") then fail("someone else's name gave " .. tostring(name or refusal)) end
end)

GWH.Check("arriving: the refused list keeps out what it should and lets real names through", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end

	local refused = P:GetRefused()

	if (table.Count(refused.words) < 20 or #refused.inside == 0 or table.Count(refused.names) == 0) then
		fail("the refused list read short")
	end

	for _, silly in ipairs({"Hugh Poop", "Joe Mama", "Gordon Freeman", "Adolf Hitler", "Mike Hunt", "Big Shitface", "Ben Dover"}) do
		if (P:CheckName(silly)) then fail(silly .. " got through") end
	end

	for _, real in ipairs({"Grace Hassett", "Alfred Hitchcock", "Charles Dickens", "Mike Freeman", "Gordon Brown"}) do
		if (!P:CheckName(real)) then fail(real .. ", a real name, was refused") end
	end
end)

GWH.Check("arriving: someone is seen as their body, height and age", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end

	local woman, man = "models/player/zelpa/female_01_extended.mdl", "models/player/zelpa/male_01_extended.mdl"
	local expected = {
		{woman, 7, 1, "A tall young woman"},
		{man, 4, 3, "An older man"},
		{man, 2, 2, "A middle-aged man, a little short"},
		{woman, 1, 3, "A short older woman"}
	}

	for _, case in ipairs(expected) do
		local seen = P:Seen(case[1], case[2], case[3])

		if (seen != case[4]) then fail(case[4] .. " was seen as " .. seen) end
	end

	local bodies = P:GetBodies()
	local faction = ix.faction.indices[FACTION_CITIZEN]

	if (#bodies == 0 or #bodies != #faction.models) then fail("the mirror offers " .. #bodies .. " bodies") end
end)

GWH.Check("arriving: clients can neither make nor choose a character", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	ResetBot(bot)

	local character = bot:GetCharacter()

	if (hook.Run("CanPlayerCreateCharacter", bot, {name = "Forged Name"}) != false) then
		fail("a client's ixCharacterCreate would make a character")
	end

	if (hook.Run("CanPlayerUseCharacter", bot, character) != false) then
		fail("a client's ixCharacterChoose would load a character")
	end

	-- the server's own load is let through by arriving (other plugins and Helix still decide: the shared bot
	-- may be in a faction it isn't whitelisted for by now)
	bot.ixArrivingLoading = character:GetID()
	local status = P:CanPlayerUseCharacter(bot, character)
	bot.ixArrivingLoading = nil

	if (status != nil) then fail("arriving refuses the server's own load") end

	P:MayUse(bot, character)
	if (bot.ixArrivingLoading != nil) then fail("MayUse left the loading mark behind") end
end)

GWH.Check("arriving: a returning player comes back as their most recent character the rules allow", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	ResetBot(bot)

	local current = bot:GetCharacter()

	Scoped(function(defer)
		defer(function()
			if (bot:GetCharacter() != current) then Switch(bot, current) end

			-- loading another character took the bot off its own inventories' receivers, as Helix's choose
			-- does; Switch (no networking) doesn't put it back
			for _, inventory in ipairs(current:GetInventory(true)) do
				if (istable(inventory)) then inventory:AddReceiver(bot) end
			end

			StandOnSpawn(bot)
		end)
		Replace(defer, bot, "ixCharList", bot.ixCharList)

		local older, newer = NewCharacter(bot), NewCharacter(bot)
		local bRefuseNewer = false

		older.vars.lastJoinTime = 100
		newer.vars.lastJoinTime = 200
		bot.ixCharList = {older:GetID(), newer:GetID()}

		-- the rules decide which may be used (the shared bot's faction may be whitelisted, which would
		-- refuse both): here both may, until the newer is refused, as a ban or a lost whitelist would
		hook.Add("CanPlayerUseCharacter", "gwh_arriving", function(client, character)
			if (character == newer and bRefuseNewer) then return false end
			if (character == older or character == newer) then return true end
		end)
		defer(function() hook.Remove("CanPlayerUseCharacter", "gwh_arriving") end)

		P:Arrive(bot)
		if (bot:GetCharacter() != newer) then fail("came back as " .. tostring(bot:GetCharacter()) .. ", not the most recent") end

		bRefuseNewer = true
		Switch(bot, current)
		P:Arrive(bot)
		if (bot:GetCharacter() != older) then fail("a refused character was loaded, or the next was not") end
	end)
end)

GWH.Check("arriving: the train is built over open sky, closed in and walkable", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end

	local train = P.train
	if (!train) then return fail("no train on " .. game.GetMap()) end

	local layout = P.layout

	if (!P:TrainFits(train.place)) then fail("the train is not clear of the world") end
	if (#train.mirrors != layout.cabins) then fail(#train.mirrors .. " mirrors for " .. layout.cabins .. " cabins") end
	if (!IsValid(train.doors.side)) then fail("no side door") end

	local glass = 0

	for _, entity in ipairs(train.entities) do
		if (!IsValid(entity)) then fail("a piece of the set is gone") end
		if (entity.GetKind and entity:GetKind() == "glass") then glass = glass + 1 end
	end

	if (glass != #layout.Windows()) then fail(glass .. " panes for " .. #layout.Windows() .. " windows") end

	for i = 1, layout.cabins do
		if (!IsValid(train.doors[i])) then fail("cabin " .. i .. " has no door") end

		-- the floor holds someone up, and a shut door keeps them in
		local bed = P:ToWorld(train.place, layout.Bed(i))
		local down = util.TraceLine({start = bed + Vector(0, 0, 40), endpos = bed - Vector(0, 0, 80)})

		if (!IsValid(down.Entity) or down.Entity:GetClass() != "ix_arriving_piece") then
			fail("cabin " .. i .. "'s floor is not under its bed")
		end

		local start, d = layout.CabinStart(i), layout.cabinDoor
		local inside = P:ToWorld(train.place, Vector(start + (d.from + d.to) / 2, layout.cabinFrom + 20, 40))
		local outside = P:ToWorld(train.place, Vector(start + (d.from + d.to) / 2, layout.corridor - 20, 40))
		local through = util.TraceLine({start = inside, endpos = outside})

		if (!train.doors[i]:GetOpened() and through.Entity != train.doors[i]) then
			fail("cabin " .. i .. "'s shut door does not block its doorway")
		end
	end
end)

GWH.Check("arriving: doors slide into their own walls and never into anyone", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end
	if (!P.train) then return {skipped = "no train on this map"} end

	local layout = P.layout
	local t = layout.thick

	-- open, each door lies inside its wall's thickness and clear of every opening in that wall
	for _, piece in ipairs(layout.Pieces()) do
		if (piece.kind == "door") then
			local mins, maxs = piece.mins + piece.slide, piece.maxs + piece.slide
			local wallFrom, wallTo = 0, 0
			local holes = {}

			if (piece.door == "side") then
				wallFrom, wallTo = -t, 0

				for i = 1, layout.cabins do
					local start, w = layout.CabinStart(i), layout.corridorWindow
					holes[#holes + 1] = {start + w.from, start + w.to}
				end
			else
				wallFrom, wallTo = layout.corridor, layout.cabinFrom

				for i = 1, layout.cabins do
					local start, d = layout.CabinStart(i), layout.cabinDoor
					holes[#holes + 1] = {start + d.from, start + d.to}
				end
			end

			local name = piece.door or ("cabin " .. piece.cabin)

			if (mins.y < wallFrom or maxs.y > wallTo) then fail(name .. "'s door leaves its wall's thickness") end

			for _, hole in ipairs(holes) do
				if (mins.x < hole[2] and maxs.x > hole[1]) then fail(name .. "'s door slides across an opening") end
			end
		end
	end

	-- a door about to move into someone waits
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	ResetBot(bot)

	local door = P.train.doors[1]
	local start, d = layout.CabinStart(1), layout.cabinDoor
	local doorway = P:ToWorld(P.train.place, Vector(start + (d.from + d.to) / 2, (layout.corridor + layout.cabinFrom) / 2, 1))

	Scoped(function(defer)
		defer(function() StandOnSpawn(bot) end)

		bot:SetPos(doorway)
		if (!door:WouldHitPlayer(door.home)) then fail("a door shutting on someone in its doorway would not wait") end

		StandOnSpawn(bot)
		if (door:WouldHitPlayer(door.home)) then fail("a door waits for someone who isn't there") end
	end)
end)

GWH.Check("arriving: a newcomer chooses at the mirror and keeping it opens their cabin door", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end
	if (!P.train) then return {skipped = "no train on this map"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	ResetBot(bot)

	local character = bot:GetCharacter()

	Scoped(function(defer)
		local model, description, name = character:GetModel(), character:GetDescription(), character:GetName()
		local data = {arrival = character:GetData("arrival"), stature = character:GetData("stature"), age = character:GetData("age")}
		local arriveAt = P.arriveAt

		defer(function()
			bot:SetNetVar("arrivingMirror", nil)
			P:FreeCabin(bot)

			for i = 1, P.layout.cabins do
				P:SetDoor(P.train.doors[i], false)
			end

			-- (each key by name: a key that was nil must go back to nil, which pairs would skip)
			for _, key in ipairs({"arrival", "stature", "age"}) do
				character:SetData(key, data[key])
			end

			character:SetModel(model)
			bot:SetModel(model)
			character:SetDescription(description)
			character:SetName(name)
			P:ApplyScale(bot, character)
			P.arriveAt = arriveAt
			P:UpdateTransmit()
			StandOnSpawn(bot)
		end)

		-- a newcomer: nameless, in a cabin
		character:SetName("")
		character:SetData("arrival", P.states.cabin)
		P:PutAboard(bot, character)

		local cabin = P:CabinOf(bot)
		if (!cabin) then return fail("the newcomer was given no cabin") end

		local door, mirror = P.train.doors[cabin], P.train.mirrors[cabin]

		if (door:GetOpened()) then fail("the cabin door is open as they wake") end
		if (!P:IsAboard(bot)) then fail("the newcomer is not aboard") end

		P:LookIn(bot, mirror)
		if (P:GetMirror(bot) != mirror) then return fail("looking in the mirror did nothing") end

		-- (earlier checks dress the shared bot in other factions' models: start from a citizen's body)
		local before = P:GetBodies()[1]

		character:SetModel(before)
		bot:SetModel(before)

		P:Choose(bot, character, mirror, "bodyNext")
		if (character:GetModel() == before or bot:GetModel() != character:GetModel()) then fail("the next body was not tried") end
		if (!table.HasValue(P:GetBodies(), character:GetModel())) then fail("the body tried is not a citizen's") end

		P:Choose(bot, character, mirror, "bodyBack")
		if (character:GetModel() != before) then fail("the body before was not tried") end

		P:Choose(bot, character, mirror, "taller")
		P:Choose(bot, character, mirror, "taller")
		if (character:GetData("stature") != P.middleStature + 2) then fail("taller twice is " .. tostring(character:GetData("stature"))) end
		if (math.abs(bot:GetModelScale() - P.statures[P.middleStature + 2]) > 0.001) then fail("the body is drawn at " .. bot:GetModelScale()) end
		if (bot:OBBMaxs().x > 16.01) then fail("a taller body collides wider: " .. tostring(bot:OBBMaxs())) end

		for _ = 1, 10 do
			P:Choose(bot, character, mirror, "taller")
		end

		if (character:GetData("stature") != #P.statures) then fail("height goes past the tallest") end

		P:Choose(bot, character, mirror, "older")
		if (character:GetData("age") != P.middleAge + 1) then fail("older is " .. tostring(character:GetData("age"))) end

		P:Choose(bot, character, mirror, "keep")

		local seen = P:Seen(character:GetModel(), character:GetData("stature"), character:GetData("age"))

		if (character:GetDescription() != seen) then fail("kept as '" .. character:GetDescription() .. "', not '" .. seen .. "'") end
		if (P:GetState(character) != P.states.aboard) then fail("keeping left them " .. tostring(P:GetState(character))) end
		if (!door:GetOpened()) then fail("keeping did not open the cabin door") end
		if (P:GetMirror(bot)) then fail("keeping did not let go of the mirror") end
		if (!P.arriveAt) then fail("leaving the cabin did not start the ride in") end
	end)
end)

GWH.Check("arriving: a mirror put up on a wall stays with the map and can be taken away", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		local saved = table.Copy(P:GetData())

		defer(function()
			P:SetData(saved)
			P:Build()
		end)

		local origin = bot:GetPos() + Vector(0, 0, 4000)
		local mirror = P:AddMirror(origin, 90)

		if (!IsValid(mirror) or mirror:GetOnTrain()) then return fail("no mirror of its own was put up") end
		if (#P:GetPlacedMirrors() != #(saved.mirrors or {}) + 1) then fail("the mirror was not kept with the map") end

		-- the map starting again brings it back
		P:Build()

		local found

		for _, entity in ipairs(ents.FindByClass("ix_arriving_mirror")) do
			if (!entity:GetOnTrain() and entity:GetPos():DistToSqr(origin) < 1) then found = entity end
		end

		if (!found) then return fail("the kept mirror did not come back with the map") end
		if (math.abs(math.AngleDifference(found:GetAngles().y, 90)) > 1) then fail("it came back facing " .. found:GetAngles().y) end

		P:RemoveMirror(found)

		if (IsValid(found) and !found:IsMarkedForDeletion()) then fail("the mirror was not taken away") end
		if (#P:GetPlacedMirrors() != #(saved.mirrors or {})) then fail("the map still keeps the mirror") end
	end)
end)

GWH.Check("arriving: someone with a name only looks in a mirror", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	ResetBot(bot)

	local character = bot:GetCharacter()

	Scoped(function(defer)
		local saved = table.Copy(P:GetData())
		local model, description, stature = character:GetModel(), character:GetDescription(), character:GetData("stature")
		local forward = Angle(0, bot:EyeAngles().y, 0):Forward()
		local mirror = P:AddMirror(bot:GetPos() + forward * 60 + Vector(0, 0, 60), (-forward):Angle().y)

		defer(function()
			bot:SetNetVar("arrivingMirror", nil)

			if (IsValid(mirror)) then P:RemoveMirror(mirror) end

			P:SetData(saved)
			character:SetModel(model)
			bot:SetModel(model)
			character:SetDescription(description)
			character:SetData("stature", stature)
			P:ApplyScale(bot, character)
		end)

		if (P:IsNameless(character)) then return fail("the bot has no name") end

		P:LookIn(bot, mirror)
		if (P:GetMirror(bot) != mirror) then return fail("someone with a name could not look in the mirror") end

		P:Choose(bot, character, mirror, "bodyNext")
		P:Choose(bot, character, mirror, "taller")
		P:Choose(bot, character, mirror, "older")

		if (character:GetModel() != model or character:GetData("stature") != stature) then
			fail("someone with a name changed who they are at a mirror")
		end

		P:Choose(bot, character, mirror, "keep")

		if (character:GetDescription() != description) then fail("stepping away rewrote their description") end
		if (P:GetMirror(bot)) then fail("Use did not step them away from the mirror") end
	end)
end)

GWH.Check("arriving: a newcomer's loadout leaves the papers to the desk", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()
	local faction = ix.faction.indices[FACTION_CITIZEN]

	Scoped(function(defer)
		local before = {}

		for item in inventory:Iter() do
			before[item.id] = true
		end

		local arrival = character:GetData("arrival")

		defer(function()
			for item in inventory:Iter() do
				if (!before[item.id]) then item:Remove() end
			end

			character:SetData("arrival", arrival)
		end)

		character:SetData("arrival", P.states.cabin)
		faction:OnCharacterCreated(bot, character)

		for item in inventory:Iter() do
			if (!before[item.id] and item.uniqueID == "cid") then fail("a newcomer was given papers before the desk") end
		end
	end)
end)

GWH.Check("arriving: the desk names a newcomer and hands them a number and papers", function(fail)
	local P = Plugin()
	if (!P) then return {skipped = "arriving not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()

	Scoped(function(defer)
		local name, cid, arrival = character:GetName(), character:GetData("cid"), character:GetData("arrival")
		local before = {}

		for item in inventory:Iter() do
			before[item.id] = true
		end

		defer(function()
			for item in inventory:Iter() do
				if (!before[item.id]) then item:Remove() end
			end

			character:SetName(name)
			character:SetData("cid", cid)
			character:SetData("arrival", arrival)
		end)

		character:SetName("")
		character:SetData("arrival", P.states.station)

		if (!P:IsNameless(character)) then fail("a nameless character is not nameless") end

		P:Register(bot, character, "Testy Arrival", "12345")

		if (character:GetName() != "Testy Arrival") then fail("the name taken is " .. character:GetName()) end
		if (character:GetData("cid") != "12345") then fail("the number kept is " .. tostring(character:GetData("cid"))) end
		if (P:GetState(character) != nil) then fail("named, they're still " .. tostring(P:GetState(character))) end

		local papers

		for item in inventory:Iter() do
			if (!before[item.id] and item.uniqueID == "cid") then papers = item end
		end

		if (!papers) then return fail("no papers were handed over") end
		if (papers:GetData("name") != "Testy Arrival" or papers:GetData("id") != "12345") then
			fail("the papers say " .. tostring(papers:GetData("name")) .. ", " .. tostring(papers:GetData("id")))
		end
	end)
end)
