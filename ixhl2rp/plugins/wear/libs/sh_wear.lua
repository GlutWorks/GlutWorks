
--- Wear: the condition of clothing, boots and armour.
-- An item takes part when its definition sets `wearPart`. Its condition is item data `condition` (0 to 100,
-- 100 when unset), capped by its ceiling, item data `conditionMax` (100 when unset), which every mend lowers.
-- What wears an item is in sv_hooks.lua; the server half of this API is in sv_wear.lua.
-- @module ix.wear

ix.wear = ix.wear or {}
ix.wear.modifiers = ix.wear.modifiers or {}
ix.wear.modifierOrder = ix.wear.modifierOrder or {}

ix.wear.PARTS = {body = true, outer = true, feet = true, hands = true, head = true}
ix.wear.PART_ORDER = {"head", "outer", "body", "hands", "feet"}

-- Levels from best to worst. An item is at the first level whose `min` its condition reaches; ruined is
-- exactly 0. `notice` is the phrase told to the wearer on entering the level by wearing out.
ix.wear.LEVELS = {
	{min = 90, phrase = "wearPristine"},
	{min = 65, phrase = "wearGood"},
	{min = 40, phrase = "wearWorn", notice = "wearNoticeWorn"},
	{min = 20, phrase = "wearTattered", notice = "wearNoticeTattered"},
	{min = 0, phrase = "wearFallingApart", notice = "wearNoticeFallingApart"},
	{phrase = "wearRuined", notice = "wearNoticeRuined"}
}
ix.wear.LEVEL_RUINED = #ix.wear.LEVELS

-- At or above this condition an item gives everything it has; below it, effectiveness falls off along
-- 1 - (1 - c / FULL)^2, slowly at first and steeply near ruin.
ix.wear.FULL_EFFECT_CONDITION = 60

-- Every mend lowers the ceiling by this much, not below CEILING_MIN and not below the condition the item had.
ix.wear.CEILING_LOSS = 5
ix.wear.CEILING_MIN = 50

-- Defaults for Helix outfits that replace the model (the uniforms) and set none of these themselves.
ix.wear.OUTFIT_DEFAULTS = {
	wearPart = "body",
	durability = 1.25,
	warmth = 4,
	waterproof = 0.1,
	repairMaterial = "fabric",
	repairQuantity = 0.5,
	repairAmount = 25,
	repairTool = "sewing_kit"
}

local function Definition(item)
	if (isstring(item)) then
		return ix.item.list[item]
	end

	return item
end

local function IsInstance(item)
	return istable(item) and item.id != nil and isfunction(item.GetData)
end

--- Whether the item instance, definition or uniqueID takes part in wear.
function ix.wear.IsWearable(item)
	item = Definition(item)

	return istable(item) and isstring(item.wearPart) and ix.wear.PARTS[item.wearPart] == true
end

--- The highest condition the item can be mended to (100 until it has been mended).
function ix.wear.GetCeiling(item)
	if (!IsInstance(item)) then
		return 100
	end

	return math.Clamp(tonumber(item:GetData("conditionMax", 100)) or 100, 0, 100)
end

--- The item's condition, 0 to 100. A definition is new (100).
function ix.wear.GetCondition(item)
	if (!IsInstance(item)) then
		return 100
	end

	return math.Clamp(tonumber(item:GetData("condition", 100)) or 100, 0, 100)
end

--- How much of its warmth, waterproofing and armour the item still gives, 0 to 1.
function ix.wear.GetEffectiveness(item)
	local condition = isnumber(item) and item or ix.wear.GetCondition(item)

	if (condition <= 0) then
		return 0
	end

	local full = ix.wear.FULL_EFFECT_CONDITION

	if (condition >= full) then
		return 1
	end

	local rest = 1 - condition / full

	return 1 - rest * rest
end

--- The level index (1 = pristine ... ix.wear.LEVEL_RUINED) and its language phrase for an item or a
-- condition value.
function ix.wear.GetLevel(item)
	local condition = isnumber(item) and item or ix.wear.GetCondition(item)

	if (condition > 0) then
		for index, level in ipairs(ix.wear.LEVELS) do
			if (level.min and condition >= level.min) then
				return index, level.phrase
			end
		end
	end

	return ix.wear.LEVEL_RUINED, ix.wear.LEVELS[ix.wear.LEVEL_RUINED].phrase
end

