local PLUGIN = PLUGIN;

function PLUGIN:GetHungerText(amount)
	-- can be implemented later to make zombie and other hostile factions not require hunger
	-- or a different text could be displayed ("decomposing" instead of "starving")
	-- if(LocalPlayer():GetCharacter():GetFaction() != DISABLED_HUNGER_FACTIONS) then
		if ( amount > 80 ) then
			return L("hungerHealthy")
		elseif( amount > 70 ) then
			return L("hungerSnack")
		elseif( amount > 50 ) then
			return L("hungerHungry")
		elseif( amount > 30 ) then
			return L("hungerStarving")
		elseif( amount > 0 ) then
			return L("hungerDeath")
		end
	-- end
end
	
function PLUGIN:GetThirstText(amount)
	-- can be implemented later to make zombie and other hostile factions not require hunger
	-- or a different text could be displayed ("decomposing" instead of "starving")
	-- if(LocalPlayer():GetCharacter():GetFaction() != DISABLED_THIRST_FACTIONS) then
		if ( amount > 80 ) then
			return L("thirstHealthy")
		elseif( amount > 70 ) then
			return L("thirstBit")
		elseif( amount > 50 ) then
			return L("thirstThirsty")
		elseif( amount > 30 ) then
			return L("thirstDehydrated")
		elseif( amount > 0 ) then
			return L("thirstDeath")
		end
	-- end
end

function PLUGIN:HungerEnabled()
	ix.bar.Add(function()
		if (LocalPlayer():GetCharacter()) then
		local hunger = LocalPlayer():GetCharacter():GetHunger()
		return hunger / 100,
		self:GetHungerText(hunger)
		end
	end, Color(241, 117, 15), nil, "hunger")
	
	ix.bar.Add(function()
		if (LocalPlayer():GetCharacter()) then
		local thirst = LocalPlayer():GetCharacter():GetThirst()
		return thirst / 100,
		self:GetThirstText(thirst)
		end
	end, Color(15, 169, 241), nil, "thirst")
end

function PLUGIN:HungerDisabled()
	ix.bar.Remove("hunger")
	ix.bar.Remove("thirst")
end