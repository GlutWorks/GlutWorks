-- Writing (writing): paper can only be written by someone who can reach it, malformed payloads change nothing,
-- and a written paper cannot be rewritten through the receiver.

local Lib = GWH.Lib
local OtherBot, Scoped, GiveItem = Lib.OtherBot, Lib.Scoped, Lib.GiveItem

local S = Lib.NewS()

GWH.Check("hygiene: paper can only be written by someone who can reach it", function(fail)
	return Scoped(function(defer)
		local writer, other = GWH.Bot(), OtherBot()
		local edit = netstream.stored.ixWritingEdit
		local paper = GiveItem(writer:GetCharacter():GetInventory(), "paper")
		defer(function() paper:Remove() end)

		local function Text() return paper:GetData("text", "") end

		edit(other, paper:GetID(), "stolen")
		if (Text() != "") then fail("someone else wrote on paper in the writer's inventory") end

		edit(writer, {}, "x")
		edit(writer, paper:GetID(), {})
		edit(writer, paper:GetID())
		edit(writer, "paper", "x")
		if (Text() != "") then fail("a malformed payload changed the paper") end

		-- the net var behind IsRestricted; SetRestricted also strips weapons, which the sandbox cannot give back
		writer:SetNetVar("restricted", true)
		edit(writer, paper:GetID(), "tied")
		writer:SetNetVar("restricted", nil)
		if (Text() != "") then fail("a tied player wrote on paper") end

		edit(writer, paper:GetID(), string.rep("a", 4000))
		local maxLength = ix.plugin.list.writing.maxLength
		if (#Text() != maxLength) then fail("own paper: expected " .. maxLength .. " characters, got " .. #Text()) end
		if (paper:GetData("owner") != writer:GetCharacter():GetID()) then fail("the writer was not recorded") end

		edit(writer, paper:GetID(), "second draft")
		if (Text() == "second draft") then fail("the writer rewrote a finished paper") end

		-- lying in the world: reachable from close by only
		local world
		ix.item.Spawn("paper", writer:GetShootPos() + Vector(0, 0, 2000), function(item) world = item end)
		defer(function()
			local entity = world:GetEntity()
			if (IsValid(entity)) then entity:Remove() end
		end)

		edit(writer, world:GetID(), "from afar")
		if (world:GetData("text", "") != "") then fail("paper was written from out of reach") end

		world:GetEntity():SetPos(writer:GetShootPos() + Vector(40, 0, 0))
		edit(writer, world:GetID(), "up close")
		if (world:GetData("text", "") != "up close") then fail("paper within reach could not be written") end

		edit(other, world:GetID(), "overwrite")
		if (world:GetData("text", "") != "up close") then fail("someone overwrote another character's writing") end
	end)
end)

GWH.Check("schema review: a written paper cannot be rewritten through the receiver", function(fail)
	if (!ix.item.list.paper) then return {skipped = "writing not loaded"} end

	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local inventory = bot:GetCharacter():GetInventory()

	for _, item in pairs(inventory:GetItemsByUniqueID("paper", true) or {}) do item:Remove() end

	inventory:Add("paper")

	local paper = inventory:HasItem("paper")
	if (!paper) then return fail("could not give the bot a paper") end

	S.Stream("ixWritingEdit", bot, paper:GetID(), "first")

	if (paper:GetData("text") != "first") then fail("a blank paper could not be written on") end

	S.Stream("ixWritingEdit", bot, paper:GetID(), "rewritten")

	if (paper:GetData("text") != "first") then fail("the author rewrote a paper the menu no longer lets them edit") end

	paper:Remove()
end)
