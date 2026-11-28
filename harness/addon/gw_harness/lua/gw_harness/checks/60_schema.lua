-- Schema (ixhl2rp/schema): the business menu (who may buy what, prices, flags, items that must not be sold),
-- /SetFreq, faction loadouts, the Combine data and objectives receivers, uniforms, and the saved dispensers,
-- vending machines and forcefields across a map cleanup. Receivers are called the way a net message would
-- call them, with a bot as the sender.
-- Runs after the plugin files: the uniforms check kicks S.Target's bot (also used by 56_datafile.lua to
-- 58_cto.lua), and the last check, a real map cleanup, kicks S.ReviewTarget's bot (also used by 56_datafile.lua
-- to 59_protectionteams.lua) and clears every other check's entities.

local Lib = GWH.Lib
local HasNotice, OtherBot, Scoped, Live = Lib.HasNotice, Lib.OtherBot, Lib.Scoped, Lib.Live

local S = Lib.NewS()

local function CountShipments() return #ents.FindByClass("ix_shipment") end

local function ClearShipments()
	for _, v in ipairs(ents.FindByClass("ix_shipment")) do v:Remove() end
end

-- Buys one of uniqueID through the real receiver; returns whether a shipment came and what it cost.
local function Buy(client, uniqueID, money)
	local character = client:GetCharacter()

	character:SetMoney(money)
	client.ixNextBusiness = nil

	local before = CountShipments()
	S.Net("ixBusinessBuy", client, {1, uniqueID, 1})

	return CountShipments() > before, money - character:GetMoney()
end

local function OptsIn(itemTable)
	return itemTable.factions != nil or itemTable.classes != nil
		or (itemTable.permit != nil and itemTable.base != "base_permits")
end

GWH.Check("schema: business menu only lists items that opt in", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()
	local state = S.Snapshot(bot)
	local listed = {}

	for _, faction in ipairs({FACTION_CITIZEN, FACTION_MPF, FACTION_OTA, FACTION_ADMIN}) do
		S.Become(bot, faction)
		listed[team.GetName(faction)] = 0

		for uniqueID, itemTable in pairs(ix.item.list) do
			if (hook.Run("CanPlayerUseBusiness", bot, uniqueID) != false) then
				listed[team.GetName(faction)] = listed[team.GetName(faction)] + 1

				if (!OptsIn(itemTable)) then
					fail(team.GetName(faction) .. " can buy '" .. uniqueID .. "', which declares no permit, faction or class")
				end
			end
		end
	end

	-- plugin items that do not opt in, unpriced and priced, through the real purchase receiver
	local free, priced

	for uniqueID, itemTable in SortedPairs(ix.item.list) do
		if (itemTable.plugin and !OptsIn(itemTable)) then
			if (!itemTable.price) then
				free = free or uniqueID
			else
				priced = priced or uniqueID
			end
		end
	end

	local function Shipments() return #ents.FindByClass("ix_shipment") end

	for _, faction in ipairs({FACTION_CITIZEN, FACTION_MPF, FACTION_OTA, FACTION_ADMIN}) do
		S.Become(bot, faction)

		for _, probe in ipairs({free, priced}) do
			character:SetMoney(1000)
			bot.ixNextBusiness = nil

			local before = Shipments()
			S.Net("ixBusinessBuy", bot, {1, probe, 1})

			if (Shipments() != before) then
				fail(team.GetName(faction) .. " received a shipment of '" .. tostring(probe) .. "', which does not opt in")
			end
		end
	end

	-- a faction allow-list item is sold, at its price, to that faction only
	S.Become(bot, FACTION_MPF)
	character:SetMoney(100)
	bot.ixNextBusiness = nil

	local before = Shipments()
	S.Net("ixBusinessBuy", bot, {1, "zip_tie", 1})

	if (Shipments() != before + 1) then
		fail("Civil Protection could not buy zip_tie")
	elseif (character:GetMoney() != 100 - ix.item.list.zip_tie.price) then
		fail("zip_tie cost " .. (100 - character:GetMoney()) .. ", expected " .. ix.item.list.zip_tie.price)
	end

	for _, v in ipairs(ents.FindByClass("ix_shipment")) do v:Remove() end

	S.Become(bot, FACTION_CITIZEN)

	if (hook.Run("CanPlayerUseBusiness", bot, "zip_tie") != false) then
		fail("a citizen can buy zip_tie (Civil Protection and OTA only)")
	end

	-- a permit item needs the permit
	if (hook.Run("CanPlayerUseBusiness", bot, "melon") != false) then
		fail("melon is buyable without the consumables permit")
	end

	inventory:Add("permit_consumables")

	if (hook.Run("CanPlayerUseBusiness", bot, "melon") == false) then
		fail("melon is not buyable with the consumables permit")
	end

	if (hook.Run("CanPlayerUseBusiness", bot, "permit_consumables") != false) then
		fail("permits themselves are buyable")
	end

	S.RemoveAll(inventory, "permit_consumables")
	S.Restore(bot, state)

	return {listed = listed, unpricedProbe = free, pricedProbe = priced}
end)

