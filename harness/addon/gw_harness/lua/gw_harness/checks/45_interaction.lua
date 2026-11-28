-- Interaction (interaction, worldui): the plugins, config, command, chat class and phrases; the tooltip
-- plugins are gone; a tap through the ixInteractionUse receiver uses a thing only for a player who can act,
-- within reach and with a clear line (not through a prop or the world), and takes a stack through the stack's
-- own pickup; held-Use options still go through Helix's ixEntityMenuSelect and refuse who cannot act;
-- Examine's wording. The outline, the world panel and the tooltip rows themselves are client-only and are
-- judged in a play session.

local Lib = GWH.Lib
local S = Lib.NewS()
local Scoped, Plugin, RemoveAll, ClearAround = Lib.Scoped, Lib.Plugin, Lib.RemoveAll, Lib.ClearAround

local function Has(text, phrase)
	return string.find(text, phrase, 1, true) != nil
end

-- The full reset, plus what these checks also change: the tap rate limit and freezing.
local function ResetBot(bot)
	Lib.ResetBotFully(bot)
	bot.ixNextInteractionUse = nil

	if (bot:IsFrozen()) then
		bot:Freeze(false)
	end
end

-- the shared one, looking down a little, as a player looking at the floor in front of them
local function StandOnSpawn(bot)
	Lib.StandOnSpawn(bot)
	bot:SetEyeAngles(Angle(20, 0, 0))
end

-- What a solid line from the bot's eyes to the entity's middle hits first, for a failure message.
local function Blocker(bot, entity)
	local trace = util.TraceLine({start = bot:GetShootPos(), endpos = entity:WorldSpaceCenter(), filter = bot, mask = MASK_SOLID})
	local hit = trace.Entity

	return (trace.StartSolid and "starts solid, " or "") .. (!trace.Hit and "nothing" or (IsValid(hit) and
		(hit:GetClass() .. " " .. (hit:IsPlayer() and hit:Name() or "") .. " at " .. tostring(hit:GetPos())) or "the world")) ..
		", bot at " .. tostring(bot:GetPos())
end

-- Runs a net receiver as if `client` had sent it, with the given values read in order.
local Receive = S.Net

local function SetState(bot, state)
	if (state == "downed") then
		bot:SetRagdolled(true)
	elseif (state == "tied") then
		bot:SetRestricted(true)
	elseif (state == "frozen") then
		bot:Freeze(true)
	elseif (state == "dead") then
		local position = bot:GetPos()
		bot:Kill()
		bot:SetPos(position)
	end
end

GWH.Check("interaction: plugins, config, command, chat class and phrases exist", function(fail)
	local plugin = Plugin("interaction", fail)

	if (!plugin) then return end
	if (!Plugin("worldui", fail)) then return end

	local config = ix.config.stored.interactionHighlight

	if (!config) then
		fail("config interactionHighlight is not registered")
	else
		if (config.default != true) then fail("interactionHighlight does not default to on") end
		if (!config.data or config.data.category != "Immersion") then fail("interactionHighlight is not under Immersion") end
	end

	if (!ix.command.list.examine) then fail("/Examine is not registered") end

	local class = ix.chat.classes.examine

	if (!class) then
		fail("the examine chat class is not registered")
	else
		if (class.prefix) then fail("the examine chat class can be typed into chat") end

		local bot = GWH.Bot()
		local other = {GetPos = function() return vector_origin end}

		if (bot and class:CanHear(bot, other) != false) then fail("someone else can hear an examine line") end
		if (bot and class:CanHear(bot, bot) != true) then fail("the examiner cannot hear their own examine line") end
	end

	for _, v in ipairs({"ixInteractionUse", "ixInteractionExamine", "ixInteractionRefused"}) do
		if (!util.NetworkStringToID(v) or util.NetworkStringToID(v) == 0) then fail("net message " .. v .. " is not registered") end
	end

	local english, spanish = ix.lang.stored.english, ix.lang.stored.spanish

	for _, key in ipairs({"cmdExamine", "interactTake", "interactOpen", "interactTalk", "interactSearch",
		"interactUntie", "interactUse", "interactExamine", "examineNothing", "examineBody", "examineDeceased",
		"examineUnconscious", "examineLocked", "examineUnlocked", "examineScavenge"}) do
		if (!english[key]) then fail("no English phrase " .. key) end
		if (!spanish[key]) then fail("no Spanish phrase " .. key) end
	end
end)

