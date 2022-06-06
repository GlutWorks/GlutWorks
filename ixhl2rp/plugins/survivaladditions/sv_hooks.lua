
function PLUGIN:SetupTimer(client, character)
	local steamID = client:SteamID64()

	timer.Create("ixHunger" .. steamID, ix.config.Get("hungerTickTime", 5), 0, function()
		if (IsValid(client) and character) then
			self:HungerTick(client, character, ix.config.Get("hungerTickTime", 5))
		else
			timer.Remove("ixHunger" .. steamID)
		end
	end)
	
	timer.Create("ixThirst" .. steamID, ix.config.Get("thirstTickTime", 5), 0, function()
		if (IsValid(client) and character) then
			self:ThirstTick(client, character, ix.config.Get("thirstTickTime", 5))
		else
			timer.Remove("ixThirst" .. steamID)
		end
	end)
end

function PLUGIN:SetupAllTimers()
	for _, v in ipairs(player.GetAll()) do
		local character = v:GetCharacter()

		if (character) then
			self:SetupTimer(v, character)
		end
	end
end

function PLUGIN:RemoveAllTimers()
	for _, v in ipairs(player.GetAll()) do
		timer.Remove("ixHunger" .. v:SteamID64())
		timer.Remove("ixThirst" .. v:SteamID64())
	end
end

function PLUGIN:HungerEnabled()
	self:SetupAllTimers()
end

function PLUGIN:HungerDisabled()
	self:RemoveAllTimers()
end

function PLUGIN:PlayerLoadedCharacter(client, character, lastCharacter)
	if (ix.config.Get("hungerEnabled", false)) then
		self:SetupTimer(client, character)
	end
end

function PLUGIN:PlayerDeath(client)
	local character = client:GetCharacter()
	character:SetHunger(100)
	character:SetThirst(100)
end

function PLUGIN:HungerTick(client, character, delta)
	if (!client:Alive() or client:GetMoveType() == MOVETYPE_NOCLIP) then
		return
	end

	local scale = 1

	-- update character hunger
	local health = client:Health()
	local hunger = character:GetHunger()
	local newHunger = math.Clamp(hunger - scale * (delta / ix.config.Get("hungerLossTime", 5)), 0, 100)

	character:SetHunger(newHunger)

	if (newHunger == 0) then
		local damage = ix.config.Get("hungerDamage", 2)
		if (damage > 0 and health > 5) then
			-- damage the player if he is starving
			client:ChatNotify("hungerDied")
			client:SetHealth(math.max(5, client:Health() - damage))
		elseif (newHunger == 0) then
			-- kill the player if necessary
			client:NotifyLocalized("hungerDied")
			client:Kill()
			-- client:GetCharacter():SetData("banned", true)
			-- client:GetCharacter():Kick()
		end
	end
end

function PLUGIN:ThirstTick(client, character, delta)
	if (!client:Alive() or client:GetMoveType() == MOVETYPE_NOCLIP) then
		return
	end

	local scale = 1

	-- update character hunger
	local health = client:Health()
	local thirst = character:GetThirst()
	local newThirst = math.Clamp(thirst - scale * (delta / ix.config.Get("thirstLossTime", 5)), 0, 100)

	character:SetThirst(newThirst)

	if (newThirst == 0) then
		local damage = ix.config.Get("thirstDamage", 2)

		if (damage > 0 and health > 5) then
			-- damage the player if he is starving
			client:SetHealth(math.max(5, client:Health() - damage))
		elseif (newThirst == 0) then
			-- kill the player if necessary
			client:NotifyLocalized("thirstDied")
			client:Kill()
			-- client:GetCharacter():SetData("banned", true)
			-- client:GetCharacter():Kick()
		end
	end
end