GWH.Check("schema review: business items need a positive price", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.SnapshotWithFlags(bot)
	local itemTable = ix.item.list.zip_tie
	local price = itemTable.price

	S.Become(bot, FACTION_MPF, "MPF-04.51001")

	for _, probe in ipairs({false, 0, -5}) do
		itemTable.price = probe or nil

		local bShipped, cost = Buy(bot, "zip_tie", 100)

		if (bShipped or cost != 0) then
			fail("zip_tie with price " .. tostring(itemTable.price) .. " was sold (cost " .. cost .. ")")
		end
	end

	itemTable.price = price

	local bShipped, cost = Buy(bot, "zip_tie", 100)

	if (!bShipped) then
		fail("a priced zip_tie was not sold to Civil Protection")
	elseif (cost != price) then
		fail("zip_tie cost " .. cost .. ", expected " .. tostring(price))
	end

	-- the schema's allow-listed items that had no price
	for _, uniqueID in ipairs({"ar2ammo", "pistolammo", "smg1ammo", "resistance_uniform", "rmedic_uniform"}) do
		local item = ix.item.list[uniqueID]

		if (item and !(isnumber(item.price) and item.price > 0)) then
			fail(uniqueID .. " has no price")
		end
	end

	ClearShipments()
	S.RestoreWithFlags(bot, state)
end)

GWH.Check("schema review: a held flag opts a flag-only item in", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.SnapshotWithFlags(bot)
	local character = bot:GetCharacter()
	local uniform = ix.item.list.resistance_uniform

	S.Become(bot, FACTION_CITIZEN)
	character:SetFlags("")

	if (hook.Run("CanPlayerUseBusiness", bot, "resistance_uniform") != false) then
		fail("resistance_uniform is buyable without the v flag")
	end

	character:SetFlags("vV")

	local bShipped, cost = Buy(bot, "resistance_uniform", 500)

	if (!bShipped) then
		fail("a citizen holding the v flag could not buy resistance_uniform")
	elseif (cost != uniform.price) then
		fail("resistance_uniform cost " .. cost .. ", expected " .. tostring(uniform.price))
	end

	-- a flag on an item with a class allow-list is an extra requirement, not an opt-in
	if (hook.Run("CanPlayerUseBusiness", bot, "pistolammo") != false) then
		fail("a citizen with the V flag can buy pistolammo, which is limited to elite classes")
	end

	ClearShipments()
	S.RestoreWithFlags(bot, state)
end)

GWH.Check("hygiene: joke and custom items are not sold by the business menu", function(fail)
	local client = OtherBot()

	return Scoped(function(defer)
		local team = client:Team()
		client:SetTeam(FACTION_MPF)
		defer(function() client:SetTeam(team) end)

		for _, uniqueID in ipairs({"baby", "infant_skull", "customitem"}) do
			if (hook.Run("CanPlayerUseBusiness", client, uniqueID) != false) then
				fail(uniqueID .. " can be bought")
			end
		end
	end)
end)

