
--- Canonical body regions, hitgroup mapping, garment coverage and pocket definitions.
-- Shared across hits, clothing wear, exposure, carry pockets and frisks with no translation.
-- @module ix.body

ix.body = ix.body or {}

ix.body.REGIONS = {"head", "chest", "waist", "arms", "legs", "feet"}

ix.body.REGION_SET = {}
for _, region in ipairs(ix.body.REGIONS) do
	ix.body.REGION_SET[region] = true
end

ix.body.REGION_LABELS = {
	head = "Head",
	chest = "Chest",
	waist = "Waist",
	arms = "Arms",
	legs = "Legs",
	feet = "Feet"
}

ix.body.FRISK_ORDER = {"waist", "chest", "arms", "legs", "head", "feet"}

ix.body.BASE_PLACES = {
	belt = {key = "belt", name = "Utility belt", region = "waist", limit = 2, concealment = 0.0},
	sling = {key = "sling", name = "Shoulder sling", region = "chest", limit = 2, concealment = 0.0},
	pockets = {key = "pockets", name = "Trouser pockets", region = "legs", limit = 4, concealment = 0.2},
	boot = {key = "boot", name = "Boot lining", region = "feet", limit = 1, concealment = 0.85},
	hands = {key = "hands", name = "Hand-carried", region = "arms", limit = nil, concealment = 0.0}
}

-- Fallback regions for wearables/outfits that only specify wearPart or outfitCategory == "model".
ix.body.WEAR_PART_REGIONS = {
	head = {"head"},
	outer = {"chest", "waist", "arms"},
	body = {"chest", "waist", "arms", "legs"},
	hands = {"arms"},
	feet = {"feet"}
}

local HITGROUP_REGIONS = {
	[HITGROUP_HEAD] = "head",
	[HITGROUP_CHEST] = "chest",
	[HITGROUP_GENERIC] = "chest",
	[HITGROUP_STOMACH] = "waist",
	[HITGROUP_LEFTARM] = "arms",
	[HITGROUP_RIGHTARM] = "arms",
	[HITGROUP_LEFTLEG] = "legs",
	[HITGROUP_RIGHTLEG] = "legs"
}

local LAYER_ORDER = {
	outer = 1,
	body = 2
}

local function Definition(item)
	if (isstring(item)) then
		return ix.item.list[item]
	end

	return item
end

--- Whether region is a canonical body region ID.
function ix.body.IsRegion(region)
	return isstring(region) and ix.body.REGION_SET[region] == true
end

--- Human-readable label for a canonical body region.
function ix.body.GetRegionLabel(region)
	return ix.body.REGION_LABELS[region] or tostring(region or "")
end

--- Maps an engine hitgroup and damage type bitmask to a canonical body region.
function ix.body.HitGroupToRegion(hitGroup, damageType)
	if (isnumber(damageType) and bit.band(damageType, DMG_FALL) != 0) then
		return "feet"
	end

	return HITGROUP_REGIONS[hitGroup] or "chest"
end

--- Returns the validated list of canonical regions covered by an item definition, instance or uniqueID.
function ix.body.GetItemRegions(item)
	item = Definition(item)

	if (!istable(item)) then
		return {}
	end

	local source

	if (istable(item.regions)) then
		source = item.regions
	elseif (isstring(item.wearPart) and ix.body.WEAR_PART_REGIONS[item.wearPart]) then
		source = ix.body.WEAR_PART_REGIONS[item.wearPart]
	elseif (item.outfitCategory == "model") then
		source = ix.body.WEAR_PART_REGIONS.body
	end

	if (!source) then
		return {}
	end

	local result, seen = {}, {}

	for _, region in ipairs(source) do
		if (ix.body.IsRegion(region) and !seen[region]) then
			seen[region] = true
			result[#result + 1] = region
		end
	end

	return result
end

--- Whether the item covers the given canonical region.
function ix.body.CoversRegion(item, region)
	if (!ix.body.IsRegion(region)) then
		return false
	end

	for _, covered in ipairs(ix.body.GetItemRegions(item)) do
		if (covered == region) then
			return true
		end
	end

	return false
end

--- Damage wear share for an item on a specific canonical region (defaults to 1).
function ix.body.GetRegionWearShare(item, region)
	item = Definition(item)

	if (istable(item) and istable(item.regionWearShare) and isnumber(item.regionWearShare[region])) then
		return math.max(item.regionWearShare[region], 0)
	end

	return 1
end

--- Returns worn garments covering region, ordered outer -> body -> other.
function ix.body.GetCoveringGarments(client, region)
	local result = {}

	if (!ix.wear or !ix.body.IsRegion(region)) then
		return result
	end

	for _, item in ipairs(ix.wear.GetWorn(client)) do
		if (ix.body.CoversRegion(item, region)) then
			result[#result + 1] = item
		end
	end

	table.sort(result, function(a, b)
		local layerA = LAYER_ORDER[a.wearPart] or 3
		local layerB = LAYER_ORDER[b.wearPart] or 3

		if (layerA != layerB) then
			return layerA < layerB
		end

		return a:GetID() < b:GetID()
	end)

	return result
end

--- Returns validated pocket definitions for an item definition, instance or uniqueID.
-- Each returned entry has id, name, region (canonical), capacity (> 0), concealment (0..1) and optional key.
function ix.body.GetItemPockets(item)
	item = Definition(item)

	if (!istable(item) or !istable(item.pockets)) then
		return {}
	end

	local result = {}
	local baseName = (isfunction(item.GetName) and item:GetName()) or item.name or "Garment"

	for index, pocket in ipairs(item.pockets) do
		if (istable(pocket) and ix.body.IsRegion(pocket.region)
			and isnumber(pocket.capacity) and pocket.capacity > 0
			and isnumber(pocket.concealment) and pocket.concealment >= 0 and pocket.concealment <= 1) then
			result[#result + 1] = {
				id = isstring(pocket.id) and pocket.id or tostring(index),
				key = isstring(pocket.key) and pocket.key or nil,
				name = isstring(pocket.name) and pocket.name or (baseName .. " pocket"),
				region = pocket.region,
				capacity = pocket.capacity,
				concealment = pocket.concealment
			}
		end
	end

	return result
end
