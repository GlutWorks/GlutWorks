
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
	local bHasItems, bHasTools
	local missing = ""
	local bypass = false

	if (self.flag and !character:HasFlags(self.flag)) then
		return false, "@CraftMissingFlag", self.flag
	end

	for uniqueID, amount in pairs(self.requirements or {}) do
		local amt = 0
		for _, item in pairs(inventory:GetItems()) do
			if (item.uniqueID == uniqueID) then 
				amt = amt + item:GetData('quantity', 1)
			end
		end
		if (amt < amount) then
			local itemTable = ix.item.Get(uniqueID)
			bHasItems = false

			missing = missing..(itemTable and itemTable.name or uniqueID)..", "
		end
	end

	for uniqueID, amount in pairs(self.interchangeable_req or {}) do
		local amt = 0
		for _, item in pairs(inventory:GetItems()) do
			if (item.uniqueID == uniqueID) then 
				print ("1")
				print (uniqueID)
				print (item.uniqueID)
				amt = amt + item:GetData('quantity', 1)
			end
		end
		if (amt >= amount) then
			print ("2")
			bypass = true
		end
	end

	if (!bypass) then

		bHasItems = false
		for uniqueID, amount in pairs(self.interchangeable_req or {}) do
			missing = missing..(ix.item.Get(uniqueID).name)..", or "
		end
	end

	if (missing != "") then
		missing = missing:sub(1, -3)
	end

	if (bHasItems == false) then
		return false, "@CraftMissingItem", missing
	end

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
			local removedItems = {}
			local choseReqDone = false
			for _, itemTable in pairs(inventory:GetItems()) do
				local uniqueID = itemTable.uniqueID

				if (self.requirements[uniqueID]) then
					local amountRemoved = removedItems[uniqueID] or 0
					local amt = itemTable:GetData('quantity', 1)
					local amount = self.requirements[uniqueID]
					if (amount > amt) then
						--Gets all required items to craft
						local items = {}
						local i=0
						local amt=0
						for _, item in pairs(inventory:GetItems()) do
							if (self.requirements[item.uniqueID]) then
								items[i] = item 
								amt = amt + item:GetData('quantity', 1)
								if (amt >= amount) then 
									break
								end
							end
						end
						print (" - found " .. i .. " " .. itemTable.name)
						--Delets those items. Fix this by waiting until last item to do the checks
						if (amt < amount) then 
							return false 
						end

						for _, item in pairs(items) do
							amount = amount - item:GetData('quantity', 1)
							if amount >= 0 then 
								item:Remove()
								if amount == 0 then goto theEnd end
							else 
								item:SetData('quantity', 0 - amount)
								goto theEnd
							end
						end
					elseif (amount < amt) then
						itemTable:SetData('quantity', amt - amount)
						removedItems[uniqueID] = amountRemoved + amount
						goto theEnd
					else
						removedItems[uniqueID] = amountRemoved + 1
						itemTable:Remove()
						goto theEnd
					end


				elseif (self.interchangeable_req[uniqueID] && !choseReqDone) then
					local amountRemoved = removedItems[uniqueID] or 0
					local amt = itemTable:GetData('quantity', 1)
					local amount = self.interchangeable_req[uniqueID]
					if (amount > amt) then
						--Gets all required items to craft
						local items = {}
						local i=0
						local amt=0
						for _, item in pairs(inventory:GetItems()) do
							if (self.interchangeable_req[item.uniqueID]) then
								items[i] = item 
								amt = amt + item:GetData('quantity', 1)
								if (amt >= amount) then 
									break
								end
							end
						end

						if (amt < amount) then goto loopEnd end
						
						for _, item in pairs(items) do
							amount = amount - item:GetData('quantity', 1)
							if amount >= 0 then 
								item:Remove()
								if amount == 0 then 
								choseReqDone = true
								goto loopEnd end
							else 
								item:SetData('quantity', 0 - amount)
								choseReqDone = true
								goto loopEnd
							end
						end
					elseif (amount < amt) then
						itemTable:SetData('quantity', amt - amount)
						removedItems[uniqueID] = amountRemoved + amount
						choseReqDone = true
						goto loopEnd
					else
						removedItems[uniqueID] = amountRemoved + 1
						itemTable:Remove()
						choseReqDone = true
						goto loopEnd
					end
				end
				::loopEnd::
			end
			print (!self.interchangeable_req)
			if (!choseReqDone && self.interchangeable_req) then
				return false, "@CraftMissingItem", "A choosable item"
			end
			::theEnd::
			print ("Finished")
		end

		for uniqueID, amount in pairs(self.results or {}) do
			if (istable(amount)) then
				if (amount["min"] and amount["max"]) then
					amount = math.random(amount["min"], amount["max"])
				else
					amount = amount[math.random(1, #amount)]
				end
			end

			for i = 1, amount do
				if (!inventory:Add(uniqueID)) then
						ix.item.Spawn(uniqueID, client)
				end
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
