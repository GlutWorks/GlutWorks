-- Immersion: the HUD config, /Feel and magazine wording (tied hands included), the silent need-at-zero,
-- notices (still sent to the right player only, refusals told apart) and the restrained text left out while
-- the HUD is hidden. The screen effects, the notice lines, the chat and the death fade are client-only and are
-- judged in a play session, not here.

local WithConfig = GWH.Lib.WithConfig

local function Has(text, phrase)
	return string.find(text, phrase, 1, true) != nil
end

-- The shared reset, plus breath: these checks set stamina and the out-of-breath flag.
local function ResetBot(bot)
	GWH.Lib.ResetBot(bot)

	bot:SetNetVar("brth", nil)
	bot:SetLocalVar("stm", 100)
end

GWH.Check("immersion: plugin, config, option, commands and chat class exist", function(fail)
	local plugin = ix.plugin.list.immersion
	if (!plugin) then return fail("immersion is not loaded") end

	local config = ix.config.stored.immersionHideHUD

	if (!config) then
		fail("config immersionHideHUD is not registered")
	elseif (config.default != true) then
		fail("immersionHideHUD does not default to on")
	end

	local option = ix.option.stored.reduceMotionEffects

	if (!option) then
		fail("option reduceMotionEffects is not registered")
	elseif (option.default != false) then
		fail("reduceMotionEffects does not default to off")
	end

	for _, v in ipairs({"feel", "checkammo"}) do
		if (!ix.command.list[v]) then fail("/" .. v .. " is not registered") end
	end

	local class = ix.chat.classes.feel

	if (!class) then
		fail("the feel chat class is not registered")
	else
		if (class.prefix) then fail("the feel chat class can be typed into chat") end
		if (class.indicator) then fail("the feel chat class shows a typing indicator") end

		local bot = GWH.Bot()
		local other = {GetPos = function() return vector_origin end}

		if (bot and class:CanHear(bot, other) != false) then fail("someone else can hear a feel line") end
	end

	-- every phrase in English has a Spanish one
	local english, spanish = ix.lang.stored.english, ix.lang.stored.spanish

	for _, key in ipairs({"feelFine", "feelHealth1", "feelHealth4", "feelNeedsOne", "feelNeedsBoth",
		"feelHunger2", "feelHunger5", "feelThirst2", "feelThirst5", "feelBreath1", "feelBreath3",
		"ammoMagEmpty", "ammoMagHalf", "ammoMagFull", "ammoSpareNone", "ammoSparePlenty", "ammoNoMagazine",
		"optReduceMotionEffects", "cmdFeel", "cmdCheckAmmo", "feelTied"}) do
		if (!english[key]) then fail("no English phrase " .. key) end
		if (spanish and !spanish[key]) then fail("no Spanish phrase " .. key) end
	end

	-- the starving/dehydrated toasts are gone
	for _, key in ipairs({"hungerEmpty", "thirstEmpty"}) do
		if (english[key] or (spanish and spanish[key])) then fail(key .. " is still a phrase") end
	end
end)

