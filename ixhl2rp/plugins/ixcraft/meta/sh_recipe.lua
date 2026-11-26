
local PLUGIN = PLUGIN
PLUGIN.meta = PLUGIN.meta or {}

local RECIPE = PLUGIN.meta.recipe or {}
RECIPE.__index = RECIPE
RECIPE.name = "undefined"
RECIPE.description = "undefined"
RECIPE.uniqueID = "undefined"
RECIPE.category = "Crafting"
RECIPE.stationRange = 100

function RECIPE:GetName()
	return self.name
end

function RECIPE:GetDescription()
	return self.description
end

function RECIPE:GetSkin()
	return self.skin
end

function RECIPE:GetModel()
	return self.model
end

function RECIPE:PreHook(name, func)
	if (!self.preHooks) then
		self.preHooks = {}
	end

	self.preHooks[name] = func
end

function RECIPE:PostHook(name, func)
	if (!self.postHooks) then
		self.postHooks = {}
	end

	self.postHooks[name] = func
end

local function ItemName(uniqueID)
	local itemTable = ix.item.list[uniqueID]

	return itemTable and itemTable.name or uniqueID
end

local function HasAmount(inventory, uniqueID, amount)
	return ix.stack.ToUnits(uniqueID, ix.stack.Count(inventory, uniqueID)) >= ix.stack.ToUnits(uniqueID, amount)
end

--- Works out what crafting this recipe would consume from the inventory: every requirement plus the first
-- interchangeable requirement (in uniqueID order) the inventory can cover.
-- @treturn[1] table uniqueID -> amount to consume
-- @treturn[2] nil
-- @treturn[2] string language phrase for the failure
-- @return[2] argument for that phrase
function RECIPE:GetConsumption(inventory)
	local consume = {}
	local missing = {}

	for uniqueID, amount in SortedPairs(self.requirements or {}) do
		consume[uniqueID] = amount

		if (!HasAmount(inventory, uniqueID, amount)) then
			missing[#missing + 1] = ItemName(uniqueID)
		end
	end

	if (#missing > 0) then
		return nil, "@CraftMissingItem", table.concat(missing, ", ")
	end

	if (next(self.interchangeable_req or {})) then
		local options = {}
		local chosen

		for uniqueID, amount in SortedPairs(self.interchangeable_req) do
			options[#options + 1] = ItemName(uniqueID)

			if (!chosen and HasAmount(inventory, uniqueID, (consume[uniqueID] or 0) + amount)) then
				chosen = uniqueID
			end
		end

		if (!chosen) then
			return nil, "@CraftMissingItem", table.concat(options, ", or ")
		end

		consume[chosen] = (consume[chosen] or 0) + self.interchangeable_req[chosen]
	end

	-- Tools are not consumed, so one must be left over after the requirements are taken.
	for _, uniqueID in ipairs(self.tools or {}) do
		if (!HasAmount(inventory, uniqueID, (consume[uniqueID] or 0) + 1)) then
			return nil, "@CraftMissingTool", ItemName(uniqueID)
		end
	end

	return consume
end

--- Whether the player is close enough to an entity of the recipe's station, if it names one.
function RECIPE:IsNearStation(client)
	if (!self.station) then
		return true
	end

	local range = self.stationRange * self.stationRange
	local position = client:GetPos()

	for _, entity in ipairs(ents.FindByClass("ix_station_" .. self.station)) do
		if (position:DistToSqr(entity:GetPos()) < range) then
			return true
		end
	end

	return false
end

function RECIPE:OnCanSee(client)
	local character = client:GetCharacter()

	if (!character) then
		return false
	end

	if (self.preHooks and self.preHooks["OnCanSee"]) then
		local a, b, c, d, e, f = self.preHooks["OnCanSee"](self, client)

		if (a != nil) then
			return a, b, c, d, e, f
		end
	end

	if (self.flag and !character:HasFlags(self.flag)) then
		return false
	end

	if (self.postHooks and self.postHooks["OnCanSee"]) then
		local a, b, c, d, e, f = self.postHooks["OnCanSee"](self, client)

		if (a != nil) then
			return a, b, c, d, e, f
		end
	end

	return true
end

function RECIPE:OnCanCraft(client)
	local character = client:GetCharacter()

	if (!character) then
		return false
	end

	if (self.preHooks and self.preHooks["OnCanCraft"]) then
		local a, b, c, d, e, f = self.preHooks["OnCanCraft"](self, client)

		if (a != nil) then
			return a, b, c, d, e, f
		end
	end

	if (self.flag and !character:HasFlags(self.flag)) then
		return false, "@CraftMissingFlag", self.flag
	end

	local consume, failString, argument = self:GetConsumption(character:GetInventory())

	if (!consume) then
		return false, failString, argument
	end

	if (!self:IsNearStation(client)) then
		local station = PLUGIN.craft.stations[self.station]

		return false, "@CraftMissingStation", station and station.name or self.station
	end

	if (self.postHooks and self.postHooks["OnCanCraft"]) then
		local a, b, c, d, e, f = self.postHooks["OnCanCraft"](self, client)

		if (a != nil) then
			return a, b, c, d, e, f
		end
	end

	return true
end

if (SERVER) then
	-- Picks the amount for a result entry: a number, a list to choose from, or {min = a, max = b}.
	local function RollAmount(amount)
		if (istable(amount)) then
			if (amount["min"] and amount["max"]) then
				return math.random(amount["min"], amount["max"])
			end

			return amount[math.random(1, #amount)]
		end

		return amount
	end

	function RECIPE:OnCraft(client)
		local bCanCraft, failString, c, d, e, f = self:OnCanCraft(client)

		if (bCanCraft == false) then
			return false, failString, c, d, e, f
		end

		if (self.preHooks and self.preHooks["OnCraft"]) then
			local a, b, c2, d2, e2, f2 = self.preHooks["OnCraft"](self, client)

			if (a != nil) then
				return a, b, c2, d2, e2, f2
			end
		end

		local inventory = client:GetCharacter():GetInventory()
		local consume, reason, argument = self:GetConsumption(inventory)

		if (!consume) then
			return false, reason, argument
		end

		-- Each Take is all or nothing; if one still fails, give back what was already taken.
		local taken = {}

		for uniqueID, amount in SortedPairs(consume) do
			if (!ix.stack.Take(inventory, uniqueID, amount)) then
				for takenID, takenAmount in pairs(taken) do
					ix.stack.GiveOrDrop(client, takenID, takenAmount)
				end

				return false, "@CraftMissingItem", ItemName(uniqueID)
			end

			taken[uniqueID] = amount
		end

		for uniqueID, amount in SortedPairs(self.results or {}) do
			ix.stack.GiveOrDrop(client, uniqueID, RollAmount(amount))
		end

		if (self.postHooks and self.postHooks["OnCraft"]) then
			local a, b, c2, d2, e2, f2 = self.postHooks["OnCraft"](self, client)

			if (a != nil) then
				return a, b, c2, d2, e2, f2
			end
		end

		return true, "@CraftSuccess", self.GetName and self:GetName() or self.name
	end
end

PLUGIN.meta.recipe = RECIPE
