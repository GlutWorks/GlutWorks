-- Nicknames (simple_nicknames): /SetNickname with % and multi-word names, replacing and rejecting nicknames,
-- apostrophes in names, and no nicknames on Combine names.

local Lib = GWH.Lib

local function CountPlain(text, needle)
	local count, start = 0, 1

	while (true) do
		local s, e = string.find(text, needle, start, true)
		if (!s) then return count end

		count = count + 1
		start = e + 1
	end
end

local S = Lib.NewS()

-- Drives the /SetNickname handler directly with the bot as the client, and puts the
-- character's name back afterwards.
GWH.Check("/SetNickname handles % and multi-word names", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot with a character") end

	local command = ix.command.list.setnickname
	if (!command or !command.OnRun) then return fail("setnickname is not in ix.command.list") end

	local character = bot:GetCharacter()
	local original = character:GetName()
	local faction, team = character:GetFaction(), bot:Team()

	-- Combine units cannot take a nickname, and the bot's faction is random per boot.
	character:SetFaction(FACTION_CITIZEN)
	bot:SetTeam(FACTION_CITIZEN)
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

	character:SetFaction(faction)
	bot:SetTeam(team)
	character:SetName(original)
end)

GWH.Check("schema review: nicknames keep apostrophes and stay off Combine names", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local state = S.SnapshotWithFlags(bot)
	local character = bot:GetCharacter()

	local function Reset()
		character:SetData("nicknameBase", nil)
		character:SetData("nicknameName", nil)
	end

	Reset()
	S.Become(bot, FACTION_MPF, "MPF-RCT 51006")

	local notices = S.Notices(bot, function() S.Command(bot, "/SetNickname x.SeC.x") end)

	if (character:GetName() != "MPF-RCT 51006") then fail("a Civil Protection unit took a nickname: " .. character:GetName()) end
	if (Schema:HasCommandRank(bot)) then fail("a nickname gave a recruit a command rank") end
	if (#notices == 0) then fail("a refused Combine nickname sent no notice") end

	Reset()
	S.Become(bot, FACTION_CITIZEN, "D'Arcy O'Neil")

	for _, case in ipairs({
		{"Chief", "D'Arcy 'Chief' O'Neil"},
		{"Boss", "D'Arcy 'Boss' O'Neil"},
		{"none", "D'Arcy O'Neil"}
	}) do
		S.Command(bot, "/SetNickname " .. case[1])

		if (character:GetName() != case[2]) then
			fail("/SetNickname " .. case[1] .. " gave '" .. character:GetName() .. "', expected '" .. case[2] .. "'")
		end
	end

	-- rank tokens in a citizen's name mean nothing
	S.Become(bot, FACTION_CITIZEN, "Mr SeC Jones")

	if (bot:IsDispatch()) then fail("a citizen named 'Mr SeC Jones' counts as dispatch") end

	Reset()
	S.RestoreWithFlags(bot, state)
end)
