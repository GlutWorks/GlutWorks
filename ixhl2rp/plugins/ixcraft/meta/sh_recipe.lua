
local PLUGIN = PLUGIN
PLUGIN.meta = PLUGIN.meta or {}

local RECIPE = PLUGIN.meta.recipe or {}
RECIPE.__index = RECIPE
RECIPE.name = "undefined"
RECIPE.description = "undefined"
RECIPE.uniqueID = "undefined"
RECIPE.category = "Crafting"

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

	local inventory = character:GetInventory()
	local bHasItems, bHasTools, bHasInterchangeable = true, true, true
	local missing = ""

	if (self.flag and !character:HasFlags(self.flag)) then
		return false, "@CraftMissingFlag", self.flag
	end

	for uniqueID, reqAmt in pairs(self.requirements or {}) do
		for _, item in pairs(inventory:GetItems()) do
			local amt = item:GetData('quantity', 1) or 1
			if (item.uniqueID == uniqueID) then 
				if (amt >= reqAmt) then 
					goto bypass1
				else 
					reqAmt = reqAmt - amt
				end
			end
		end
		local itemTable = ix.item.Get(uniqueID)
		bHasItems = false
		missing = missing..(itemTable and itemTable.name or uniqueID)..", "
		::bypass1::
	end
	if (missing != "") then 
		missing = missing:sub(1, -3)
		return false, "@CraftMissingItem", missing
	end

	if(next(self.interchangeable_req)) then
		missing = ""
		for uniqueID, reqAmt in pairs(self.interchangeable_req or {}) do
			for _, item in pairs(inventory:GetItems()) do
				if (item.uniqueID == uniqueID) then
					local amt = item:GetData(quantity) or 1
					if (amt >= reqAmt) then 
						goto bypass2
					else 
						reqAmt = reqAmt - amt
					end
				end
			end
		end
		for uniqueID, amount in pairs(self.interchangeable_req or {}) do
			missing = missing..(ix.item.Get(uniqueID).name)..", or "
		end
		missing = missing:sub(1, -6) 
		return false, "@CraftMissingItem", missing
	end
	::bypass2::

	for _, uniqueID in pairs(self.tools or {}) do
		if (!inventory:HasItem(uniqueID)) then
			local itemTable = ix.item.Get(uniqueID)
			bHasTools = false

			missing = itemTable and itemTable.name or uniqueID
			break
		end
	end

	if (bHasTools == false) then
		return false, "@CraftMissingTool", missing
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
	function RECIPE:OnCraft(client)
		local bCanCraft, failString, c, d, e, f = self:OnCanCraft(client)

		if (bCanCraft == false) then
			return false, failString, c, d, e, f
		end

		if (self.preHooks and self.preHooks["OnCraft"]) then
			local a, b, c, d, e, f = self.preHooks["OnCraft"](self, client)

			if (a != nil) then
				return a, b, c, d, e, f
			end
		end

		local character = client:GetCharacter()
		local inventory = character:GetInventory()

		if (self.requirements) then
			local intReqUnfufilled = true
			for uniqueID, reqAmt in pairs(self.requirements) do
				local warning = false
				local stop = true
				for _, item in pairs(inventory:GetItems()) do
					if (item.uniqueID == uniqueID) then
						local amt = item:GetData('quantity', 1) or  1
						if (amt == reqAmt) then
							item:Remove()
							stop = false
							break
						elseif (amt > reqAmt) then
							item:SetData('quantity', amt - reqAmt)
							stop = false
							break
						else
							item:Remove()
							reqAmt = reqAmt - amt
							warning = true
						end
					end
					if (self.interchangeable_req[item.uniqueID] && intReqFufilled) then
						if (item.uniqueID == uniqueID) then
							local amt = item:GetData('quantity', 1) or 1
							if (amt == reqAmt) then
								item:Remove()
								intReqUnfufilled = false
							elseif (amt > reqAmt) then
								item:SetData('quantity', amt - reqAmt)
								intReqUnfufilled = false
							end
						end
					end
				end
				if (warning) then
					print("AN ITEM WAS DELETED INCORRECTLY IN sh_recipe.lua[217]. CHECK CLIENT SIDE CRAFTING CHECKER")
				end
				if (stop) then return false end
			end
		end

		if (next(self.interchangeable_req)) then
			for uniqueID, reqAmt in pairs(self.interchangeable_req) do
				local warning = false
				if (stop) then break end
				for _, item in pairs(inventory:GetItems()) do
					if (item.uniqueID == uniqueID) then
						local amt = item:GetData('quantity', 1) or 1
						if (amt == reqAmt) then
							item:Remove()
							goto theEnd
						elseif (amt > reqAmt) then
							item:SetData('quantity', amt - reqAmt)
							goto theEnd
						else
							item:Remove()
							reqAmt = reqAmt - amt
							warning = true
						end
					end
				end
				if (warning) then
					print("AN ITEM WAS DELETED INCORRECTLY IN sh_recipe.lua[217]. CHECK CLIENT SIDE CRAFTING CHECKER")
				end
			end
			return false
		end
		::theEnd::

		for uniqueID, amount in pairs(self.results or {}) do
			if (istable(amount)) then
				if (amount["min"] and amount["max"]) then
					amount = math.random(amount["min"], amount["max"])
				else
					amount = amount[math.random(1, #amount)]
				end
			end

			if (!inventory:Add(uniqueID, amount)) then
				ix.item.Spawn(uniqueID, client, quantity)
			end
		end

		if (self.postHooks and self.postHooks["OnCraft"]) then
			local a, b, c, d, e, f = self.postHooks["OnCraft"](self, client)

			if (a != nil) then
				return a, b, c, d, e, f
			end
		end

		return true, "@CraftSuccess", self.GetName and self:GetName() or self.name
	end
end

PLUGIN.meta.recipe = RECIPE
