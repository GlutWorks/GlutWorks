-- Client values (ix.util.ReadClientType and ReadClientTable, ix.option.Sanitize, our changes to Helix in
-- UPSTREAM.md): the receivers of item actions, entity-menu choices, character creation, commands and options read
-- what a client sent only if it is plain, and options only as their type says. Each check sends, laid out as a
-- client's net.Write* calls would (Wire), what a modified client could send instead.

local Lib = GWH.Lib
local Scoped, Replace, Wire, ReceiveWire, Expect = Lib.Scoped, Lib.Replace, Lib.Wire, Lib.ReceiveWire, Lib.Expect
local ResetBotFully, RemoveAll = Lib.ResetBotFully, Lib.RemoveAll

-- A table nested `depth` levels deep.
local function Nested(depth)
	local root = {}
	local node = root

	for _ = 2, depth do
		node[1] = {}
		node = node[1]
	end

	return root
end

-- Sends the bot's "Drink" action on a fresh water with `data` as its table, and returns whether it drank.
local function Drink(bot, data)
	local inventory = bot:GetCharacter():GetInventory()

	RemoveAll(inventory, "water")
	inventory:Add("water")

	local water = inventory:HasItem("water")

	bot.ixItemNetTokens = nil
	ReceiveWire("ixInventoryAction", bot, Wire():String("Drink"):UInt(water:GetID()):UInt(inventory:GetID()):Table(data))

	return inventory:GetItemByID(water:GetID()) == nil
end

GWH.Check("client values: an item action's table is read only if it's plain", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		defer(function() ResetBotFully(bot) RemoveAll(bot:GetCharacter():GetInventory(), "water") end)
		ResetBotFully(bot)

		Expect(fail, "drank, with an empty table", Drink(bot, {}), true)
		Expect(fail, "drank, with plain options", Drink(bot, {1, amount = 2, nested = {flag = true}}), true)
		Expect(fail, "drank, with an entity in the table", Drink(bot, {bot}), false)
		Expect(fail, "drank, with a table nested 10 deep", Drink(bot, Nested(10)), false)
		Expect(fail, "drank, with NaN in the table", Drink(bot, {value = 0 / 0}), false)

		local many = {}
		for i = 1, 100 do many[i] = i end
		Expect(fail, "drank, with 100 entries", Drink(bot, many), false)
	end)
end)

GWH.Check("client values: an entity-menu choice carries only plain data", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBotFully(bot)

		local received = {}
		local prop = ents.Create("prop_physics")
		prop:SetModel("models/props_junk/wood_crate001a.mdl")
		prop:SetPos(bot:GetShootPos() + bot:GetAimVector() * 40)
		prop:Spawn()
		prop.OnSelecttest = function(_, _, data) received[#received + 1] = data end
		defer(function() prop:Remove() end)

		ReceiveWire("ixEntityMenuSelect", bot, Wire():Entity(prop):String("test"):Type({action = "fuel", amount = 2}))
		ReceiveWire("ixEntityMenuSelect", bot, Wire():Entity(prop):String("test"):Type(bot))
		ReceiveWire("ixEntityMenuSelect", bot, Wire():Entity(prop):String("test"):Type(Nested(10)))

		Expect(fail, "choices that reached the entity", #received, 1)
		Expect(fail, "the plain choice's action", istable(received[1]) and received[1].action, "fuel")
	end)
end)

GWH.Check("client values: character creation stops at a field that isn't plain", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		local asked = 0

		-- refuse every creation the check gets as far as asking about, so none is made
		hook.Add("CanPlayerCreateCharacter", "gwh_count", function() asked = asked + 1 return false, "gwh" end)
		defer(function() hook.Remove("CanPlayerCreateCharacter", "gwh_count") end)
		Replace(defer, bot, "ixCharList", bot.ixCharList or {})

		local function Create(fields)
			bot.ixNextCharacterCreate = nil

			local wire = Wire():UInt(table.Count(fields))

			for key, value in pairs(fields) do
				wire:String(key):Type(value)
			end

			ReceiveWire("ixCharacterCreate", bot, wire)
		end

		Create({name = "Gwh Plain", description = "plain fields", model = 1})
		Expect(fail, "creations asked about after plain fields", asked, 1)

		Create({name = "Gwh Entity", description = bot, model = 1})
		Create({name = "Gwh Nested", description = "deep", data = Nested(10)})
		Expect(fail, "creations asked about after fields that aren't plain", asked, 1)
	end)
end)

GWH.Check("client values: an option holds only what its type allows", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		local steamID = bot:SteamID64()
		local before = ix.option.clients[steamID] and table.Copy(ix.option.clients[steamID])
		defer(function() ix.option.clients[steamID] = before end)

		local function Set(key, value)
			ReceiveWire("ixOptionSet", bot, Wire():String(key):Type(value))
			return (ix.option.clients[steamID] or {})[key]
		end

		Expect(fail, "thirdpersonEnabled after true", Set("thirdpersonEnabled", true), true)
		Expect(fail, "thirdpersonEnabled after false", Set("thirdpersonEnabled", false), false)
		Expect(fail, "thirdpersonEnabled after a table", Set("thirdpersonEnabled", {1}), false)
		Expect(fail, "thirdpersonEnabled after a string", Set("thirdpersonEnabled", "yes"), false)
		Expect(fail, "language after english", Set("language", "english"), "english")
		Expect(fail, "language after one there isn't", Set("language", "gwh-nonsense"), "english")
		Expect(fail, "language after a table", Set("language", {"english"}), "english")

		-- the first sync after joining, through the same checks
		local wire = Wire():UInt(2):String("thirdpersonEnabled"):Type({}):String("language"):Type("gwh-nonsense")
		ReceiveWire("ixOptionSync", bot, wire)
		Expect(fail, "thirdpersonEnabled after a synced table", ix.option.clients[steamID].thirdpersonEnabled, false)
		Expect(fail, "language after a synced language there isn't", ix.option.clients[steamID].language, "english")
	end)
end)
