-- Compat checks: the behaviour the team used to get from edits inside helix/, now provided by
-- schema plugins (enhancedanims, ragdollstate, pac, thirdperson, uifonts, addfactionhands).

local Lib = GWH.Lib
local ResetBot = Lib.ResetBotFully

local ZELPA_MALE = "models/player/zelpa/male_08_extended.mdl"
local ZELPA_FEMALE = "models/player/zelpa/female_03_extended.mdl"

-- Every hold type Weapon:SetHoldType accepts, run through Helix's translator the way
-- UpdatePlayerHoldType does it.
local function TranslatedHoldTypes()
	local result, seen = {}, {}

	for _, holdType in ipairs({
		"", "normal", "pistol", "smg", "grenade", "ar2", "shotgun", "rpg", "physgun", "crossbow", "melee",
		"slam", "fist", "melee2", "passive", "knife", "duel", "camera", "magic", "revolver"
	}) do
		local translated = HOLDTYPE_TRANSLATOR[holdType] or holdType

		if (!seen[translated]) then
			seen[translated] = true
			result[#result + 1] = translated
		end
	end

	return result
end

GWH.Check("compat: every animation class has every hold type", function(fail)
	for _, name in ipairs({"citizen_male_enhanced", "citizen_female_enhanced"}) do
		if (!ix.anim[name]) then fail("animation class " .. name .. " is missing") end
	end

	for _, holdType in ipairs({"ar2", "crossbow", "rpg", "fist", "melee2", "knife", "revolver"}) do
		if (HOLDTYPE_TRANSLATOR[holdType] != holdType) then
			fail("hold type " .. holdType .. " is still translated to " .. tostring(HOLDTYPE_TRANSLATOR[holdType]))
		end
	end

	local holdTypes = TranslatedHoldTypes()
	local classes = {}

	-- "player" animates through its own path; zombie/fastZombie are flat activity maps.
	for name, class in SortedPairs(ix.anim) do
		if (name != "player" and istable(class) and istable(class.normal)) then
			classes[#classes + 1] = name

			for _, holdType in ipairs(holdTypes) do
				local tree = class[holdType]

				if (!istable(tree) or !tree[ACT_MP_STAND_IDLE] or !tree[ACT_MP_RUN]) then
					fail(name .. " has no usable '" .. holdType .. "' table")
				end
			end
		end
	end

	-- Classes without their own tables must animate exactly as stock Helix collapsed them.
	local male = ix.anim.citizen_male

	if (male.ar2 != male.smg or male.knife != male.melee or male.revolver != male.pistol or male.fist != male.normal) then
		fail("citizen_male's new hold types do not fall back to the stock tables")
	end

	return {classes = classes, holdTypes = holdTypes}
end)

GWH.Check("compat: models map to the intended animation classes", function(fail)
	local expected = {
		[ZELPA_MALE] = "citizen_male_enhanced",
		["models/player/zelpa/male_01_extended.mdl"] = "citizen_male_enhanced",
		["models/player/zelpa/male_11_extended.mdl"] = "citizen_male_enhanced",
		[ZELPA_FEMALE] = "citizen_female_enhanced",
		["models/player/zelpa/female_07_extended.mdl"] = "citizen_female_enhanced",
		["models/police_nemez.mdl"] = "metrocop",
		["models/police.mdl"] = "metrocop",
		-- unknown models keep the stock classes
		["models/humans/group01/male_02.mdl"] = "citizen_male",
		["models/humans/group01/female_01.mdl"] = "citizen_female",
		["models/player/kleiner.mdl"] = "player"
	}

	for model, class in SortedPairs(expected) do
		local actual = ix.anim.GetModelClass(model)

		if (actual != class) then fail(model .. " maps to " .. tostring(actual) .. ", expected " .. class) end
	end

	-- The zelpa citizens get the citizen acts.
	if (ix.act) then
		for act, class in pairs({Sit = "citizen_male_enhanced", Stand = "citizen_female_enhanced", Arrest = "citizen_male_enhanced"}) do
			if (!ix.act.stored[act] or !ix.act.stored[act][class]) then fail("act " .. act .. " is not registered for " .. class) end
		end
	end

	local hands = player_manager.TranslatePlayerHands("nemezpolice")

	if (!hands or hands.model != "models/weapons/c_arms_combine.mdl") then
		fail("models/police_nemez.mdl has no combine viewmodel hands")
	end
end)

GWH.Check("compat: a zelpa citizen gets a table for each weapon it holds", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	local oldModel = bot:GetModel()
	local seen = {}

	for _, model in ipairs({ZELPA_MALE, "models/humans/group01/male_02.mdl", "models/police_nemez.mdl"}) do
		bot:SetModel(model)

		for _, class in ipairs({"weapon_pistol", "weapon_357", "weapon_smg1", "weapon_ar2", "weapon_shotgun",
			"weapon_crossbow", "weapon_rpg", "weapon_crowbar", "weapon_stunstick", "weapon_frag", "weapon_slam", "ix_hands"}) do
			local weapon = bot:Give(class, true)

			if (IsValid(weapon)) then
				hook.Run("PlayerWeaponChanged", bot, weapon)

				local key = bot.ixAnimModelClass .. "/" .. tostring(bot.ixAnimHoldType)
				seen[key] = true

				if (!istable(bot.ixAnimTable)) then
					fail(model .. " holding " .. class .. " (" .. tostring(bot.ixAnimHoldType) .. ") has no animation table")
				end

				bot:StripWeapon(class)
			end
		end
	end

	bot:SetModel(oldModel)
	bot:Give("ix_hands")
	bot:SelectWeapon("ix_hands")

	return {seen = table.GetKeys(seen)}
end)

-- Knockdown, wake-up and death take timers and a tick for the ragdoll to be deleted, and checks
-- run synchronously, so the scenario runs as soon as the bot joins and the check reads the result.
local scenario = {log = {}}
GWH.compatScenario = scenario

local function Record(name)
	return function(client, value)
		if (scenario.recording) then
			scenario.log[#scenario.log + 1] = {hook = name, client = client, value = value}
		end
	end
end

hook.Add("OnCharacterWakeup", "gw_harness_compat", Record("OnCharacterWakeup"))
hook.Add("OnCharacterWakeupWeapon", "gw_harness_compat", Record("OnCharacterWakeupWeapon"))

local function TakeLog()
	local log = scenario.log
	scenario.log = {}

	return log
end

-- Engine bots run about on their own. The scenario needs one standing still, both so a knockdown
-- starts from rest and so the bot is where the scenario left it.
hook.Add("StartCommand", "gw_harness_compat", function(client, command)
	if (scenario.holdStill and client:IsBot()) then
		command:ClearMovement()
		command:ClearButtons()
	end
end)

-- Helix only counts a timed knockdown down while the ragdoll is still (under 8 units/s), and how
-- long a real model takes to settle after falling varies by model. Putting the body at rest makes
-- the countdown's first tick the one that ends it.
local function PutAtRest(ragdoll)
	for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
		local physObj = ragdoll:GetPhysicsObjectNum(i)

		if (IsValid(physObj)) then
			physObj:SetVelocity(vector_origin)
			physObj:EnableMotion(false)
		end
	end
end

local function PartNames(client)
	return table.concat(table.GetKeys(client:GetParts() or {}), ",")
end

local function ActiveClass(client)
	local weapon = client:GetActiveWeapon()

	return IsValid(weapon) and weapon:GetClass() or nil
end

-- PAC parts of a weapon item across a get-up: worn again when holstered, not when held.
local function RunPACScenario(bot, Step, finish)
	local item = ix.item.list.pistol

	if (!pace or !item or !weapons.GetStored(item.class)) then
		scenario.pac = {skipped = "needs PAC3 and the pistol's SWEP"}
		return finish()
	end

	local inventory = bot:GetCharacter():GetInventory()

	for _, v in pairs(inventory:GetItemsByUniqueID("pistol")) do v:Remove() end

	inventory:Add("pistol")
	local pistol = inventory:HasItem("pistol")
	local partID = ix.plugin.list.pac:GetItemPartID(bot, pistol)

	bot:Give("ix_hands")
	pistol:Equip(bot, true, true)
	bot:SetActiveWeapon(bot:GetWeapon("ix_hands"))

	-- holstered: what switching away from the pistol leaves on
	bot:AddPart(partID, pistol)

	bot:SetRagdolled(true)
	local down = PartNames(bot)
	bot:SetRagdolled(false)

	scenario.pac = {partID = partID, class = pistol.class}

	Step(0.1, function()
		scenario.pac.holstered = {down = down, parts = PartNames(bot), weapon = ActiveClass(bot), equip = pistol:GetData("equip")}

		-- held: the weapon draws itself, so no holstered part
		bot:SetActiveWeapon(bot:GetWeapon(pistol.class))
		bot:RemovePart(partID)

		bot:SetRagdolled(true, 0.2)
		PutAtRest(bot.ixRagdoll)

		Step(0.5, function()
			scenario.pac.held = {parts = PartNames(bot), weapon = ActiveClass(bot), equip = pistol:GetData("equip"), down = IsValid(bot.ixRagdoll)}

			pistol:Remove()
			bot:SelectWeapon("ix_hands")
			finish()
		end)
	end)
end

local function RunScenario(bot)
	local function Step(delay, fn)
		timer.Simple(delay, function()
			if (!IsValid(bot)) then
				scenario.error = "bot left during the scenario"
				scenario.holdStill = false
				return
			end

			local ok, err = pcall(fn)

			if (!ok) then
				scenario.error = tostring(err)
				scenario.holdStill = false
			end
		end)
	end

	local function Finish()
		scenario.holdStill = false
		scenario.done = true
	end

	scenario.holdStill = true

	Step(0.1, function()
		if (!IsValid(bot:GetActiveWeapon())) then
			bot:Give("ix_hands")
			bot:SelectWeapon("ix_hands")
		end

		scenario.weapon = IsValid(bot:GetActiveWeapon()) and bot:GetActiveWeapon():GetClass()
		scenario.recording = true

		-- Timed knockdown of a still player: the countdown removes the ragdoll on its first tick.
		bot:SetLocalVelocity(vector_origin)
		bot:SetRagdolled(true, 0.2)
		scenario.timedRagdoll = bot.ixRagdoll
		PutAtRest(bot.ixRagdoll)

		Step(0.6, function()
			scenario.timed = {
				log = TakeLog(),
				ixRagdoll = bot.ixRagdoll,
				noDraw = bot:GetNoDraw(),
				weapon = IsValid(bot:GetActiveWeapon()) and bot:GetActiveWeapon():GetClass()
			}

			-- Untimed knockdown ended by code: no wake-up, but the weapon comes back.
			bot:SetRagdolled(true)
			bot:SetRagdolled(false)

			Step(0.15, function()
				scenario.manual = {log = TakeLog(), ixRagdoll = bot.ixRagdoll}
				scenario.recording = false

				bot:SetRagdolled(true, 30)

				local ragdoll = bot.ixRagdoll
				bot:Kill()

				scenario.death = {
					ragdoll = IsValid(ragdoll),
					alive = bot:Alive(),
					isDeadPlayer = IsValid(ragdoll) and ragdoll:GetNetVar("isDeadPlayer") or nil
				}

				Step(0.05, function()
					if (!bot:Alive()) then bot:Spawn() end

					Step(0.1, function()
						RunPACScenario(bot, Step, Finish)
					end)
				end)
			end)
		end)
	end)
end

hook.Add("PlayerInitialSpawn", "gw_harness_compat", function(client)
	if (GWH.cfg.mode == "smoke" and client:IsBot() and !scenario.started) then
		scenario.started = true
		RunScenario(client)
	end
end)

GWH.Check("compat: knockdown wake-up hooks and ragdoll state", function(fail)
	if (!scenario.started) then
		return {skipped = "the scenario only runs in a headless run, when the bot joins"}
	end

	if (scenario.error) then fail("scenario error: " .. scenario.error) end
	if (!scenario.done) then return fail("scenario did not finish before the checks ran") end

	local timed, manual, death = scenario.timed, scenario.manual, scenario.death
	local order = {}

	for _, v in ipairs(timed.log) do order[#order + 1] = v.hook end

	if (table.concat(order, ",") != "OnCharacterWakeup,OnCharacterWakeupWeapon") then
		fail("timed knockdown fired [" .. table.concat(order, ",") .. "], expected OnCharacterWakeup then OnCharacterWakeupWeapon")
	else
		if (timed.log[1].value != scenario.timedRagdoll) then fail("OnCharacterWakeup was not passed the ragdoll") end
		if (timed.log[2].value != scenario.weapon) then
			fail("OnCharacterWakeupWeapon was passed " .. tostring(timed.log[2].value) .. ", expected " .. tostring(scenario.weapon))
		end
	end

	if (timed.ixRagdoll != nil) then fail("ixRagdoll is " .. tostring(timed.ixRagdoll) .. " after waking up, expected nil") end
	if (timed.noDraw) then fail("player is still hidden after waking up") end
	if (timed.weapon != scenario.weapon) then fail("active weapon after waking up is " .. tostring(timed.weapon)) end

	local manualOrder = {}

	for _, v in ipairs(manual.log) do manualOrder[#manualOrder + 1] = v.hook end

	if (table.concat(manualOrder, ",") != "OnCharacterWakeupWeapon") then
		fail("SetRagdolled(false) fired [" .. table.concat(manualOrder, ",") .. "], expected only OnCharacterWakeupWeapon")
	end

	if (manual.ixRagdoll != nil) then fail("ixRagdoll is " .. tostring(manual.ixRagdoll) .. " after SetRagdolled(false)") end

	if (!death.ragdoll) then fail("no ragdoll to kill the bot in") end
	if (death.alive) then fail("bot survived Kill()") end
	if (death.isDeadPlayer != true) then fail("ragdoll of the killed bot has isDeadPlayer = " .. tostring(death.isDeadPlayer)) end

	return {weapon = scenario.weapon, timed = order, manual = manualOrder, isDeadPlayer = death.isDeadPlayer}
end)

GWH.Check("compat: PAC parts of weapons come back after getting up", function(fail)
	if (!scenario.started) then
		return {skipped = "the scenario only runs in a headless run, when the bot joins"}
	end

	if (scenario.error) then fail("scenario error: " .. scenario.error) end
	if (!scenario.done) then return fail("scenario did not finish before the checks ran") end

	local pac = scenario.pac
	if (pac.skipped) then return pac end

	local function Has(list, partID)
		return table.HasValue(string.Explode(",", list), partID)
	end

	local holstered, held = pac.holstered, pac.held

	if (Has(holstered.down, pac.partID)) then fail("the holstered " .. pac.partID .. " part stayed on while knocked down") end
	if (!holstered.equip) then fail("the pistol was not equipped again after getting up") end
	if (holstered.weapon != "ix_hands") then fail("holding " .. tostring(holstered.weapon) .. " after getting up, expected ix_hands") end
	if (!Has(holstered.parts, pac.partID)) then
		fail("the holstered pistol's part " .. pac.partID .. " is gone after getting up (parts: " .. holstered.parts .. ")")
	end

	if (held.down) then fail("the timed knockdown holding the pistol did not end") end
	if (!held.equip) then fail("the held pistol was not equipped again after waking up") end
	if (held.weapon != pac.class) then fail("holding " .. tostring(held.weapon) .. " after waking up, expected " .. pac.class) end
	if (Has(held.parts, pac.partID)) then fail("the held pistol also wears its holstered part after waking up") end

	return pac
end)

GWH.Check("compat: PAC override is inert without PAC3", function(fail)
	local plugin = ix.plugin.list.pac
	if (!plugin) then return fail("pac plugin is not loaded") end
	if (!plugin.GetItemPartID) then fail("the schema pac override did not load") end

	if (pace) then
		return {skipped = "PAC3 is installed on this server"}
	end

	if (ix.pac != nil) then fail("ix.pac exists without PAC3") end

	for _, name in ipairs({"PlayerLoadedCharacter", "PlayerSwitchWeapon", "OnPlayerObserve", "InitializedPlugins"}) do
		if (plugin[name]) then fail("pac plugin hooks " .. name .. " without PAC3") end
	end

	local playerMeta = FindMetaTable("Player")
	if (playerMeta.AddPart or playerMeta.GetParts) then fail("player PAC methods exist without PAC3") end

	-- Variant selection, against stand-in players so no state changes.
	local function Client(female, faction)
		local character = {GetFaction = function() return faction end}

		return {
			GetCharacter = function() return character end,
			IsFemale = function() return female end
		}
	end

	local all = {uniqueID = "x", pacData = {}, pacDataMale = {}, pacDataFemale = {}, pacDataMPF = {}}
	local plain = {uniqueID = "y", pacData = {}}
	local maleOnly = {uniqueID = "z", pacDataMale = {}}

	local cases = {
		{Client(false, FACTION_CITIZEN), all, "xmale"},
		{Client(true, FACTION_CITIZEN), all, "xfemale"},
		{Client(true, FACTION_MPF), all, "xmpf"},
		{Client(true, FACTION_MPF), plain, "y"},
		{Client(true, FACTION_CITIZEN), maleOnly, nil},
		{Client(false, FACTION_CITIZEN), maleOnly, "zmale"}
	}

	for i, case in ipairs(cases) do
		local partID = plugin:GetItemPartID(case[1], case[2])

		if (partID != case[3]) then fail("case " .. i .. ": part " .. tostring(partID) .. ", expected " .. tostring(case[3])) end
	end

	local ids = table.concat(plugin:GetItemPartIDs(all), ",")
	if (ids != "x,xfemale,xmale,xmpf") then fail("part ids of a full item are " .. ids) end
end)

GWH.Check("compat: third person and fonts", function(fail)
	local option = ix.option.stored.thirdpersonEnabled

	if (!option) then
		fail("thirdpersonEnabled is not registered on the server")
	elseif (!option.bNetworked) then
		fail("thirdpersonEnabled is not networked")
	end

	if (ix.config.Get("thirdperson") != true) then fail("third person is not allowed by default") end

	local bot = GWH.Bot()

	if (bot and ix.option.Get(bot, "thirdpersonEnabled", "unset") != false) then
		fail("ix.option.Get(bot, \"thirdpersonEnabled\") is " .. tostring(ix.option.Get(bot, "thirdpersonEnabled", "unset")))
	end

	local font = ix.config.stored.font

	if (!font or font.default != "Times New Roman" or ix.config.Get("font") != "Times New Roman") then
		fail("title font is " .. tostring(ix.config.Get("font")) .. ", expected Times New Roman")
	end
end)

GWH.Check("world review: errors inside Helix's SetRagdolled keep their traceback", function(fail)
	local bot = GWH.Bot()
	if (!bot or !ix.plugin.list.ragdollstate) then return fail("no bot or ragdollstate") end

	local playerMeta = FindMetaTable("Player")
	local createRagdoll, timerCreate = playerMeta.CreateServerRagdoll, timer.Create
	local message

	ResetBot(bot)

	playerMeta.CreateServerRagdoll = function()
		error("gw_harness ragdoll failure")
	end

	local ok, err = pcall(bot.SetRagdolled, bot, true, 5)
	playerMeta.CreateServerRagdoll = createRagdoll
	message = tostring(err)

	if (timer.Create != timerCreate) then
		timer.Create = timerCreate
		fail("timer.Create was not put back after the error")
	end

	if (ok) then
		fail("the error inside SetRagdolled was swallowed")
	else
		if (!string.find(message, "gw_harness ragdoll failure", 1, true)) then fail("the error message was lost: " .. message) end
		if (!string.find(message, "stack traceback", 1, true)) then fail("the error lost its traceback: " .. message) end
	end

	ResetBot(bot)

	return {message = string.Left(message, 300)}
end)
