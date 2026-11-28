
local PLUGIN = PLUGIN

PLUGIN.WOUND_TICK_INTERVAL = 5
PLUGIN.TREAT_DURATION = 3

local function CleanWounds(raw)
	local clean = {}

	if (!istable(raw)) then
		return clean
	end

	for _, region in ipairs(ix.body.REGIONS) do
		local entry = raw[region]

		if (istable(entry) and ix.body.IsWoundKind(entry.kind) and isnumber(entry.severity) and entry.severity > 0) then
			local state = entry.state == "dressed" and "dressed" or "open"
			clean[region] = {
				kind = entry.kind,
				region = region,
				severity = math.Clamp(entry.severity, 1, 100),
				state = state,
				dressedAt = state == "dressed" and tonumber(entry.dressedAt) or nil
			}
		end
	end

	return clean
end

--- Sends a private line in words through immersion when loaded, otherwise as a notice.
function PLUGIN:Tell(client, phrase, ...)
	if (!IsValid(client)) then
		return
	end

	local immersion = ix.plugin.Get("immersion")

	if (immersion and isfunction(immersion.SendPrivate)) then
		immersion:SendPrivate(client, L(phrase, client, ...))
	else
		client:NotifyLocalized(phrase, ...)
	end
end

local function CancelTreatment(client)
	if (!IsValid(client)) then
		return
	end

	if (client.ixBodyTreating) then
		client.ixBodyTreating = nil
		client:SetAction()
	end
end

--- Syncs character wounds to the owning player (`bodyWounds`) and compact arm/leg effects (`bodyWoundEffects`).
function ix.body.SyncWounds(client)
	if (!IsValid(client)) then
		return
	end

	local character = client:GetCharacter()
	local wounds = character and CleanWounds(character:GetData("wounds", {})) or {}
	local effects = ix.body.ComputeWoundEffects(wounds)

	client:SetLocalVar("bodyWounds", wounds)
	client:SetNetVar("bodyWoundEffects", effects)
end

--- Inflicts or worsens a wound on canonical `region` (`"cut"` or `"gunshot"`, severity `1..100`).
-- Reopens a dressed wound if hit again on that region.
function ix.body.AddWound(client, region, kind, severity)
	if (!IsValid(client) or !ix.body.IsRegion(region) or !ix.body.IsWoundKind(kind)) then
		return false
	end

	local character = client:GetCharacter()

	if (!character) then
		return false
	end

	local amount = tonumber(severity)

	if (!amount or amount <= 0) then
		return false
	end

	local wounds = CleanWounds(character:GetData("wounds", {}))
	local existing = wounds[region]
	local newSeverity = math.Clamp(math.Round(amount), 1, 100)
	local newKind = kind

	if (existing) then
		newSeverity = math.Clamp(math.Round(existing.severity + amount), 1, 100)

		if (existing.kind == "gunshot") then
			newKind = "gunshot"
		end
	end

	local wound = {
		kind = newKind,
		region = region,
		severity = newSeverity,
		state = "open",
		dressedAt = nil
	}

	wounds[region] = wound
	character:SetData("wounds", wounds)
	ix.body.SyncWounds(client)

	hook.Run("OnCharacterWounded", client, wound)

	return wound
end

--- Sets an exact open wound on canonical `region` (severity <= 0 removes it). Used by admin commands.
function ix.body.SetWound(client, region, kind, severity)
	if (!IsValid(client) or !ix.body.IsRegion(region)) then
		return false
	end

	local character = client:GetCharacter()

	if (!character) then
		return false
	end

	local amount = tonumber(severity) or 0

	if (amount <= 0) then
		ix.body.RemoveWound(client, region)
		return nil
	end

	if (!ix.body.IsWoundKind(kind)) then
		return false
	end

	local wounds = CleanWounds(character:GetData("wounds", {}))
	local wound = {
		kind = kind,
		region = region,
		severity = math.Clamp(math.Round(amount), 1, 100),
		state = "open",
		dressedAt = nil
	}

	wounds[region] = wound
	character:SetData("wounds", wounds)
	ix.body.SyncWounds(client)

	hook.Run("OnCharacterWounded", client, wound)

	return wound
end

--- Removes any wound on canonical `region`.
function ix.body.RemoveWound(client, region)
	if (!IsValid(client) or !ix.body.IsRegion(region)) then
		return false
	end

	local character = client:GetCharacter()

	if (!character) then
		return false
	end

	local wounds = CleanWounds(character:GetData("wounds", {}))

	if (!wounds[region]) then
		return false
	end

	wounds[region] = nil
	character:SetData("wounds", wounds)
	ix.body.SyncWounds(client)

	return true
end

--- Clears all active wounds on client.
function ix.body.ClearWounds(client)
	if (!IsValid(client)) then
		return false
	end

	CancelTreatment(client)

	local character = client:GetCharacter()

	if (character) then
		character:SetData("wounds", {})
	end

	ix.body.SyncWounds(client)

	return true
end