GWH.Check("immersion: /Feel describes the body in words", function(fail)
	local plugin = ix.plugin.list.immersion
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local function Describe(changes)
		local state = {health = 100, maxHealth = 100, hunger = 100, thirst = 100, stamina = 100, exhausted = false}

		for k, v in pairs(changes) do state[k] = v end

		local text = plugin:DescribeCondition(bot, state)

		if (string.find(text, "%d")) then fail("the description has a number in it: " .. text) end

		return text
	end

	local function Expect(label, changes, phrases)
		local text = Describe(changes)

		for _, phrase in ipairs(phrases) do
			if (!Has(text, phrase)) then fail(label .. ": '" .. text .. "' does not say '" .. phrase .. "'") end
		end

		return text
	end

	local detail = {}

	WithConfig({hungerthirstEnabled = true}, function()
		local fine = Describe({})
		detail.fine = fine

		if (fine != L("feelFine", bot)) then fail("a healthy character is described as '" .. fine .. "'") end

		detail.hurt = Expect("hurt", {health = 30}, {L("feelHealth3", bot)})
		Expect("nearly dead", {health = 5}, {L("feelHealth4", bot)})
		Expect("scratched", {health = 80}, {L("feelHealth1", bot)})

		detail.hungry = Expect("hungry", {hunger = 40}, {L("feelNeedsOne", bot, L("feelHunger4", bot))})
		detail.thirsty = Expect("thirsty", {thirst = 60}, {L("feelNeedsOne", bot, L("feelThirst3", bot))})
		detail.both = Expect("hungry and thirsty", {hunger = 0, thirst = 75},
			{L("feelNeedsBoth", bot, L("feelHunger5", bot), L("feelThirst2", bot))})

		detail.winded = Expect("exhausted", {stamina = 0, exhausted = true}, {L("feelBreath3", bot)})
		Expect("breathing hard", {stamina = 20}, {L("feelBreath2", bot)})

		detail.all = Expect("everything", {health = 30, hunger = 40, thirst = 75, stamina = 0, exhausted = true},
			{L("feelHealth3", bot), L("feelHunger4", bot), L("feelThirst2", bot), L("feelBreath3", bot)})

		if (Describe({hunger = 85, thirst = 90}) != L("feelFine", bot)) then
			fail("barely peckish is not 'fine'")
		end

		-- the bot's real state goes through the same path
		ResetBot(bot)
		bot:SetHealth(bot:GetMaxHealth())
		bot:GetCharacter():SetHunger(100)
		bot:GetCharacter():SetThirst(100)

		local real = plugin:DescribeCondition(bot)

		if (real != L("feelFine", bot)) then
			fail("the healthy bot's own description is '" .. real .. "' (health " .. bot:Health() .. " of " .. bot:GetMaxHealth() .. ")")
		end
	end)

	WithConfig({hungerthirstEnabled = false}, function()
		if (Describe({hunger = 0, thirst = 0}) != L("feelFine", bot)) then
			fail("hunger and thirst are described while hungerthirstEnabled is off")
		end
	end)

	-- /Feel itself sends one private line to the player
	local sent = {}
	local send = plugin.SendPrivate

	plugin.SendPrivate = function(_, client, text) sent[#sent + 1] = {client, text} end
	local ok, err = pcall(ix.command.list.feel.OnRun, ix.command.list.feel, bot)
	plugin.SendPrivate = send

	if (!ok) then
		fail("/Feel raised " .. tostring(err))
	elseif (#sent != 1 or sent[1][1] != bot) then
		fail("/Feel sent " .. #sent .. " lines")
	end

	return detail
end)

GWH.Check("immersion: magazine checks say roughly how full, in words", function(fail)
	local plugin = ix.plugin.list.immersion
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local detail = {}

	local function Expect(clip, maxClip, reserve, magazine, spare)
		local text = plugin:DescribeMagazine(bot, clip, maxClip, reserve)
		local label = clip .. "/" .. maxClip .. " +" .. reserve

		detail[label] = text

		if (string.find(text, "%d")) then fail(label .. ": has a number in it: " .. text) end
		if (!Has(text, L(magazine, bot))) then fail(label .. ": '" .. text .. "' is not " .. magazine) end
		if (!Has(text, L(spare, bot))) then fail(label .. ": '" .. text .. "' is not " .. spare) end
	end

	Expect(0, 30, 0, "ammoMagEmpty", "ammoSpareNone")
	Expect(3, 30, 10, "ammoMagLow", "ammoSpareFew")
	Expect(10, 30, 45, "ammoMagUnderHalf", "ammoSpareSome")
	Expect(15, 30, 10, "ammoMagHalf", "ammoSpareFew")
	Expect(25, 30, 0, "ammoMagMost", "ammoSpareNone")
	Expect(30, 30, 200, "ammoMagFull", "ammoSparePlenty")
	Expect(18, 17, 17, "ammoMagFull", "ammoSpareSome") -- a round chambered over the magazine
	Expect(1, 6, 0, "ammoMagLow", "ammoSpareNone")

	-- the real path: validation, wording for no magazine, rate limit
	local sent = {}
	local send = plugin.SendPrivate

	plugin.SendPrivate = function(_, client, text) sent[#sent + 1] = text end

	local ok, err = pcall(function()
		ResetBot(bot)

		local hadPistol = bot:HasWeapon("weapon_pistol")
		local active = IsValid(bot:GetActiveWeapon()) and bot:GetActiveWeapon():GetClass()
		local weapon = bot:Give("weapon_pistol")

		if (!IsValid(weapon)) then weapon = bot:GetWeapon("weapon_pistol") end

		if (!IsValid(weapon)) then
			fail("could not give the bot a pistol")
		else
			bot:SetActiveWeapon(weapon)
			weapon:SetClip1(9)
			bot:SetAmmo(0, weapon:GetPrimaryAmmoType())

			bot.ixNextMagazineCheck = nil
			plugin:CheckMagazine(bot)

			if (sent[1] != plugin:DescribeMagazine(bot, 9, weapon:GetMaxClip1(), 0)) then
				fail("checking a half-full pistol said '" .. tostring(sent[1]) .. "'")
			end

			plugin:CheckMagazine(bot)
			if (#sent != 1) then fail("a second check straight away was not rate-limited") end

			-- dead players feel nothing
			bot.ixNextMagazineCheck = nil
			bot:KillSilent()
			plugin:CheckMagazine(bot)
			if (#sent != 1) then fail("a dead player checked their magazine") end

			ResetBot(bot)

			if (!hadPistol and bot:HasWeapon("weapon_pistol")) then bot:StripWeapon("weapon_pistol") end
		end

		-- no magazine: /CheckAmmo says so, Walk + Reload stays silent
		local hands = bot:GetWeapon("ix_hands")

		if (IsValid(hands)) then
			bot:SetActiveWeapon(hands)

			local before = #sent

			bot.ixNextMagazineCheck = nil
			plugin:CheckMagazine(bot)
			if (#sent != before) then fail("Walk + Reload with hands said something") end

			bot.ixNextMagazineCheck = nil
			ix.command.list.checkammo.OnRun(ix.command.list.checkammo, bot)

			if (sent[#sent] != L("ammoNoMagazine", bot)) then
				fail("/CheckAmmo with hands said '" .. tostring(sent[#sent]) .. "'")
			end
		end

		if (active and bot:HasWeapon(active)) then bot:SelectWeapon(active) end
		bot.ixNextMagazineCheck = nil
	end)

	plugin.SendPrivate = send
	if (!ok) then fail("checking the magazine raised " .. tostring(err)) end

	return detail
end)

GWH.Check("immersion: a need reaching zero is felt, not announced, and still starves", function(fail)
	local survival = ix.plugin.list.survivaladditions
	local bot = GWH.Bot()
	if (!survival or !bot) then return fail("no survivaladditions or bot") end

	local character = bot:GetCharacter()
	local notices = {}

	local meta = FindMetaTable("Player")
	local notify = meta.NotifyLocalized

	ResetBot(bot)

	meta.NotifyLocalized = function(client, phrase, ...)
		if (client == bot) then notices[#notices + 1] = phrase end
		return notify(client, phrase, ...)
	end

	local ok, err = pcall(WithConfig, {hungerthirstEnabled = true, hungerDamage = 5, thirstDamage = 5, needsRespawnLevel = 40}, function()
		character:SetHunger(0.01)
		character:SetThirst(0.01)
		bot:SetHealth(50)
		survival:NeedsTick(bot, character, 6)

		if (character:GetHunger() != 0 or character:GetThirst() != 0) then fail("the needs did not reach zero") end
		if (bot:Health() != 40) then fail("starving and dehydrated left health at " .. bot:Health() .. ", expected 40") end
		if (#notices > 0) then fail("reaching zero still notifies: " .. table.concat(notices, ", ")) end

		bot:SetHealth(3)
		survival:NeedsTick(bot, character, 6)

		if (bot:Alive()) then
			fail("a lethal starvation tick did not kill")
		elseif (!table.HasValue(notices, "hungerDied")) then
			fail("starving to death did not say so (got " .. table.concat(notices, ", ") .. ")")
		end
	end)

	meta.NotifyLocalized = notify
	ResetBot(bot)
	character:SetHunger(100)
	character:SetThirst(100)

	if (!ok) then error(err, 0) end
end)

GWH.Check("immersion: the server still sends each notice to its player alone (the client makes it a line)", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local sent = {}

	GWH.Lib.Scoped(function(defer)
		local start, send, broadcast = net.Start, net.Send, net.Broadcast
		local current

		GWH.Lib.Replace(defer, net, "Start", function(name, ...)
			current = name
			return start(name, ...)
		end)
		GWH.Lib.Replace(defer, net, "Send", function(target, ...)
			if (current == "ixNotify" or current == "ixNotifyLocalized") then sent[#sent + 1] = {current, target} end
			return send(target, ...)
		end)
		GWH.Lib.Replace(defer, net, "Broadcast", function(...)
			if (current == "ixNotify" or current == "ixNotifyLocalized") then sent[#sent + 1] = {current, "everyone"} end
			return broadcast(...)
		end)

		bot:Notify("A plain notice.")
		bot:NotifyLocalized("notNow")
		ix.util.NotifyLocalized("noFit", bot)
		ix.util.Notify("A notice for everyone.")
	end)

	local got = {}

	for i, v in ipairs(sent) do
		got[i] = v[1] .. ">" .. (v[2] == bot and "bot" or tostring(v[2]))
	end

	GWH.Lib.Expect(fail, "notices sent", table.concat(got, ","),
		"ixNotify>bot,ixNotifyLocalized>bot,ixNotifyLocalized>bot,ixNotify>everyone")
end)

GWH.Check("immersion: refusals are told apart from other notices", function(fail)
	local plugin = ix.plugin.list.immersion
	if (!plugin or !plugin.IsRefusalNotice) then return fail("no immersion or IsRefusalNotice") end

	local cases = {
		{"You do not have enough space for this item!", "noFit", true},
		{"You need 5 tokens to purchase this.", "vendingNeedMoney", true},
		{"You could only pick up some of it.", "stackPartialPickup", false},
		{"That camera is already disabled!", nil, true},
		{"Note: Your character currently has no biosignal.", nil, false},
		{"Map entity removed.", nil, false},
		{"Purchase successful!", "buyGood", false},
		{"Come again soon!", "vendorBye", false},
		{"The map will restart in 10 seconds!", "mapRestarting", false}
	}

	for _, v in ipairs(cases) do
		if (plugin:IsRefusalNotice(v[1], v[2]) != v[3]) then
			fail("'" .. v[1] .. "' (" .. tostring(v[2]) .. ") is " .. (v[3] and "not " or "") .. "taken for a refusal")
		end
	end

	-- every refusal phrase is a real one, so a typo cannot quietly turn a refusal into a plain notice
	for key in pairs(plugin.refusalPhrases) do
		if (!ix.lang.stored.english[key]) then fail("refusal phrase " .. key .. " is not an English phrase") end
	end

	for key in pairs(plugin.plainPhrases) do
		if (!ix.lang.stored.english[key]) then fail("plain phrase " .. key .. " is not an English phrase") end
	end
end)

GWH.Check("immersion: /Feel says the hands are tied", function(fail)
	local plugin = ix.plugin.list.immersion
	local bot = GWH.Bot()
	if (!plugin or !bot) then return fail("no plugin or bot") end

	local tied = L("feelTied", bot)
	local state = {health = 100, maxHealth = 100, hunger = 100, thirst = 100, stamina = 100, restricted = true}

	if (!Has(plugin:DescribeCondition(bot, state), tied)) then fail("a tied state is not described as tied") end

	-- the net var behind IsRestricted; SetRestricted also takes the weapons, which cannot be given back in
	-- the same frame
	GWH.Lib.Scoped(function(defer)
		defer(function() bot:SetNetVar("restricted", nil) end)

		ResetBot(bot)
		bot:SetNetVar("restricted", true)

		local text = plugin:DescribeCondition(bot)

		if (!Has(text, tied)) then fail("/Feel while tied says '" .. text .. "'") end

		bot:SetNetVar("restricted", nil)
		text = plugin:DescribeCondition(bot)

		if (Has(text, tied)) then fail("/Feel after untying still says '" .. text .. "'") end
	end)
end)

GWH.Check("immersion: no restrained text while the HUD is hidden, and it comes back with the config", function(fail)
	local bot = GWH.Bot()
	if (!bot or !ix.immersionSetRestricted) then return fail("no bot, or SetRestricted is not wrapped") end

	GWH.Lib.Scoped(function(defer)
		-- Helix's SetRestricted, minus the weapons (they cannot be given back in the same frame)
		GWH.Lib.Replace(defer, ix, "immersionSetRestricted", function(client, bState, bNoMessage)
			client:SetNetVar("restricted", bState or nil)
			client:SetLocalVar("restrictNoMsg", (bState and bNoMessage) and true or nil)
		end)

		defer(function() bot:SetRestricted(false) end)

		WithConfig({immersionHideHUD = true}, function()
			bot:SetRestricted(true)
			GWH.Lib.Expect(fail, "tied, HUD hidden: no text", bot:GetLocalVar("restrictNoMsg"), true)

			ix.config.Set("immersionHideHUD", false)
			GWH.Lib.Expect(fail, "tied, HUD turned back on: text", bot:GetLocalVar("restrictNoMsg"), nil)

			ix.config.Set("immersionHideHUD", true)
			GWH.Lib.Expect(fail, "tied, HUD hidden again: no text", bot:GetLocalVar("restrictNoMsg"), true)

			bot:SetRestricted(false)
			GWH.Lib.Expect(fail, "untied: cleared", bot:GetLocalVar("restrictNoMsg"), nil)
		end)

		WithConfig({immersionHideHUD = false}, function()
			bot:SetRestricted(true)
			GWH.Lib.Expect(fail, "tied, HUD shown: text", bot:GetLocalVar("restrictNoMsg"), nil)
			bot:SetRestricted(false)

			-- a caller that asked for no text still gets none
			bot:SetRestricted(true, true)
			GWH.Lib.Expect(fail, "tied quietly, HUD shown: no text", bot:GetLocalVar("restrictNoMsg"), true)
			ix.config.Set("immersionHideHUD", true)
			ix.config.Set("immersionHideHUD", false)
			GWH.Lib.Expect(fail, "tied quietly, config back and forth: still no text", bot:GetLocalVar("restrictNoMsg"), true)
			bot:SetRestricted(false)
		end)
	end)
end)

GWH.Check("immersion: Helix's wepselect and typing are extended by the project's files, loaded after Helix's", function(fail)
	local wepselect, typing = ix.plugin.list.wepselect, ix.plugin.list.typing
	if (!wepselect or !typing) then return fail("wepselect or typing is not loaded") end

	local Lib = GWH.Lib

	-- One table holds both files: Helix's name (ours sets none) and Helix's functions sit beside ours. Both files
	-- set a description; ours is the one left, so ours ran second, as it must for its methods to win.
	Lib.Expect(fail, "wepselect name (Helix's)", wepselect.name, "Weapon Select")
	if (!isfunction(wepselect.GetDirectSwitch)) then fail("wepselect has no GetDirectSwitch (ours did not run)") end
	Lib.Expect(fail, "wepselect description (ours, so loaded last)", wepselect.description,
		"Switch weapons with the wheel or the slot keys, straight away and with nothing drawn.")

	Lib.Expect(fail, "typing name (Helix's)", typing.name, "Typing Indicator")
	if (!isfunction(typing.PlayerSpawn)) then fail("typing lost Helix's PlayerSpawn") end
	if (!isnumber(typing.quietFontSize) or !IsColor(typing.quietColor)) then fail("typing has no quiet style (ours did not run)") end
	Lib.Expect(fail, "typing description (ours, so loaded last)", typing.description,
		"Shows a small, dim word above someone who is typing.")
end)
