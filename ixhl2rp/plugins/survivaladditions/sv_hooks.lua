
local PLUGIN = PLUGIN

PLUGIN.needs = {
	hunger = {
		get = "GetHunger",
		set = "SetHunger",
		lossTime = "hungerLossTime",
		damage = "hungerDamage",
		died = "hungerDied"
	},
	thirst = {
		get = "GetThirst",
		set = "SetThirst",
		lossTime = "thirstLossTime",
		damage = "thirstDamage",
		died = "thirstDied"
	}
}

function PLUGIN:GetTimerName(character)
	return "ixNeeds" .. character:GetID()
end

--- Starts the hunger/thirst tick for a loaded character. One timer per character, removed
-- when the character unloads or its player leaves.
function PLUGIN:StartNeeds(character)
	local name = self:GetTimerName(character)

	if (!ix.config.Get("hungerthirstEnabled", false)) then
		timer.Remove(name)
		return
	end

	local id = character:GetID()
	local delay = ix.config.Get("needsTickTime", 5)

	timer.Create(name, delay, 0, function()
		local client = character:GetPlayer()
		local current = IsValid(client) and client:GetCharacter()

		if (!current or current:GetID() != id) then
			timer.Remove(name)
			return
		end

		self:NeedsTick(client, character, delay)
	end)
end

function PLUGIN:StopNeeds(character)
	timer.Remove(self:GetTimerName(character))
end

function PLUGIN:SetupAllTimers()
	for _, v in ipairs(player.GetAll()) do
		local character = v:GetCharacter()

		if (character) then
			self:StartNeeds(character)
		end
	end
end

function PLUGIN:CharacterLoaded(character)
	self:StartNeeds(character)
end

function PLUGIN:PlayerLoadedCharacter(client, character, lastCharacter)
	if (lastCharacter) then
		self:StopNeeds(lastCharacter)
	end
end

function PLUGIN:OnCharacterDisconnect(client, character)
	self:StopNeeds(character)
end

function PLUGIN:GetPoisonTimerName(client)
	return "ixPoison" .. client:SteamID64()
end

function PLUGIN:PlayerDeath(client)
	timer.Remove(self:GetPoisonTimerName(client))

	local character = client:GetCharacter()

	if (!character) then
		return
	end

	-- Respawning must not be a free refill, but starting at zero would kill again at once.
	local level = ix.config.Get("needsRespawnLevel", 50)

	character:SetHunger(level)
	character:SetThirst(level)
end

--- Drains one need by `delta` seconds' worth and applies damage while it is empty.
function PLUGIN:DrainNeed(client, character, info, delta)
	local old = character[info.get](character)
	local perSecond = 100 / (ix.config.Get(info.lossTime) * 60)
	local new = math.max(old - perSecond * delta, 0)

	character[info.set](character, new)

	-- Reaching zero is felt through the immersion plugin's body feedback, not announced.
	if (new > 0) then
		return
	end

	local damage = ix.config.Get(info.damage, 2)

	if (damage <= 0) then
		return
	end

	local health = client:Health() - damage

	if (health > 0) then
		client:SetHealth(health)
	else
		client:NotifyLocalized(info.died)
		client:Kill()
	end
end

function PLUGIN:NeedsTick(client, character, delta)
	if (!ix.config.Get("hungerthirstEnabled", false) or !client:Alive() or client:GetMoveType() == MOVETYPE_NOCLIP) then
		return
	end

	for _, info in ipairs({self.needs.hunger, self.needs.thirst}) do
		-- starving to death resets the bars; the rest of this tick must not drain them again
		if (!client:Alive()) then
			break
		end

		self:DrainNeed(client, character, info, delta)
	end
end

--- Gives a player one item, filling an existing stack where the stacking plugin is present,
-- and drops it at their feet when it does not fit.
function PLUGIN:GiveItem(client, uniqueID)
	local character = client:GetCharacter()
	local inventory = character and character:GetInventory()
	local itemTable = ix.item.list[uniqueID]

	if (!itemTable) then
		return
	end

	if (ix.stack and ix.stack.IsStackable(itemTable)) then
		local bSuccess = inventory and ix.stack.Give(inventory, uniqueID, 1)

		if (!bSuccess) then
			ix.stack.Spawn(uniqueID, client:GetItemDropPos(), 1)
		end

		return
	end

	if (!inventory or !inventory:Add(uniqueID)) then
		ix.item.Spawn(uniqueID, client)
	end
end

--- Applies a food or drink item's effects. Called from the base_eatable and base_drinkable actions.
function PLUGIN:Consume(item, client)
	local character = client:GetCharacter()

	if (!character) then
		return false
	end

	if (item.restoredHunger != 0) then
		character:SetHunger(math.Clamp(character:GetHunger() + item.restoredHunger, 0, 100))
	end

	if (item.restoredThirst != 0) then
		character:SetThirst(math.Clamp(character:GetThirst() + item.restoredThirst, 0, 100))
	end

	if (item.restoredHealth > 0) then
		client:SetHealth(math.min(client:Health() + item.restoredHealth, client:GetMaxHealth()))
	end

	if (item.restoredStamina > 0 and client.RestoreStamina) then
		client:RestoreStamina(item.restoredStamina)
	end

	if (item.useSound) then
		client:EmitSound(item.useSound, 75, item.useSoundPitch or 100, 0.35)
	end

	if (item.bMessy) then
		local effect = EffectData()
			effect:SetStart(client:EyePos())
			effect:SetOrigin(client:EyePos())
			effect:SetScale(0.25)
			effect:SetNormal(client:EyeAngles():Forward())
		util.Effect("StriderBlood", effect)
	end

	for _, uniqueID in ipairs(item.items or {}) do
		self:GiveItem(client, uniqueID)
	end

	if (item.OnConsumed) then
		item:OnConsumed(client)
	end

	return true
end