--- Dresses an open wound on `region` (or the worst open wound when `region` is nil).
-- Immediately halves felt arm/leg penalties, notifies the player, and fires `OnWoundTreated`.
function ix.body.TreatWound(client, region)
	if (!IsValid(client)) then
		return false
	end

	local character = client:GetCharacter()

	if (!character) then
		return false
	end

	if (!region) then
		local _, worstRegion = ix.body.GetWorstOpenWound(client)
		region = worstRegion
	end

	if (!ix.body.IsRegion(region)) then
		return false
	end

	local wounds = CleanWounds(character:GetData("wounds", {}))
	local wound = wounds[region]

	if (!wound or wound.state != "open") then
		return false
	end

	wound.state = "dressed"
	wound.dressedAt = CurTime()

	character:SetData("wounds", wounds)
	ix.body.SyncWounds(client)

	PLUGIN:Tell(client, "bodyWoundTreated", wound.kind, string.lower(ix.body.GetRegionLabel(region)))
	hook.Run("OnWoundTreated", client, wound)

	return wound
end

--- Re-validates player, bandage item, and open wound, then consumes the bandage, restores health,
-- and dresses the wound.
function ix.body.FinishTreatWound(client, itemOrID, region, expectedCharID)
	if (!IsValid(client)) then
		return false
	end

	client.ixBodyTreating = nil

	if (!client:Alive() or client:IsRestricted() or IsValid(client.ixRagdoll)) then
		return false
	end

	local character = client:GetCharacter()

	if (!character or (expectedCharID and character:GetID() != expectedCharID)) then
		return false
	end

	local itemID = istable(itemOrID) and itemOrID.id or itemOrID
	local inventory = character:GetInventory()
	local item = inventory and isnumber(itemID) and inventory:GetItemByID(itemID, false)

	if (!item) then
		return false
	end

	if (region) then
		local targetWound = ix.body.GetWound(client, region)

		if (!targetWound or targetWound.state != "open") then
			return false
		end
	elseif (!ix.body.HasOpenWound(client)) then
		return false
	end

	item:Remove()
	client:SetHealth(math.min(client:Health() + 20, client:GetMaxHealth()))
	client:EmitSound("items/medshot4.wav", 65, 100, 0.7)

	return ix.body.TreatWound(client, region)
end

--- Starts a timed action to bind an open wound with `item` (bandage).
function ix.body.StartTreatWound(client, item, region)
	if (!IsValid(client) or !client:Alive() or client:IsRestricted() or IsValid(client.ixRagdoll)) then
		return false
	end

	local character = client:GetCharacter()

	if (!character or !istable(item)) then
		return false
	end

	if (client.ixBodyTreating and client.ixBodyTreating > CurTime()) then
		client:NotifyLocalized("bodyAlreadyTreating")
		return false
	end

	if (region) then
		if (!ix.body.IsRegion(region)) then
			return false
		end

		local wound = ix.body.GetWound(client, region)

		if (!wound or wound.state != "open") then
			return false
		end
	elseif (!ix.body.HasOpenWound(client)) then
		return false
	end

	local itemID = item.id
	local charID = character:GetID()
	local duration = PLUGIN.TREAT_DURATION

	client.ixBodyTreating = CurTime() + duration + 0.5
	client:SetAction("Binding wound...", duration, function(ply)
		ix.body.FinishTreatWound(ply, itemID, region, charID)
	end)

	return true
end