GWH.Check("schema: /SetFreq accepts a valid frequency", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()

	inventory:Add("handheld_radio")

	local radio = inventory:HasItem("handheld_radio")
	if (!radio) then return fail("could not give the bot a radio") end

	S.Command(bot, "/SetFreq 100.0")

	if (character:GetData("frequency") != "100.0" or radio:GetData("frequency") != "100.0") then
		fail("/SetFreq 100.0 left the frequency at " .. tostring(character:GetData("frequency")))
	end

	S.Command(bot, "/SetFreq 451.25")

	if (character:GetData("frequency") != "451.3") then
		fail("/SetFreq 451.25 set " .. tostring(character:GetData("frequency")) .. ", expected 451.3")
	end

	for _, bad in ipairs({"abc", "99.9", "1000"}) do
		S.Command(bot, "/SetFreq " .. bad)

		if (character:GetData("frequency") != "451.3") then
			fail("/SetFreq " .. bad .. " was accepted")
		end
	end

	S.RemoveAll(inventory, "handheld_radio")
	character:SetData("frequency", nil)
end)

GWH.Check("schema: every faction's starting loadout is given", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()
	local cid = character:GetData("cid")
	local expected = {
		[FACTION_CITIZEN] = {suitcase = 1, cid = 1},
		[FACTION_MPF] = {stunstick = 1, pistol = 1, pistolammo = 2},
		[FACTION_OTA] = {pistol = 1, pistolammo = 2, ar2 = 1, ar2ammo = 2}
	}
	local given = {}

	for index, faction in ipairs(ix.faction.indices) do
		if (faction.OnCharacterCreated) then
			local before = {}

			for item in inventory:Iter() do before[item.id] = true end

			local errors = S.Errors(function() faction:OnCharacterCreated(bot, character) end)

			for _, err in ipairs(errors) do fail(faction.name .. ": " .. err) end

			given[faction.name] = {}

			for uniqueID, amount in pairs(expected[index] or {}) do
				local count = S.Count(inventory, uniqueID)
				given[faction.name][uniqueID] = count

				if (ix.item.list[uniqueID] and count < amount) then
					fail(faction.name .. " got " .. count .. " of " .. uniqueID .. ", expected " .. amount)
				end
			end

			for item in inventory:Iter() do
				if (!before[item.id]) then item:Remove() end
			end
		end
	end

	character:SetData("cid", cid)

	-- a loadout naming an item that is not registered is skipped, not an error
	local errors = S.Errors(function()
		Schema:GiveLoadout(character, {{"gwh_unregistered_item", 1}, {"suitcase", 1}})
	end)

	for _, err in ipairs(errors) do fail("missing loadout item: " .. err) end

	if (S.Count(inventory, "suitcase") < 1) then
		fail("an unregistered loadout item stopped the rest of the loadout")
	end

	S.RemoveAll(inventory, "suitcase")

	return given
end)

