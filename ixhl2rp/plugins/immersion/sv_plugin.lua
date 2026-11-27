
local PLUGIN = PLUGIN

util.AddNetworkString("ixCheckMagazine")

-- Seconds between two magazine checks by the same player.
PLUGIN.magazineCheckDelay = 1

-- Health fraction -> sentence, worst first: the first row whose limit the fraction is under wins.
PLUGIN.healthWords = {
	{0.15, "feelHealth4"},
	{0.35, "feelHealth3"},
	{0.6, "feelHealth2"},
	{0.9, "feelHealth1"}
}

-- Fraction of a part-full magazine -> sentence, emptiest first: the first row the fraction is at
-- or under wins, and anything above the last is "mostly full".
PLUGIN.magazineWords = {
	{0.2, "ammoMagLow"},
	{0.4, "ammoMagUnderHalf"},
	{0.65, "ammoMagHalf"}
}

local function Survival()
	return ix.plugin.Get("survivaladditions")
end

--- The sentence for one need, or nil when it is not worth mentioning (above the second step).
local function NeedWord(levels, amount, prefix, client)
	local survival = Survival()
	local level = survival:GetNeedLevel(levels, amount)

	if (level <= 1) then
		return
	end

	return L(prefix .. level, client)
end

--- Describes how a player's character feels, in words only, in that player's language. Pass
-- `state` ({health, maxHealth, hunger, thirst, stamina, exhausted}) to describe a made-up state
-- instead of the player's own.
function PLUGIN:DescribeCondition(client, state)
	if (!state) then
		local character = client:GetCharacter()

		state = {
			health = client:Health(),
			maxHealth = client:GetMaxHealth(),
			hunger = character and character:GetHunger() or 100,
			thirst = character and character:GetThirst() or 100,
			stamina = client:GetLocalVar("stm", 100),
			exhausted = client:GetNetVar("brth", false)
		}
	end

	local sentences = {}
	local fraction = state.health / math.max(state.maxHealth or 100, 1)

	for _, v in ipairs(self.healthWords) do
		if (fraction < v[1]) then
			sentences[#sentences + 1] = L(v[2], client)
			break
		end
	end

	local survival = Survival()

	if (survival and ix.config.Get("hungerthirstEnabled", false)) then
		local hunger = NeedWord(survival.hungerLevels, state.hunger, "feelHunger", client)
		local thirst = NeedWord(survival.thirstLevels, state.thirst, "feelThirst", client)

		if (hunger and thirst) then
			sentences[#sentences + 1] = L("feelNeedsBoth", client, hunger, thirst)
		elseif (hunger or thirst) then
			sentences[#sentences + 1] = L("feelNeedsOne", client, hunger or thirst)
		end
	end

	if (state.exhausted) then
		sentences[#sentences + 1] = L("feelBreath3", client)
	elseif (state.stamina < 30) then
		sentences[#sentences + 1] = L("feelBreath2", client)
	elseif (state.stamina < 60) then
		sentences[#sentences + 1] = L("feelBreath1", client)
	end

	if (#sentences == 0) then
		return L("feelFine", client)
	end

	return table.concat(sentences, " ")
end

--- Describes a magazine and the spare rounds for it, in words only.
function PLUGIN:DescribeMagazine(client, clip, maxClip, reserve)
	local phrase

	-- a round chambered over the magazine's size still feels full
	if (clip >= maxClip) then
		phrase = "ammoMagFull"
	elseif (clip <= 0) then
		phrase = "ammoMagEmpty"
	else
		phrase = "ammoMagMost"

		for _, v in ipairs(self.magazineWords) do
			if (clip / maxClip <= v[1]) then
				phrase = v[2]
				break
			end
		end
	end

	local spare = "ammoSparePlenty"

	if (reserve <= 0) then
		spare = "ammoSpareNone"
	elseif (reserve < maxClip) then
		spare = "ammoSpareFew"
	elseif (reserve < maxClip * 3) then
		spare = "ammoSpareSome"
	end

	return L(phrase, client) .. " " .. L(spare, client)
end

function PLUGIN:SendPrivate(client, text)
	ix.chat.Send(client, "feel", text, false, {client})
end

function PLUGIN:SendFeeling(client)
	if (!IsValid(client) or !client:GetCharacter() or !client:Alive()) then
		return
	end

	self:SendPrivate(client, self:DescribeCondition(client))
end

--- Tells a player how full their weapon's magazine feels. `bAsked` is true for /CheckAmmo, which
-- answers with a short line for a weapon without a magazine; Walk + Reload stays silent then.
function PLUGIN:CheckMagazine(client, bAsked)
	if (!IsValid(client) or !client:GetCharacter() or !client:Alive() or IsValid(client.ixRagdoll)) then
		return
	end

	if ((client.ixNextMagazineCheck or 0) > CurTime()) then
		return
	end

	client.ixNextMagazineCheck = CurTime() + self.magazineCheckDelay

	local weapon = client:GetActiveWeapon()

	if (!self:HasMagazine(weapon)) then
		if (bAsked) then
			self:SendPrivate(client, L("ammoNoMagazine", client))
		end

		return
	end

	local reserve = client:GetAmmoCount(weapon:GetPrimaryAmmoType())

	self:SendPrivate(client, self:DescribeMagazine(client, weapon:Clip1(), weapon:GetMaxClip1(), reserve))
end

-- Walk + Reload on the client (see PlayerBindPress in cl_plugin.lua). Everything is checked here.
net.Receive("ixCheckMagazine", function(length, client)
	PLUGIN:CheckMagazine(client)
end)
