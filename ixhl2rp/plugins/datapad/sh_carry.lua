local pad = ix.datapad

function pad.Size(item)
	return item.width * item.height > 1 and 2 or 1
end

function pad.Weight(item)
	local unit = item.carryWeight or (item.stackUnit == "kg" and 1)
		or (item.stackLimit and 0.08) or (item.isWeapon and 0.85 * pad.Size(item)) or 0.35 * pad.Size(item)
	return unit * ix.stack.GetQuantity(item)
end

function pad.Contraband(item)
	return item.contraband == true or item.isWeapon or item.ammoAmount or item.uniqueID == "book_rev"
end

local function worn(item)
	return item.isBag or ((item.outfitCategory or item.wearPart) and item:GetData("equip"))
end

local function fitsKind(group, item)
	if (group.key == "storage") then return true end
	if (group.wornPart) then return worn(item) and (item.wearPart or "body") == group.wornPart end
	if (group.key == "worn") then return worn(item) end
	if (worn(item)) then return false end
	if (group.key == "sling") then return item.isWeapon and pad.Size(item) == 2 end
	if (group.key == "belt") then return item.isWeapon or item.category == "Tools" end
	return true
end

local function group(key, name, limit, inventory, region)
	return {key = key, name = name, limit = limit, inv = inventory, region = region, items = {}, used = 0, kg = 0}
end