GWH.Check("schema: data and objective receivers validate their input", function(fail)
	local bot, target = GWH.Bot(), S.Target()
	if (!bot or !target) then return fail("no bots") end

	local state, targetState = S.Snapshot(bot), S.Snapshot(target)
	local targetCharacter = target:GetCharacter()
	local objectives = Schema.CombineObjectives

	S.Become(target, FACTION_CITIZEN)
	targetCharacter:SetData("combineData", nil)

	-- malformed payloads must not throw
	for _, payload in ipairs({{target, 5}, {"x", "text"}, {Entity(0), "text"}, {nil, nil}}) do
		for _, err in ipairs(S.Errors(function() S.Stream("ViewDataUpdate", bot, payload[1], payload[2]) end)) do
			fail("ViewDataUpdate with a bad payload: " .. err)
		end
	end

	for _, err in ipairs(S.Errors(function() S.Stream("ViewObjectivesUpdate", bot, {}) end)) do
		fail("ViewObjectivesUpdate with a table: " .. err)
	end

	S.Become(bot, FACTION_CITIZEN)
	S.Stream("ViewDataUpdate", bot, target, "citizen edit")

	if (targetCharacter:GetData("combineData")) then
		fail("a citizen edited another character's Combine data")
	end

	S.Become(bot, FACTION_MPF, "MPF-RCT.11111")
	S.Stream("ViewDataUpdate", bot, target, "cp edit")

	if (!istable(targetCharacter:GetData("combineData")) or targetCharacter:GetData("combineData").text != "cp edit") then
		fail("Civil Protection could not edit a citizen's Combine data")
	end

	-- objectives need a command rank, and are rate limited
	Schema.CombineObjectives = {text = "before"}
	bot.ixNextObjectivesEdit = nil
	S.Stream("ViewObjectivesUpdate", bot, "recruit")

	if (Schema.CombineObjectives.text != "before") then
		fail("a recruit edited the objectives")
	end

	S.Become(bot, FACTION_MPF, "MPF-OfC.11111")
	S.Stream("ViewObjectivesUpdate", bot, "officer")

	if (Schema.CombineObjectives.text != "officer") then
		fail("an OfC could not edit the objectives")
	end

	S.Stream("ViewObjectivesUpdate", bot, "again")

	if (Schema.CombineObjectives.text != "officer") then
		fail("objective edits are not rate limited")
	end

	-- a name change on a character without a player
	local ghost = {GetPlayer = function() return NULL end}

	for _, err in ipairs(S.Errors(function() Schema:CharacterVarChanged(ghost, "name", "a", "b") end)) do
		fail("CharacterVarChanged without a player: " .. err)
	end

	Schema.CombineObjectives = objectives
	ix.data.Set("combineObjectives", objectives, false, true)
	bot.ixNextObjectivesEdit = nil
	targetCharacter:SetData("combineData", nil)
	S.Restore(bot, state)
	S.Restore(target, targetState)
end)

GWH.Check("schema review: Overwatch may edit the objectives", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.SnapshotWithFlags(bot)
	local objectives = Schema.CombineObjectives

	S.Become(bot, FACTION_OTA, "OTA-OWS.51002")
	Schema.CombineObjectives = {text = "before"}
	bot.ixNextObjectivesEdit = nil

	S.Stream("ViewObjectivesUpdate", bot, "overwatch")

	if (Schema.CombineObjectives.text != "overwatch") then fail("an Overwatch soldier could not edit the objectives") end

	Schema.CombineObjectives = objectives
	ix.data.Set("combineObjectives", objectives, false, true)
	bot.ixNextObjectivesEdit = nil
	S.RestoreWithFlags(bot, state)
end)

GWH.Check("schema review: Combine data edits are rate limited", function(fail)
	local bot, target = GWH.Bot(), S.ReviewTarget()
	if (!bot or !target) then return fail("no bots") end

	local state, targetState = S.SnapshotWithFlags(bot), S.SnapshotWithFlags(target)
	local targetCharacter = target:GetCharacter()

	S.Become(bot, FACTION_MPF, "MPF-04.51003")
	S.Become(target, FACTION_CITIZEN)
	targetCharacter:SetData("combineData", nil)
	bot.ixNextDataEdit = nil

	S.Stream("ViewDataUpdate", bot, target, "first")

	local notices = S.Notices(bot, function()
		for i = 1, 20 do S.Stream("ViewDataUpdate", bot, target, "flood " .. i) end
	end)

	local data = targetCharacter:GetData("combineData")

	if (!istable(data) or data.text != "first") then
		fail("21 edits in one tick left the text at " .. tostring(istable(data) and data.text))
	end

	if (!HasNotice(notices, "wait")) then fail("a refused Combine data edit sent no notice") end

	bot.ixNextDataEdit = nil
	S.Stream("ViewDataUpdate", bot, target, "later")

	if (targetCharacter:GetData("combineData", {}).text != "later") then fail("an edit after the cooldown was refused") end

	targetCharacter:SetData("combineData", nil)
	bot.ixNextDataEdit = nil
	S.RestoreWithFlags(bot, state)
	S.RestoreWithFlags(target, targetState)
end)

