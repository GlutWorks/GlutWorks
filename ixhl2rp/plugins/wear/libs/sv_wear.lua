
--- The server half of ix.wear: changing condition, wearing, repairing. See sh_wear.lua.
-- @module ix.wear

-- Seconds a repair takes.
ix.wear.REPAIR_TIME = 5
-- Condition points an item's condition may drift from what was last sent to its owner and saved.
ix.wear.STORE_STEP = 0.5

local function IsInstance(item)
	return istable(item) and item.id != nil and isfunction(item.GetData)
end

local function Owner(item, client)
	if (IsValid(client)) then
		return client
	end

	local owner = item:GetOwner()

	return IsValid(owner) and owner or nil
end

--- The item's name as it reads inside a sentence, e.g. "work boots".
function ix.wear.GetDisplayName(item)
	return string.lower(item.GetName and item:GetName() or item.name or "")
end

--- Sets the item's condition, clamped to 0..its ceiling. Fires OnItemConditionLevelChanged when the level
-- changes and calls the item's own OnConditionChanged(old, new, client) if it has one. Returns the new
-- condition and the old and new level.
function ix.wear.SetCondition(item, value, cause, client)
	if (!IsInstance(item) or !isnumber(value) or value != value) then
		return
	end

	local old = ix.wear.GetCondition(item)
	local oldLevel = ix.wear.GetLevel(old)

	value = math.Clamp(value, 0, ix.wear.GetCeiling(item))

	if (value == old) then
		return value, oldLevel, oldLevel
	end

	local newLevel = ix.wear.GetLevel(value)

	-- Walking and time take a few hundredths of a point at a time. Those stay in memory (the server always
	-- reads the true value); the owner and the database get the condition once it has moved STORE_STEP from
	-- what they last got, or when its level changes.
	local stored = item.wearStored or old

	if (newLevel != oldLevel or value <= 0 or math.abs(value - stored) >= ix.wear.STORE_STEP) then
		item.wearStored = value
		item:SetData("condition", value)
	else
		item.wearStored = stored
		item:SetData("condition", value, false, true, true)
	end

	if (newLevel != oldLevel) then
		hook.Run("OnItemConditionLevelChanged", Owner(item, client), item, oldLevel, newLevel, cause)
	end

	if (isfunction(item.OnConditionChanged)) then
		item:OnConditionChanged(old, value, Owner(item, client))
	end

	return value, oldLevel, newLevel
end

--- Wears the item by `amount` condition points, divided by its durability and run through the modifiers.
-- Tells the wearer when an equipped item gets worse by a level. Returns the condition actually removed.
function ix.wear.Damage(item, amount, cause, client)
	if (!ix.config.Get("wearEnabled", true) or !IsInstance(item) or !ix.wear.IsWearable(item)) then
		return 0
	end

	if (!isnumber(amount) or amount != amount or amount <= 0) then
		return 0
	end

	client = Owner(item, client)

	local durability = tonumber(item.durability) or 1

	if (durability <= 0) then
		durability = 1
	end

	amount = ix.wear.ApplyModifiers(client, item, cause, amount / durability)

	local old = ix.wear.GetCondition(item)

	if (amount <= 0 or old <= 0) then
		return 0
	end

	local new, oldLevel, newLevel = ix.wear.SetCondition(item, old - amount, cause, client)

	if (newLevel and newLevel > oldLevel and IsValid(client) and item:GetData("equip")) then
		local notice = ix.wear.LEVELS[newLevel].notice

		if (notice) then
			client:NotifyLocalized(notice .. (item.bPlural and "Plural" or ""), ix.wear.GetDisplayName(item))
		end
	end

	return old - (new or old)
end

--- Raises the condition by amount, up to the ceiling. Returns the condition restored.
function ix.wear.Repair(item, amount)
	if (!IsInstance(item) or !ix.wear.IsWearable(item) or !isnumber(amount) or amount <= 0) then
		return 0
	end

	local old = ix.wear.GetCondition(item)
	local new = ix.wear.SetCondition(item, old + amount, "repair")

	return (new or old) - old
end

--- Lowers the ceiling for one mend: by CEILING_LOSS, not below CEILING_MIN and not below the current
-- condition, so mending never makes an item worse. Returns the new ceiling.
function ix.wear.LowerCeiling(item)
	local ceiling = ix.wear.GetCeiling(item)
	local new = math.min(ceiling, math.max(ix.wear.CEILING_MIN, ceiling - ix.wear.CEILING_LOSS, ix.wear.GetCondition(item)))

	if (new != ceiling) then
		item:SetData("conditionMax", new)
	end

	return new
end

--- One mend: lowers the ceiling, then repairs by amount. Returns the condition restored.
function ix.wear.Mend(item, amount)
	if (!IsInstance(item) or !ix.wear.IsWearable(item)) then
		return 0
	end

	ix.wear.LowerCeiling(item)

	return ix.wear.Repair(item, amount)
end

--- Starts a repair of this kind ("mend" or "plate") as a timed action. Returns whether it started.
function ix.wear.StartRepair(client, item, kind)
	if (!IsValid(client)) then
		return false
	end

	if ((client.ixWearRepairUntil or 0) > CurTime()) then
		client:NotifyLocalized("wearBusy")
		return false
	end

	local result = {ix.wear.CanRepair(client, item, kind)}

	if (!result[1]) then
		client:NotifyLocalized(unpack(result, 2))
		return false
	end

	local itemID = item:GetID()
	local characterID = client:GetCharacter():GetID()

	client.ixWearRepairUntil = CurTime() + ix.wear.REPAIR_TIME + 1
	client:SetAction(kind == "plate" and "@wearPlating" or "@wearMending", ix.wear.REPAIR_TIME, function(target)
		ix.wear.FinishRepair(target, itemID, kind, characterID)
	end)

	return true
end

--- Completes a repair: checks everything again, takes the material, then repairs. Called when the action
-- time is up; returns whether it repaired and how much.
function ix.wear.FinishRepair(client, itemID, kind, characterID)
	if (!IsValid(client)) then
		return false
	end

	client.ixWearRepairUntil = nil

	local character = client:GetCharacter()

	if (!character or (characterID and character:GetID() != characterID)) then
		return false
	end

	local item = ix.item.instances[itemID]

	if (!item) then
		client:NotifyLocalized("wearCannotRepair")
		return false
	end

	local result = {ix.wear.CanRepair(client, item, kind)}

	if (!result[1]) then
		client:NotifyLocalized(unpack(result, 2))
		return false
	end

	local spec = ix.wear.GetRepairSpec(item, kind)

	if (!ix.stack.Take(character:GetInventory(), spec.material, spec.quantity)) then
		client:NotifyLocalized("wearCannotRepair")
		return false
	end

	local restored

	if (kind == "plate") then
		restored = item:Repair(spec.amount)
		client:NotifyLocalized("wearPlated", ix.wear.GetDisplayName(item))
	else
		restored = ix.wear.Mend(item, spec.amount)
		client:NotifyLocalized("wearMended", ix.wear.GetDisplayName(item))
	end

	return true, restored
end
