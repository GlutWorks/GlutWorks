-- Text plugins: the removed book items, /SetNickname's name handling, and the /me chat classes.

local function CountPlain(text, needle)
	local count, start = 0, 1

	while (true) do
		local s, e = string.find(text, needle, start, true)
		if (!s) then return count end

		count = count + 1
		start = e + 1
	end
end

GWH.Check("removed book items are gone and books remain", function(fail)
	for _, uniqueID in ipairs({"bookexample", "dustytestbook", "book_stillirise"}) do
		if (ix.item.list[uniqueID]) then fail(uniqueID .. " is still registered") end
	end

	local books = 0

	for _, item in pairs(ix.item.list) do
		if (item.base == "base_books") then books = books + 1 end
	end

	if (books < 50) then fail("only " .. books .. " book items remain, expected at least 50") end

	return {books = books}
end)

-- Drives the /SetNickname handler directly with the bot as the client, and puts the
-- character's name back afterwards.
GWH.Check("/SetNickname handles % and multi-word names", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot with a character") end

	local command = ix.command.list.setnickname
	if (!command or !command.OnRun) then return fail("setnickname is not in ix.command.list") end

	local character = bot:GetCharacter()
	local original = character:GetName()

	character:SetName("Alpha Bravo Charlie")

	local function Run(nickname)
		return pcall(command.OnRun, command, bot, nickname)
	end

	local ok, notice, name = Run("Ace 100%")

	if (!ok) then
		fail("OnRun raised on a % nickname: " .. tostring(notice))
	elseif (notice != "@nicknameNowKnown" or name != "Alpha 'Ace 100%' Bravo Charlie") then
		fail("nickname with % gave '" .. tostring(name) .. "'")
	elseif (CountPlain(name, "Ace 100%") != 1) then
		fail("nickname appears " .. CountPlain(name, "Ace 100%") .. " times")
	end

	-- Replacing an existing nickname goes through the quoted branch.
	ok, notice, name = Run("Zed 50%")

	if (!ok or name != "Alpha 'Zed 50%' Bravo Charlie") then
		fail("replacing a nickname gave '" .. tostring(name) .. "'")
	end

	-- Rejected input leaves the name untouched and returns a notice to the player.
	local before = character:GetName()

	ok, notice = Run("   ")
	if (!ok or notice != "@nicknameEmpty") then fail("whitespace-only nickname was not rejected") end

	ok, notice = Run(string.rep("x", 33))
	if (!ok or notice != "@nicknameTooLong") then fail("33-character nickname was not rejected") end

	if (character:GetName() != before) then fail("a rejected nickname changed the name") end

	character:SetName(original)
end)

GWH.Check("fancy /me chat classes are registered and read their range at send time", function(fail)
	local expected = {mey = "/MeY", ity = "/ItY", mew = "/MeW", itw = "/ItW", mel = "/MeL", itl = "/ItL"}

	for class, prefix in pairs(expected) do
		local data = ix.chat.classes[class]

		if (!data) then
			fail(class .. " is not registered")
		elseif (!table.HasValue(data.prefix or {}, prefix)) then
			fail(class .. " does not have the prefix " .. prefix)
		end
	end

	-- CanHear only needs GetPos, so plain tables stand in for the two players.
	local speaker = {GetPos = function() return Vector(0, 0, 0) end}
	local listener = {GetPos = function() return Vector(50, 0, 0) end}
	local wClass = ix.chat.classes.mew

	if (!wClass) then return end

	local original = ix.config.Get("chatActionWRange", 75)

	ix.config.Set("chatActionWRange", 75)
	if (wClass:CanHear(speaker, listener) != true) then fail("50 units is not within a 75 unit whisper range") end

	ix.config.Set("chatActionWRange", 10)
	if (wClass:CanHear(speaker, listener) != false) then fail("whisper range change was not picked up") end

	ix.config.Set("chatActionWRange", original)
end)