GWH.Check("schema: uniforms change citizen models", function(fail)
	local cases = {
		{"models/player/zelpa/male_03_extended.mdl", "group03", "models/humans/group03/male_03.mdl"},
		{"models/player/zelpa/female_07_extended.mdl", "group03m", "models/humans/group03m/female_07.mdl"},
		{"models/player/zelpa/male_11_extended.mdl", "group03", "models/humans/group03/male_01.mdl"},
		{"models/humans/group01/female_02.mdl", "group03", "models/humans/group03/female_02.mdl"},
		{"models/police.mdl", "group03", "models/police.mdl"}
	}

	for _, case in ipairs(cases) do
		local result = Schema:GetUniformModel(case[1], case[2])

		if (result != case[3]) then fail(case[1] .. " -> " .. tostring(result) .. ", expected " .. case[3]) end
		if (result != case[1] and !util.IsValidModel(result)) then fail(result .. " is not a valid model") end
	end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.Snapshot(bot)
	local character = bot:GetCharacter()
	local inventory = character:GetInventory()
	local zelpa = "models/player/zelpa/male_03_extended.mdl"

	S.Become(bot, FACTION_CITIZEN)
	character:SetModel(zelpa)

	for uniqueID, expected in pairs({resistance_uniform = "models/humans/group03/male_03.mdl", rmedic_uniform = "models/humans/group03m/male_03.mdl"}) do
		inventory:Add(uniqueID)

		local item = inventory:HasItem(uniqueID)

		if (!item) then
			fail("could not give " .. uniqueID)
		else
			item.player = bot
			item.functions.Equip.OnRun(item)

			if (character:GetModel() != expected) then fail(uniqueID .. " gave model " .. character:GetModel()) end

			item.functions.EquipUn.OnRun(item)

			if (character:GetModel() != zelpa) then fail(uniqueID .. " did not restore the model, left " .. character:GetModel()) end

			item:Remove()
		end
	end

	S.Restore(bot, state)

	-- S.Target's bot is not needed after this: 56_datafile.lua to 58_cto.lua run earlier
	local target = S.Target()

	if (IsValid(target)) then target:Kick("gw_harness") end
end)

-- Last of the feature checks (only 90_teardown.lua runs after it): a real map cleanup also clears every
-- other check's entities.
-- A vending machine (ix_vendingmachine) says why it will not sell; a sale is only seen and heard (the drink drops
-- out, the machine sounds, the price is on its face), and an empty button refilled by the Combine is heard too. The
-- spawn is made synchronous and the aimed button fixed, so the check needs no database round trip or aim.
GWH.Check("schema: a vending machine says why it refuses, and a sale or restock is not announced", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local character = bot:GetCharacter()
	local state = S.Snapshot(bot)

	local machine = ents.Create("ix_vendingmachine")
	machine:SetPos(Vector(0, 0, 3000))
	machine:Spawn()

	Scoped(function(defer)
		defer(function()
			if (IsValid(machine)) then machine:Remove() end
			S.Restore(bot, state)
		end)

		Lib.Replace(defer, machine, "GetClosestButton", function() return 1 end)
		Lib.Replace(defer, ix.item, "Spawn", function(uniqueID, position, callback)
			if (callback) then callback({}, NULL) end
			return true
		end)

		local function Use()
			machine.nextUseTime = 0
			return Lib.Capture(bot, function() machine:Use(bot) end)
		end

		-- a citizen buys
		S.Become(bot, FACTION_CITIZEN)

		character:SetMoney(0)
		local seen = Use()
		Lib.Expect(fail, "no money: the refusal is said", seen.notices, "vendingNeedMoney")
		Lib.Expect(fail, "no money: stock kept", machine:GetStock(1), machine.MaxStock)

		character:SetMoney(100)
		seen = Use()
		Lib.Expect(fail, "sold: nothing said", seen.notices .. seen.texts, "")
		Lib.Expect(fail, "sold: paid", character:GetMoney(), 100 - machine.Items[1][3])
		Lib.Expect(fail, "sold: stock taken", machine:GetStock(1), machine.MaxStock - 1)

		-- the Combine refill an empty button
		S.Become(bot, FACTION_MPF)
		if (!character:IsCombine()) then return fail("the bot did not become Combine") end

		machine:SetStock(1, 0)
		seen = Use()
		Lib.Expect(fail, "restocked: nothing said", seen.notices .. seen.texts, "")
		Lib.Expect(fail, "restocked: full again", machine:GetStock(1), machine.MaxStock)
	end)

	if (ix.lang.stored.english.vendingPurchased or ix.lang.stored.english.vendingRestocked) then
		fail("the pruned vending phrases are still defined")
	end
end)

