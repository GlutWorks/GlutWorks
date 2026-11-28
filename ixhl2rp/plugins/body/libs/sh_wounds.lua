
--- Persistent regional wounds, severity words and felt arm/leg effect calculations.
-- Stored per character in character data `"wounds"` (keyed by canonical region), synced to the
-- owning player via local var `"bodyWounds"` and summarized in netvar `"bodyWoundEffects"` for
-- shared SetupMove prediction.
-- @module ix.body

ix.body = ix.body or {}

ix.body.WOUND_KINDS = {
	cut = true,
	gunshot = true
}

ix.body.WOUND_KIND_LABELS = {
	cut = "Cut",
	gunshot = "Gunshot"
}

--- Whether kind is a supported wound kind (`"cut"` or `"gunshot"`).
function ix.body.IsWoundKind(kind)
	return isstring(kind) and ix.body.WOUND_KINDS[kind] == true
end

--- Human-readable label for a wound kind.
function ix.body.GetWoundKindLabel(kind)
	return ix.body.WOUND_KIND_LABELS[kind] or tostring(kind or "")
end

--- Severity band word for a wound severity (`1..100`).
function ix.body.GetWoundSeverityWord(severity)
	severity = tonumber(severity) or 0

	if (severity >= 70) then
		return "severe"
	elseif (severity >= 35) then
		return "moderate"
	end

	return "minor"
end

--- Returns the table of active wounds for client, keyed by canonical region.
function ix.body.GetWounds(client)
	if (!IsValid(client)) then
		return {}
	end

	if (SERVER) then
		local character = client:GetCharacter()
		local wounds = character and character:GetData("wounds", {})

		return istable(wounds) and wounds or {}
	end

	local wounds = client:GetLocalVar("bodyWounds")

	return istable(wounds) and wounds or {}
end

--- Returns the active wound on canonical `region`, or nil.
function ix.body.GetWound(client, region)
	if (!ix.body.IsRegion(region)) then
		return
	end

	return ix.body.GetWounds(client)[region]
end

--- Whether client has at least one open (undressed) wound.
function ix.body.HasOpenWound(client)
	for _, wound in pairs(ix.body.GetWounds(client)) do
		if (istable(wound) and wound.state == "open") then
			return true
		end
	end

	return false
end

--- Returns the open wound with highest severity and its canonical region, or nil.
function ix.body.GetWorstOpenWound(client)
	local wounds = ix.body.GetWounds(client)
	local worst, worstRegion

	for _, region in ipairs(ix.body.REGIONS) do
		local wound = wounds[region]

		if (istable(wound) and wound.state == "open") then
			if (!worst or (wound.severity or 0) > (worst.severity or 0)) then
				worst = wound
				worstRegion = region
			end
		end
	end

	if (worst) then
		return worst, worstRegion
	end
end

--- Computes compact arm tremor (0..1) and leg speed penalty (0..0.35) from a wounds table.
function ix.body.ComputeWoundEffects(wounds)
	local arms, legs = 0, 0

	if (!istable(wounds)) then
		return {arms = 0, legs = 0}
	end

	local armWound = wounds.arms

	if (istable(armWound) and isnumber(armWound.severity) and armWound.severity > 0) then
		local fraction = math.Clamp(armWound.severity / 100, 0, 1)
		local shake = Lerp(fraction, 0.15, 1.0)

		if (armWound.state == "dressed") then
			shake = shake * 0.5
		end

		arms = math.Clamp(shake, 0, 1)
	end

	for _, region in ipairs({"legs", "feet"}) do
		local wound = wounds[region]

		if (istable(wound) and isnumber(wound.severity) and wound.severity > 0) then
			local fraction = math.Clamp(wound.severity / 100, 0, 1)
			local penalty = Lerp(fraction, 0.10, 0.35)

			if (wound.state == "dressed") then
				penalty = penalty * 0.5
			end

			if (penalty > legs) then
				legs = penalty
			end
		end
	end

	return {
		arms = arms,
		legs = math.Clamp(legs, 0, 0.35)
	}
end

--- Movement speed multiplier from leg/foot wounds: 1 when uninjured, 0.90..0.65 open, 0.95..0.825 dressed.
function ix.body.GetLegSpeedScale(client)
	if (!ix.config.Get("bodyWoundsEnabled", true) or !IsValid(client)) then
		return 1
	end

	local effects = client:GetNetVar("bodyWoundEffects")
	local penalty

	if (istable(effects) and isnumber(effects.legs)) then
		penalty = effects.legs
	else
		penalty = ix.body.ComputeWoundEffects(ix.body.GetWounds(client)).legs
	end

	if (penalty <= 0) then
		return 1
	end

	return math.Clamp(1 - penalty, 0.5, 1)
end

--- Aim tremor strength (0..1) from arm wounds: 0 when uninjured, 0.15..1.0 open, halved once dressed.
function ix.body.GetArmShake(client)
	if (!ix.config.Get("bodyWoundsEnabled", true) or !IsValid(client)) then
		return 0
	end

	local effects = client:GetNetVar("bodyWoundEffects")

	if (istable(effects) and isnumber(effects.arms)) then
		return math.Clamp(effects.arms, 0, 1)
	end

	return ix.body.ComputeWoundEffects(ix.body.GetWounds(client)).arms
end

--- Finds the fastest-access bandage carried by `client` (lowest accessTime first).
-- Returns `{item, place, placeName, accessTime}` or nil when none is carried.
function ix.body.FindDressing(client, groups)
	if (!IsValid(client) and !istable(groups)) then
		return nil
	end

	if (istable(groups) or (ix.datapad and isfunction(ix.datapad.Layout))) then
		if (!istable(groups)) then
			local character = client:GetCharacter()
			local inv = character and character:GetInventory()

			if (!inv) then
				return nil
			end

			local wetness = character.GetWetness and character:GetWetness() or 0
			groups = ix.datapad.Layout(inv, wetness)
		end

		local best

		for _, place in ipairs(groups) do
			local accessTime = isnumber(place.accessTime) and place.accessTime
				or (ix.datapad and ix.datapad.GetAccessTime and ix.datapad.GetAccessTime(place) or 0)

			for _, item in ipairs(place.items or {}) do
				if (item.uniqueID == "bandage") then
					if (!best or accessTime < best.accessTime) then
						best = {
							item = item,
							place = place,
							placeName = place.name,
							accessTime = accessTime
						}
					end
				end
			end
		end

		return best
	end

	local character = client:GetCharacter()
	local inv = character and character:GetInventory()

	if (!inv) then
		return nil
	end

	for _, item in pairs(inv:GetItems()) do
		if (item.uniqueID == "bandage") then
			return {
				item = item,
				place = nil,
				placeName = "inventory",
				accessTime = 0
			}
		end
	end

	return nil
end