local function put(place, item)
	place.items[#place.items + 1] = item
	place.used = place.used + pad.Size(item)
	place.kg = place.kg + pad.Weight(item)
end

local function items(inv)
	local result = {}
	for _, item in pairs(inv:GetItems(true)) do result[#result + 1] = item end
	table.sort(result, function(a, b) return a.id < b.id end)
	return result
end

-- Root pockets share the character's existing Helix inventory. Bags retain their own inventory IDs.
-- The hand-carried group keeps old saves and changes of outfit lossless.
function pad.Layout(inv)
	local root = items(inv)
	local groups = {
		group("belt", "Utility belt", 2, inv, "waist"),
		group("sling", "Shoulder sling", 2, inv, "chest"),
		group("pockets", "Trouser pockets", 4, inv, "legs")
	}
	local wornLocations = {}
	for _, item in ipairs(root) do
		local part = item.wearPart
		if (part and item:GetData("equip") and (part == "head" or part == "feet" or part == "hands") and !wornLocations[part]) then
			local place = group("worn" .. part, "Worn / " .. part, nil, inv, part)
			place.wornPart = part
			wornLocations[part] = place
			groups[#groups + 1] = place
		end
		if ((item.outfitCategory or part == "outer" or part == "body") and item:GetData("equip")) then
			groups[#groups + 1] = group("coat" .. item.id, item:GetName() .. " pockets", 4, inv, "chest")
		end
	end
	groups[#groups + 1] = group("boot", "Boot lining", 1, inv, "feet")
	groups[#groups + 1] = group("worn", "Worn kit", nil, inv, "chest")
	for _, bag in ipairs(root) do
		local bagInv = bag.isBag and bag:GetInventory()
		if (bagInv) then
			local place = group("bag" .. bag.id, bag:GetName(), bagInv.w * bagInv.h, bagInv, "back")
			place.maxKg = bag.carryLimit or bagInv.w * bagInv.h * 2
			for _, item in ipairs(items(bagInv)) do put(place, item) end
			groups[#groups + 1] = place
		end
	end
	groups[#groups + 1] = group("hands", "Hand-carried", nil, inv, "hands")
	local byKey, loose = {}, {}
	for _, place in ipairs(groups) do byKey[place.key] = place end
	for _, item in ipairs(root) do
		local place = worn(item) and (wornLocations[item.wearPart] or byKey.worn) or byKey[item:GetData("carryPlace")]
		if (place and place.inv == inv and fitsKind(place, item)
			and (!place.limit or place.used + pad.Size(item) <= place.limit)) then
			put(place, item)
		else
			loose[#loose + 1] = item
		end
	end
	for _, item in ipairs(loose) do
		local place = pad.Destination(groups, item, nil, true)
		put(place or byKey.hands, item)
	end
	return groups
end

function pad.Locate(groups, id)
	for _, place in ipairs(groups) do
		for _, item in ipairs(place.items) do
			if (item.id == id) then return place, item end
		end
	end
end

-- On clients Helix replicates only the top-left cell of each item. Include its complete footprint.
local function hasSpace(inv, item)
	if (inv:GetID() == item.invID) then return true end
	if (SERVER) then return inv:FindEmptySlot(item.width, item.height, true) != nil end
	local cells = {}
	for x, col in pairs(inv.slots) do
		for y, other in pairs(col) do
			if (!istable(other)) then continue end
			for i = x, x + other.width - 1 do
				for j = y, y + other.height - 1 do cells[i + j * 128] = true end
			end
		end
	end
	for x = 1, inv.w - item.width + 1 do
		for y = 1, inv.h - item.height + 1 do
			local free = true
			for i = x, x + item.width - 1 do
				for j = y, y + item.height - 1 do
					if (cells[i + j * 128]) then free = false end
				end
			end
			if (free) then return true end
		end
	end
	return false
end

function pad.Fits(place, item, kg, reserved)
	return fitsKind(place, item) and (!place.limit or place.used + pad.Size(item) <= place.limit)
		and (!place.maxKg or place.kg + (kg or pad.Weight(item)) + (reserved or 0) <= place.maxKg)
		and hasSpace(place.inv, item)
end

function pad.Destination(groups, item, preference, onlyRoot, kg, reserved)
	local best, score
	for _, place in ipairs(groups) do
		if (onlyRoot and place.inv != groups[1].inv) then continue end
		if (!pad.Fits(place, item, kg, reserved and reserved[place])) then continue end
		local rank = 10
		if (place.key == "hands" or place.key == "boot") then rank = 0 end
		if (place.key == "pockets") then rank = 20 end
		if (place.maxKg and (item.stackLimit or item.category == "Food" or item.base == "base_books")) then rank = 30 end
		for _, other in ipairs(place.items) do
			if (other.category == item.category) then rank = math.max(rank, 40) end
		end
		if (place.key == "sling" or place.key == "belt") then rank = place.key == "sling" and 55 or 50 end
		if (place.key == preference) then rank = 60 end
		if (place.wornPart) then rank = 70 end
		if (!score or rank > score) then best, score = place, rank end
	end
	return best
end

function pad.Total(groups)
	local kg = 0
	for _, place in ipairs(groups) do kg = kg + place.kg end
	return kg
end

function pad.LoadBand(kg)
	if (kg >= 22) then return "Heavy", 3 end
	if (kg >= 12) then return "Loaded", 2 end
	return "Light", 1
end

-- A crate or a corpse has a single contents list, followed by any bags it actually contains.
function pad.StorageGroups(inv, name)
	local root = group("storage", name, nil, inv)
	local groups = {root}
	for _, item in ipairs(items(inv)) do
		put(root, item)
		local bag = item.isBag and item:GetInventory()
		if (bag) then
			local place = group("bag" .. item.id, item:GetName(), bag.w * bag.h, bag)
			place.maxKg = item.carryLimit or bag.w * bag.h * 2
			for _, inside in ipairs(items(bag)) do put(place, inside) end
			groups[#groups + 1] = place
		end
	end
	return groups
end

function pad.TransferWeight(item)
	local kg = pad.Weight(item)
	local bag = item.isBag and item:GetInventory()
	if (bag) then
		for _, inside in pairs(bag:GetItems(true)) do kg = kg + pad.Weight(inside) end
	end
	return kg
end

-- Plan the whole instance before touching it. The preview and server choose the same partial
-- stacks, and reserve their added weight before deciding where the remainder fits.
function pad.PlanTransfer(groups, item, preference, canMerge)
	local plan, reserved = {merges = {}}, {}
	local units = ix.stack.GetUnits(item)
	local remaining = units
	local weight = pad.Weight(item)
	if (item.stackLimit and units > 0) then
		for _, place in ipairs(groups) do
			for _, stack in ipairs(place.items) do
				if (!ix.stack.CanCombine(stack, item)) then continue end
				local amount = math.min(remaining, ix.stack.GetLimitUnits(stack) - ix.stack.GetUnits(stack))
				local addedKg = weight * amount / units
				local kg = place.kg + (reserved[place] or 0) + addedKg
				if ((place.maxKg and kg > place.maxKg) or (canMerge and !canMerge(place, stack))) then continue end
				plan.merges[#plan.merges + 1] = {place = place, stack = stack}
				reserved[place] = (reserved[place] or 0) + addedKg
				remaining = remaining - amount
				if (remaining == 0) then return plan end
			end
		end
	end
	local kg = units > 0 and weight * remaining / units or weight
	plan.place = pad.Destination(groups, item, preference, false, kg, reserved)
	if (plan.place) then return plan end
end