local CLEANUP_CLASSES = {"ix_rationdispenser", "ix_vendingmachine", "ix_forcefield"}
local CLEANUP_SAVES = {ix_rationdispenser = "rationDispensers", ix_vendingmachine = "vendingMachines", ix_forcefield = "forceFields"}

GWH.Check("schema review: a map cleanup keeps the saved dispensers, vending machines and forcefields", function(fail)
	local base = Vector(5100, 5100, 64)
	local positions = {}

	for index, class in ipairs(CLEANUP_CLASSES) do
		positions[class] = {}

		for i = 1, 2 do
			local entity = ents.Create(class)
			entity:SetPos(base + Vector(i * 80, index * 160, 0))
			entity:Spawn()
			positions[class][i] = entity:GetPos()
		end
	end

	hook.Run("SaveData")

	local before = {}

	for _, class in ipairs(CLEANUP_CLASSES) do
		before[class] = #Live(class)
	end

	local errors = S.Errors(function() game.CleanUpMap() end)

	for _, err in ipairs(errors) do fail("game.CleanUpMap: " .. err) end

	for _, class in ipairs(CLEANUP_CLASSES) do
		local saved = #(ix.data.Get(CLEANUP_SAVES[class]) or {})

		if (#Live(class) != before[class]) then fail("after a cleanup " .. #Live(class) .. " " .. class .. " remain, expected " .. before[class]) end
		if (saved != before[class]) then fail("after a cleanup " .. saved .. " " .. class .. " are saved, expected " .. before[class]) end
	end

	-- an entity removed this frame is not saved again
	local removed = Live("ix_rationdispenser")[1]

	if (IsValid(removed)) then
		local count = #Live("ix_rationdispenser")

		Schema.bCleaningUp = true
		removed:Remove()
		Schema.bCleaningUp = false
		Schema:SaveRationDispensers()

		if (#(ix.data.Get("rationDispensers") or {}) != count - 1) then fail("a ration dispenser removed this frame was saved again") end
	end

	-- remove the ones made here, then save what is left
	Schema.bCleaningUp = true

	for _, class in ipairs(CLEANUP_CLASSES) do
		for _, entity in ipairs(Live(class)) do
			for _, position in ipairs(positions[class]) do
				if (entity:GetPos():Distance(position) < 1) then entity:Remove() end
			end
		end
	end

	Schema.bCleaningUp = false
	Schema:SaveData()

	-- S.ReviewTarget's bot is not needed after this: 56_datafile.lua to 59_protectionteams.lua run earlier
	for _, v in ipairs(player.GetBots()) do
		if (v.gwhReviewTarget) then v:Kick("gw_harness") end
	end
end)