GWH.Check("interaction: the tooltip plugins are gone and nothing refers to them", function(fail)
	for _, v in ipairs({"entity_info", "livetooltips"}) do
		if (ix.plugin.list[v]) then fail(v .. " is still loaded") end
	end

	-- every Lua file of the schema and its plugins
	local found = {}

	local function Walk(path)
		local files, folders = file.Find(path .. "/*", "GAME")

		for _, v in ipairs(files or {}) do
			if (v:EndsWith(".lua")) then
				local text = file.Read(path .. "/" .. v, "GAME") or ""

				for _, word in ipairs({"entity_info", "livetooltips", "GetEntityInfoState", "ix.gui.entityInfo"}) do
					if (Has(text, word)) then
						found[#found + 1] = path .. "/" .. v .. " mentions " .. word
					end
				end
			end
		end

		for _, v in ipairs(folders or {}) do
			Walk(path .. "/" .. v)
		end
	end

	Walk("gamemodes/ixhl2rp")

	for _, v in ipairs(found) do
		-- this plugin removes a tooltip left open by a Lua refresh, and says so
		if (!Has(v, "plugins/interaction/cl_plugin.lua mentions ix.gui.entityInfo")) then
			fail(v)
		end
	end
end)

GWH.Check("interaction: a tap uses a thing only for a player who can", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local plugin = Plugin("interaction", fail)
	if (!plugin) then return end

	local inventory = bot:GetCharacter():GetInventory()

	Scoped(function(defer)
		local home = bot:GetPos()
		defer(function() bot:SetPos(home) end)
		defer(function() ResetBot(bot) RemoveAll(inventory, "water") end)

		local function Try(state, distance)
			ResetBot(bot)
			StandOnSpawn(bot)
			RemoveAll(inventory, "water")

			local spawned

			ix.item.Spawn("water", bot:GetShootPos() + bot:GetAimVector() * distance, function(item, entity)
				spawned = {item = item, entity = entity}
			end, angle_zero)

			if (!spawned or !IsValid(spawned.entity)) then
				fail("could not spawn water for the " .. state .. " case")
				return
			end

			local entity = spawned.entity
			defer(function() if (IsValid(entity)) then entity:Remove() end end)

			-- frozen where it was put, so it is still within reach on the next line
			local physics = entity:GetPhysicsObject()
			if (IsValid(physics)) then physics:EnableMotion(false) end

			ClearAround(bot, entity)
			SetState(bot, state)

			local bCanUse = plugin:CanUseEntity(bot, entity)

			local blocker = Blocker(bot, entity)

			Receive("ixInteractionUse", bot, {entity})

			return inventory:HasItem("water") != false, IsValid(entity) and !entity:IsMarkedForDeletion(), bCanUse,
				IsValid(entity) and bot:GetShootPos():Distance(entity:NearestPoint(bot:GetShootPos())), blocker
		end

		local bTaken, bLeft, bCanUse, distance, blocker = Try("standing", 30)

		if (!bTaken or bLeft) then
			fail("a standing player within reach could not take an item with a tap (taken " .. tostring(bTaken) ..
				", left in the world " .. tostring(bLeft) .. ", CanUseEntity " .. tostring(bCanUse) .. ", " ..
				tostring(distance) .. " units, free slot " .. tostring(inventory:FindEmptySlot(1, 1) != nil) .. ", line hits " .. tostring(blocker) .. ")")
		end

		for _, state in ipairs({"downed", "tied", "frozen", "dead"}) do
			bTaken, bLeft = Try(state, 30)

			if (bTaken or !bLeft) then fail("a " .. state .. " player took an item with a tap") end
		end

		bTaken, bLeft = Try("standing", 300)

		if (bTaken or !bLeft) then fail("a player 300 units away took an item with a tap") end

		-- the validation on its own, for anything else that asks
		ResetBot(bot)
		if (plugin:CanUseEntity(bot, game.GetWorld())) then fail("the world can be used") end
		if (plugin:CanUseEntity(bot, bot)) then fail("a player can use themselves") end
	end)
end)

-- Places `entity` frozen at `position`.
local function Freeze(entity, position)
	entity:SetPos(position)

	local physics = entity:GetPhysicsObject()
	if (IsValid(physics)) then physics:EnableMotion(false) physics:SetPos(position) end
end

GWH.Check("interaction: a tap does not reach through a prop or the world", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local plugin = Plugin("interaction", fail)
	if (!plugin) then return end

	Scoped(function(defer)
		local home = bot:GetPos()
		defer(function() bot:SetPos(home) end)
		defer(function() ResetBot(bot) end)

		ResetBot(bot)
		StandOnSpawn(bot)
		bot:SetEyeAngles(Angle(0, 0, 0))

		local eye = bot:GetShootPos()
		local back = -bot:GetForward()

		-- money 88 units behind the bot, facing away, with a crate in between
		local money = ix.currency.Spawn(eye + back * 88, 25)
		if (!IsValid(money)) then return fail("could not spawn money") end
		defer(function() if (IsValid(money)) then money:Remove() end end)
		Freeze(money, eye + back * 88)

		ClearAround(bot, money)

		local crate = ents.Create("prop_physics")
		crate:SetModel("models/props_junk/wood_crate001a.mdl")
		crate:Spawn()
		defer(function() if (IsValid(crate)) then crate:Remove() end end)
		Freeze(crate, eye + back * 50)

		local money0 = bot:GetCharacter():GetMoney()

		bot.ixNextInteractionUse = nil
		Receive("ixInteractionUse", bot, {money})

		if (bot:GetCharacter():GetMoney() != money0 or !IsValid(money) or money:IsMarkedForDeletion()) then
			fail("money behind a crate was picked up")
		end

		if (plugin:CanUseEntity(bot, money)) then fail("CanUseEntity allows money behind a crate") end

		-- the crate moved away, the same money is in reach and is picked up, facing away or not
		crate:SetPos(crate:GetPos() + Vector(0, 0, 4000))
		bot.ixNextInteractionUse = nil

		if (!plugin:CanUseEntity(bot, money)) then
			fail("CanUseEntity refuses money in plain reach once the crate is gone")
		end

		-- an item under the floor, within reach of the eyes but through the world
		local floor = util.TraceLine({start = eye, endpos = eye - Vector(0, 0, 200), filter = bot, mask = MASK_SOLID_BRUSHONLY})

		if (!floor.HitWorld or eye.z - floor.HitPos.z > 80) then
			return fail("no floor within reach under the spawn point to test against")
		end

		local below = floor.HitPos - Vector(0, 0, 16)

		local spawned

		ix.item.Spawn("water", below, function(item, entity) spawned = entity end, angle_zero)
		if (!IsValid(spawned)) then return fail("could not spawn water under the floor") end
		defer(function() if (IsValid(spawned)) then spawned:Remove() end end)
		Freeze(spawned, below)

		if (plugin:CanUseEntity(bot, spawned)) then fail("CanUseEntity allows an item under the floor") end
	end)
end)

GWH.Check("interaction: a tap takes a stack and the stack's own pickup still decides", function(fail)
	local bot = GWH.Bot()
	if (!bot or !ix.stack) then return fail("no bot or ix.stack") end

	local inventory = bot:GetCharacter():GetInventory()

	Scoped(function(defer)
		local home = bot:GetPos()
		defer(function() bot:SetPos(home) end)
		defer(function() ResetBot(bot) RemoveAll(inventory, "metal_scrap") end)

		ResetBot(bot)
		StandOnSpawn(bot)
		RemoveAll(inventory, "metal_scrap")
		ix.stack.Give(inventory, "metal_scrap", 2)

		local spawned

		ix.stack.Spawn("metal_scrap", bot:GetShootPos() + bot:GetAimVector() * 30, 3, angle_zero, function(item, entity)
			spawned = {item = item, entity = entity}
		end)

		if (!spawned or !IsValid(spawned.entity)) then return fail("could not spawn a stack") end

		local entity = spawned.entity
		defer(function() if (IsValid(entity)) then entity:Remove() end end)

		local physics = entity:GetPhysicsObject()
		if (IsValid(physics)) then physics:EnableMotion(false) end

		ClearAround(bot, entity)
		Receive("ixInteractionUse", bot, {entity})

		if (ix.stack.Count(inventory, "metal_scrap") != 5) then
			fail("tapping a stack of 3 with 2 held left " .. tostring(ix.stack.Count(inventory, "metal_scrap")) .. " held")
		end
	end)
end)

GWH.Check("interaction: options still go through Helix's menu receiver and refuse who cannot act", function(fail)
	local bot = GWH.Bot()
	if (!bot or !ix.station) then return fail("no bot or ix.station") end

	Scoped(function(defer)
		local home = bot:GetPos()
		defer(function() bot:SetPos(home) end)
		defer(function() ResetBot(bot) end)

		local function Try(state, offset)
			ResetBot(bot)

			local smelter = ix.station.Spawn("smelter", home + Vector(0, 0, 600), angle_zero, bot:GetCharacter():GetID())

			if (!IsValid(smelter)) then
				fail("could not spawn a smelter")
				return
			end

			defer(function() if (IsValid(smelter)) then smelter:Remove() end end)

			bot:SetPos(smelter:GetPos() + offset)
			bot.ixNextStationAction = 0
			SetState(bot, state)

			-- what the world panel's "Pick Up" row sends: ix.menu.NetworkChoice(entity, label, data)
			Receive("ixEntityMenuSelect", bot, {smelter, "Pick Up", {action = "pickup"}})

			return !IsValid(smelter) or smelter:IsMarkedForDeletion()
		end

		if (!Try("standing", Vector(60, 0, 0))) then fail("a standing player next to their smelter could not pick it up") end

		for _, state in ipairs({"downed", "tied", "dead"}) do
			if (Try(state, Vector(60, 0, 0))) then fail("a " .. state .. " player picked a smelter up") end
		end

		if (Try("standing", Vector(400, 0, 0))) then fail("a player 400 units away picked a smelter up") end

		RemoveAll(bot:GetCharacter():GetInventory(), "smelter")
	end)
end)

GWH.Check("interaction: Examine describes things in words", function(fail)
	local plugin = Plugin("interaction", fail)
	local bot = GWH.Bot()
	if (!plugin) then return end
	if (!bot) then return fail("no bot") end

	-- the rows Helix's item tooltip and the stack's PopulateTooltip would add, in order
	local scrap = ix.item.list.metal_scrap

	if (scrap and ix.stack) then
		local text = plugin:ComposeExamine({
			{id = "name", text = scrap.name},
			{id = "description", text = scrap.description},
			{id = "quantity", text = L("stackQuantity", bot, ix.stack.Format("metal_scrap", 5), ix.stack.Format("metal_scrap", scrap.stackLimit))}
		}, nil, bot)

		if (!text:StartWith(scrap.name .. ".")) then fail("a stack's description does not start with its name: " .. text) end
		if (!Has(text, "Quantity: " .. ix.stack.Format("metal_scrap", 5))) then fail("a stack's description has no quantity: " .. text) end
		if (!text:EndsWith(".")) then fail("a stack's description does not end a sentence: " .. text) end
	else
		fail("no metal_scrap item or ix.stack")
	end

	-- an item with no rows of its own beyond name and description
	local water = ix.item.list.water

	if (water) then
		local text = plugin:ComposeExamine({{id = "name", text = water.name}, {id = "description", text = water.description}}, nil, bot)

		if (!Has(text, water.name) or !Has(text, string.Trim(water.description):sub(1, 10))) then
			fail("an item's description lacks its name or description: " .. text)
		end
	end

	-- a container: the lock glyph row is left out and the lock is said in words
	local rows = {{id = "icon", text = "P"}, {id = "name", text = "Wardrobe"}, {id = "description", text = "A tall wooden wardrobe"}}
	local locked = plugin:ComposeExamine(rows, {bLocked = true}, bot)
	local unlocked = plugin:ComposeExamine(rows, {bLocked = false}, bot)

	if (Has(locked, "P.") or !Has(locked, "Wardrobe. A tall wooden wardrobe.")) then fail("a container reads wrongly: " .. locked) end
	if (!Has(locked, L("examineLocked", bot))) then fail("a locked container is not said to be locked: " .. locked) end
	if (!Has(unlocked, L("examineUnlocked", bot))) then fail("an unlocked container is not said to be unlocked: " .. unlocked) end

	-- a corpse: the injury read from the owner goes, "Seems deceased" follows the name, no numbers
	local corpse = plugin:ComposeExamine({
		{id = "name", text = "John Doe"},
		{id = "injureText", text = L("injMajor", bot)},
		{id = "description", text = "A tall man in a worn jacket"}
	}, {bDeceased = true}, bot)

	if (!Has(corpse, "John Doe. " .. L("examineDeceased", bot))) then fail("a corpse is not said to be dead after its name: " .. corpse) end
	if (Has(corpse, L("injMajor", bot))) then fail("a corpse still reads its owner's injuries: " .. corpse) end
	if (corpse:find("%d")) then fail("a corpse is described with numbers: " .. corpse) end

	local nameless = plugin:ComposeExamine({}, {bDeceased = true}, bot)

	if (!Has(nameless, L("examineBody", bot)) or !Has(nameless, L("examineDeceased", bot))) then
		fail("a corpse with no rows does not read as a dead body: " .. nameless)
	end

	-- a stranger is their description, never "Unknown"; a tied one says so
	local stranger = plugin:ComposeExamine({
		{id = "name", text = L("unknown", bot)},
		{id = "ziptie", text = L("tiedUp", bot)},
		{id = "description", text = "A tall man in a worn jacket"}
	}, nil, bot)

	if (Has(stranger, L("unknown", bot))) then fail("an unrecognised character is called Unknown: " .. stranger) end
	if (!Has(stranger, "A tall man in a worn jacket.") or !Has(stranger, L("tiedUp", bot))) then
		fail("an unrecognised tied character reads wrongly: " .. stranger)
	end

	if (plugin:ComposeExamine({}, nil, bot) != L("examineNothing", bot)) then fail("nothing to describe does not say so") end

	-- the deceased rule on real ragdolls
	local ragdoll = ents.Create("prop_ragdoll")
	ragdoll:SetModel("models/player/group01/male_01.mdl")
	ragdoll:SetPos(bot:GetPos() + Vector(0, 0, 900))
	ragdoll:Spawn()

	if (plugin:IsDeceased(ragdoll)) then fail("a plain ragdoll counts as deceased") end

	ragdoll:SetNetVar("isDeadPlayer", true)

	if (!plugin:IsDeceased(ragdoll)) then fail("a persistent corpse does not count as deceased") end

	ragdoll:Remove()
end)