--- Advances dressed wound healing over `delta` seconds.
function PLUGIN:WoundTick(client, character, delta)
	if (!ix.config.Get("bodyWoundsEnabled", true) or !IsValid(client) or !client:Alive()) then
		return
	end

	if (client:GetCharacter() != character or !isnumber(delta) or delta <= 0) then
		return
	end

	local raw = character:GetData("wounds", {})

	if (!istable(raw) or table.IsEmpty(raw)) then
		return
	end

	local wounds = CleanWounds(raw)
	local healTime = math.max(ix.config.Get("bodyWoundHealTime", 180), 1)
	local healAmount = (delta / healTime) * 100
	local bChanged = false
	local improved, healed = {}, {}

	for _, region in ipairs(ix.body.REGIONS) do
		local wound = wounds[region]

		if (wound and wound.state == "dressed") then
			local oldBand = ix.body.GetWoundSeverityWord(wound.severity)
			local newSeverity = wound.severity - healAmount

			bChanged = true

			if (newSeverity <= 0) then
				wounds[region] = nil
				healed[#healed + 1] = {region = region, kind = wound.kind}
			else
				wound.severity = newSeverity

				local newBand = ix.body.GetWoundSeverityWord(newSeverity)

				if (newBand != oldBand) then
					improved[#improved + 1] = {region = region, kind = wound.kind, band = newBand}
				end
			end
		end
	end

	if (!bChanged) then
		return
	end

	character:SetData("wounds", wounds)
	ix.body.SyncWounds(client)

	for _, entry in ipairs(improved) do
		self:Tell(client, "bodyWoundImproved", entry.kind, string.lower(ix.body.GetRegionLabel(entry.region)), entry.band)
	end

	for _, entry in ipairs(healed) do
		self:Tell(client, "bodyWoundHealed", entry.kind, string.lower(ix.body.GetRegionLabel(entry.region)))
		hook.Run("OnWoundHealed", client, entry.region, entry.kind)
	end
end

--- Describes every active wound for `/Feel`, or returns nil when uninjured.
function PLUGIN:DescribeWounds(client)
	if (!ix.config.Get("bodyWoundsEnabled", true) or !IsValid(client) or !client:GetCharacter()) then
		return
	end

	local wounds = ix.body.GetWounds(client)
	local sentences = {}

	for _, region in ipairs(ix.body.REGIONS) do
		local wound = wounds[region]

		if (istable(wound)) then
			local severityWord = ix.body.GetWoundSeverityWord(wound.severity)
			local regionName = string.lower(ix.body.GetRegionLabel(region))
			local phrase = wound.state == "dressed" and "feelWoundDressed" or "feelWoundOpen"

			sentences[#sentences + 1] = L(phrase, client, severityWord, wound.kind, regionName)
		end
	end

	if (#sentences > 0) then
		return table.concat(sentences, " ")
	end
end

--- Appends wound descriptions to `/Feel` output, replacing `"You feel fine."` when wounded.
function PLUGIN:AppendWoundDescription(client, text)
	local extra = self:DescribeWounds(client)

	if (!extra) then
		return text
	end

	if (!isstring(text) or text == "" or text == L("feelFine", client)) then
		return extra
	end

	return text .. " " .. extra
end

--- Wraps immersion's `DescribeCondition` once so `/Feel` reports active wounds.
function PLUGIN:WrapImmersion()
	local immersion = ix.plugin.Get("immersion")

	if (!immersion or !isfunction(immersion.DescribeCondition)) then
		return false
	end

	if (immersion.DescribeCondition == immersion.ixBodyWoundsWrapper) then
		return false
	end

	if (immersion.ixExposureWrapper and immersion.DescribeCondition == immersion.ixExposureWrapper
		and immersion.ixExposureOriginal == immersion.ixBodyWoundsWrapper) then
		return false
	end

	local original = immersion.DescribeCondition
	local function wrapper(this, client, ...)
		local text = original(this, client, ...)
		local body = ix.plugin.Get("body")

		if (!body or !IsValid(client)) then
			return text
		end

		return body:AppendWoundDescription(client, text)
	end

	immersion.ixBodyWoundsOriginal = original
	immersion.ixBodyWoundsWrapper = wrapper
	immersion.DescribeCondition = wrapper

	return true
end

function PLUGIN:StartWoundTimer()
	local interval = self.WOUND_TICK_INTERVAL

	timer.Create("ixBodyWounds", interval, 0, function()
		if (!ix.config.Get("bodyWoundsEnabled", true)) then
			return
		end

		for _, client in player.Iterator() do
			local character = client:GetCharacter()

			if (character and client:Alive()) then
				self:WoundTick(client, character, interval)
			end
		end
	end)
end

function PLUGIN:InitializedPlugins()
	self:WrapImmersion()
	self:StartWoundTimer()
end

function PLUGIN:PostEntityTakeDamage(target, dmg, bTook)
	if (!ix.config.Get("bodyWoundsEnabled", true) or !bTook) then
		return
	end

	if (!IsValid(target) or !target:IsPlayer() or !target:Alive() or !target:GetCharacter()) then
		return
	end

	local damage = dmg:GetDamage()

	if (damage < 5) then
		return
	end

	local bSlash = dmg:IsDamageType(DMG_SLASH)
	local bShot = dmg:IsDamageType(DMG_BULLET) or dmg:IsDamageType(DMG_BUCKSHOT)

	if (!bSlash and !bShot) then
		return
	end

	local region = ix.body.HitGroupToRegion(target:LastHitGroup(), dmg:GetDamageType())
	local kind = bSlash and "cut" or "gunshot"
	local severity = math.Clamp(math.Round(damage * 2.2), 15, 100)
	local wound = ix.body.AddWound(target, region, kind, severity)

	if (wound) then
		local phrase = wound.kind == "cut" and "bodyWoundCut" or "bodyWoundGunshot"
		local word = ix.body.GetWoundSeverityWord(wound.severity)
		local regionName = string.lower(ix.body.GetRegionLabel(region))

		self:Tell(target, phrase, word, regionName)
	end
end

function PLUGIN:PrePlayerLoadedCharacter(client, character, lastCharacter)
	CancelTreatment(client)
	client.ixBodyLoadingChar = true
end

function PLUGIN:PlayerLoadedCharacter(client, character, lastCharacter)
	client.ixBodyLoadingChar = nil
	CancelTreatment(client)
	ix.body.SyncWounds(client)
end

function PLUGIN:PlayerSpawn(client)
	CancelTreatment(client)

	if (client.ixBodyLoadingChar) then
		ix.body.SyncWounds(client)
		return
	end

	ix.body.ClearWounds(client)
end

function PLUGIN:PlayerDeath(client)
	ix.body.ClearWounds(client)
end

-- Restart the wound timer on Lua refresh so it calls this load's functions.
if (timer.Exists("ixBodyWounds")) then
	PLUGIN:StartWoundTimer()
end