--- The equipped wearable items of the player's character, head to feet.
function ix.wear.GetWorn(client)
	local character = IsValid(client) and client:GetCharacter()
	local inventory = character and character:GetInventory()
	local result = {}

	if (!inventory) then
		return result
	end

	-- Iter yields an item once per cell it covers
	local seen = {}

	for item in inventory:Iter() do
		if (!seen[item.id] and item:GetData("equip") and ix.wear.IsWearable(item)) then
			seen[item.id] = true
			result[#result + 1] = item
		end
	end

	local order = {}

	for index, part in ipairs(ix.wear.PART_ORDER) do
		order[part] = index
	end

	table.sort(result, function(a, b)
		if (a.wearPart != b.wearPart) then
			return order[a.wearPart] < order[b.wearPart]
		end

		return a:GetID() < b:GetID()
	end)

	return result
end

--- The equipped item for one part, or nil.
function ix.wear.GetWornPart(client, part)
	for _, item in ipairs(ix.wear.GetWorn(client)) do
		if (item.wearPart == part) then
			return item
		end
	end
end

--- Registers a wear modifier: fn(client, item, cause, amount) returns the new amount. Modifiers run in the
-- order they were first registered, each on the previous one's result; registering an id again replaces
-- that modifier in place, and fn = nil removes it. A modifier that returns nil leaves the amount as it was.
function ix.wear.AddModifier(id, fn)
	if (ix.wear.modifiers[id] == nil and fn) then
		ix.wear.modifierOrder[#ix.wear.modifierOrder + 1] = id
	elseif (!fn) then
		table.RemoveByValue(ix.wear.modifierOrder, id)
	end

	ix.wear.modifiers[id] = fn
end

--- Runs the modifier chain over amount.
function ix.wear.ApplyModifiers(client, item, cause, amount)
	for _, id in ipairs(ix.wear.modifierOrder) do
		local fn = ix.wear.modifiers[id]

		if (fn) then
			local ok, result = pcall(fn, client, item, cause, amount)

			if (!ok) then
				ErrorNoHalt("[wear] modifier " .. tostring(id) .. ": " .. tostring(result) .. "\n")
			elseif (isnumber(result) and result == result) then
				amount = math.max(result, 0)
			end
		end
	end

	return amount
end

--- The material, quantity, amount and tool of a repair of this kind ("mend" for condition, "plate" for
-- armour points), or nil if the item has no such repair.
function ix.wear.GetRepairSpec(item, kind)
	item = Definition(item)

	if (!istable(item)) then
		return
	end

	if (kind == "plate") then
		if (!isstring(item.plateMaterial) or !isfunction(item.GetArmorCapacity)) then
			return
		end

		return {
			material = item.plateMaterial,
			quantity = item.plateQuantity or 1,
			amount = item.plateAmount or 25,
			tool = item.plateTool
		}
	end

	if (!ix.wear.IsWearable(item) or !isstring(item.repairMaterial)) then
		return
	end

	return {
		material = item.repairMaterial,
		quantity = item.repairQuantity or 1,
		amount = item.repairAmount or 25,
		tool = item.repairTool
	}
end

--- Whether the item is below what a repair of this kind can bring it back to.
function ix.wear.NeedsRepair(item, kind)
	if (kind == "plate") then
		return isfunction(item.GetArmor) and item:GetArmor() < item:GetArmorCapacity()
	end

	return ix.wear.GetCondition(item) < ix.wear.GetCeiling(item)
end

local function Has(inventory, uniqueID, quantity)
	if (!ix.item.list[uniqueID]) then
		return false
	end

	return ix.stack.ToUnits(uniqueID, ix.stack.Count(inventory, uniqueID)) >= ix.stack.ToUnits(uniqueID, quantity)
end

--- Whether client may repair the item this way now. Returns false, a language phrase and its arguments
-- when not.
-- The item must be in the character's own inventory (not in the world or a container), the material and
-- tool anywhere in that inventory or the bags inside it.
function ix.wear.CanRepair(client, item, kind)
	local character = IsValid(client) and client:GetCharacter()
	local inventory = character and character:GetInventory()
	local spec = istable(item) and ix.wear.GetRepairSpec(item, kind)

	if (!inventory or !spec or !IsInstance(item) or IsValid(item.entity)) then
		return false, "wearCannotRepair"
	end

	if (item.invID != inventory:GetID() or !inventory:GetItemByID(item:GetID())) then
		return false, "wearCannotRepair"
	end

	if (!client:Alive() or IsValid(client.ixRagdoll) or client:IsRestricted()) then
		return false, "wearCannotRepair"
	end

	if (!ix.wear.NeedsRepair(item, kind)) then
		return false, "wearNoRepairNeeded"
	end

	if (spec.tool and !Has(inventory, spec.tool, 1)) then
		local tool = ix.item.list[spec.tool]

		return false, "wearNeedTool", string.lower(tool and tool.name or spec.tool)
	end

	if (!Has(inventory, spec.material, spec.quantity)) then
		local material = ix.item.list[spec.material]

		return false, "wearNeedMaterial", material and ix.stack.Format(material, spec.quantity) or tostring(spec.quantity),
			string.lower(material and material.name or spec.material)
	end

	return true
end

local function RepairFunction(kind, phrase, icon)
	return {
		name = phrase,
		tip = phrase .. "Tip",
		icon = icon,
		OnRun = function(item)
			if (SERVER) then
				ix.wear.StartRepair(item.player, item, kind)
			end

			return false
		end,
		OnCanRun = function(item)
			-- shown while the item needs it and is carried; missing material is told when tried
			return !IsValid(item.entity) and IsValid(item.player) and ix.wear.GetRepairSpec(item, kind) != nil and
				ix.wear.NeedsRepair(item, kind)
		end
	}
end

--- Gives one definition the wear defaults (outfits) and the repair actions.
function ix.wear.Apply(item)
	if (item.wearPart == nil and item.outfitCategory == "model" and isfunction(item.AddOutfit)) then
		for key, value in pairs(ix.wear.OUTFIT_DEFAULTS) do
			if (item[key] == nil) then
				item[key] = value
			end
		end
	end

	if (!ix.wear.IsWearable(item)) then
		return
	end

	item.functions = item.functions or {}

	if (item.repairMaterial) then
		item.functions.wearMend = RepairFunction("mend", "wearMend", "icon16/cut.png")
	end

	if (item.plateMaterial and isfunction(item.GetArmorCapacity)) then
		item.functions.wearPlate = RepairFunction("plate", "wearPlate", "icon16/shield.png")
	end
end

function ix.wear.ApplyToAll()
	for _, item in pairs(ix.item.list) do
		ix.wear.Apply(item)
	end
end
