-- Saving (ix.data.SaveSoon, CHAR:SaveSoon and the storage money handlers, our changes to Helix in UPSTREAM.md): a
-- saved character var, and the container on the other side of a money transfer, are saved at the end of the tick
-- they change in, once however often they change, and a character's own save doesn't queue another. The checks run
-- the end-of-tick queue themselves (ix.data.SaveQueued), with the saves replaced by counters.

local Lib = GWH.Lib
local Scoped, Replace, ReceiveReads, Expect = Lib.Scoped, Lib.Replace, Lib.ReceiveReads, Lib.Expect
local ResetBot, NewCharacter = Lib.ResetBot, Lib.NewCharacter

-- A stand-in character of the bot's that counts as a real one (bots' characters are never saved), with Save
-- replaced by a counter: returns the character and a function giving the count.
local function Counted(defer, bot)
	local character = NewCharacter(bot)
	local saves = 0

	character.isBot = false
	character.Save = function() saves = saves + 1 end

	defer(function() ix.char.loaded[character:GetID()] = nil end)

	return character, function() return saves end
end

GWH.Check("saving: the end-of-tick queue runs each save once, in order, past an error", function(fail)
	Scoped(function(defer)
		local ran, errors = {}, {}

		Replace(defer, _G, "ErrorNoHalt", function(text) errors[#errors + 1] = text end)
		ix.data.SaveQueued()

		ix.data.SaveSoon("gwh first", function() ran[#ran + 1] = "first, early" end)
		ix.data.SaveSoon("gwh broken", function() error("a broken save") end)
		ix.data.SaveSoon("gwh second", function() ran[#ran + 1] = "second" end)
		ix.data.SaveSoon("gwh first", function() ran[#ran + 1] = "first" end)
		ix.data.SaveQueued()

		Expect(fail, "saves run", table.concat(ran, ", "), "first, second")
		Expect(fail, "errors reported", #errors, 1)

		ix.data.SaveQueued()
		Expect(fail, "saves run by a second flush", #ran, 2)
	end)
end)

GWH.Check("saving: a character's saved vars are saved in the tick they change, once", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBot(bot)
		ix.data.SaveQueued()

		local character, saves = Counted(defer, bot)

		character:SetMoney(77)
		Expect(fail, "saves before the tick ends", saves(), 0)
		ix.data.SaveQueued()
		Expect(fail, "saves after SetMoney", saves(), 1)

		for i = 1, 50 do
			character:SetMoney(i)
			character:SetData("gwhSaving", i)
		end

		ix.data.SaveQueued()
		Expect(fail, "saves after 100 changes in one tick", saves(), 2)

		-- a var with no database field (CHAR:SetVar) isn't saved for
		character:SetVar("gwhSaving", 1)
		ix.data.SaveQueued()
		Expect(fail, "saves after a var that isn't kept", saves(), 2)

		-- a bot's character is never saved
		character.isBot = true
		character:SetMoney(5)
		ix.data.SaveQueued()
		Expect(fail, "saves of a bot's character", saves(), 2)
	end)
end)

GWH.Check("saving: what a character's own save sets doesn't queue another", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		ResetBot(bot)
		ix.data.SaveQueued()

		-- the real Save, of a stand-in with no database row: its CharacterPreSave hooks set position, health,
		-- stamina and ammo
		local character = NewCharacter(bot)
		character.isBot = false
		defer(function() ix.char.loaded[character:GetID()] = nil end)

		local queued = 0
		local saveSoon = ix.data.SaveSoon

		Replace(defer, ix.data, "SaveSoon", function(key, callback)
			if (key == "character " .. character:GetID()) then queued = queued + 1 end
			return saveSoon(key, callback)
		end)

		character:Save()
		Expect(fail, "saves queued by its own save", queued, 0)
		Expect(fail, "health set by CharacterPreSave", character:GetData("health") != nil, true)
	end)
end)

GWH.Check("saving: a container's money is saved in the tick a player moves it", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local plugin = ix.plugin.list.containers
	if (!plugin) then return fail("the containers plugin isn't loaded") end

	Scoped(function(defer)
		ResetBot(bot)
		ix.data.SaveQueued()

		local saves = 0
		Replace(defer, plugin, "SaveContainer", function() saves = saves + 1 end)

		local inventory = ix.inventory.Create(4, 4, 2100400001)
		local container = ents.Create("ix_container")
		container:SetModel("models/props_junk/wood_crate001a.mdl")
		container:SetPos(bot:GetPos() + Vector(50, 0, 10))
		container:Spawn()
		container:SetInventory(inventory)
		container:SetMoney(100)

		defer(function()
			if (inventory.storageInfo) then ix.storage.Close(inventory) end

			-- ixIsSafe: removed without its OnRemove deleting any inventory rows
			if (IsValid(container)) then
				container.ixIsSafe = true
				container:Remove()
			end

			ix.item.inventories[inventory:GetID()] = nil
		end)

		local money = bot:GetCharacter():GetMoney()
		defer(function() bot:GetCharacter():SetMoney(money) end)

		ix.storage.Open(bot, inventory, {entity = container, name = "crate", searchTime = 0})

		bot.ixStorageMoneyTimer = nil
		ReceiveReads("ixStorageMoneyTake", bot, {ReadUInt = {inventory:GetID(), 30}})
		Expect(fail, "the container's money after taking 30", container:GetMoney(), 70)

		ix.data.SaveQueued()
		Expect(fail, "container saves at the end of the tick", saves, 1)

		bot.ixStorageMoneyTimer = nil
		ReceiveReads("ixStorageMoneyGive", bot, {ReadUInt = {inventory:GetID(), 10}})
		ix.data.SaveQueued()
		Expect(fail, "container saves after paying 10 back in", saves, 2)
	end)
end)
