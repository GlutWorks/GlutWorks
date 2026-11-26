
-- STAND-IN FOR THE STACKING WORKSTREAM: DELETE THIS FILE WHEN ixhl2rp/plugins/stacking IS MERGED.
-- A minimal ix.stack following the contract in the shared brief, so the station, smelter, mining and
-- scavenging code can run before the real plugin exists. It is only installed when nothing else has
-- defined ix.stack once every plugin has loaded, so the real implementation always wins.

local function Round(quantity)
	return math.Round(quantity, 1)
end

hook.Add("InitializedPlugins", "glutcraftStackStandIn", function()
	if (ix.stack) then
		return
	end

	local stack = {}

	function stack.IsStackable(itemTable)
		return itemTable != nil and itemTable.stackLimit != nil
	end

	function stack.GetQuantity(item)
		if (!stack.IsStackable(item)) then
			return 1
		end

		return item:GetData("quantity", 1)
	end

	function stack.FromEntity(entity)
		if (!IsValid(entity) or entity:GetClass() != "ix_item") then
			return
		end

		local item = ix.item.instances[entity.ixItemID]

		if (item) then
			return item, stack.GetQuantity(item)
		end
	end

	function stack.Count(inventory, uniqueID)
		local total = 0

		for _, item in ipairs(inventory:GetItemsByUniqueID(uniqueID)) do
			total = total + stack.GetQuantity(item)
		end

		return Round(total)
	end

	if (SERVER) then
		function stack.SetQuantity(item, quantity)
			quantity = Round(quantity)

			if (quantity <= 0) then
				item:Remove()
			else
				item:SetData("quantity", quantity)
			end
		end

		function stack.Give(inventory, uniqueID, quantity)
			local itemTable = ix.item.list[uniqueID]

			if (!itemTable) then
				return false, quantity
			end

			if (!stack.IsStackable(itemTable)) then
				local count = math.Round(quantity)

				for i = 1, count do
					if (!inventory:Add(uniqueID)) then
						return false, count - i + 1
					end
				end

				return true
			end

			local limit = itemTable.stackLimit
			local left = Round(quantity)

			for _, item in ipairs(inventory:GetItemsByUniqueID(uniqueID)) do
				if (left <= 0) then
					break
				end

				local have = stack.GetQuantity(item)
				local add = math.min(left, Round(limit - have))

				if (add > 0) then
					stack.SetQuantity(item, have + add)
					left = Round(left - add)
				end
			end

			while (left > 0) do
				local amount = math.min(left, limit)

				if (!inventory:Add(uniqueID, 1, {quantity = amount})) then
					return false, left
				end

				left = Round(left - amount)
			end

			return true
		end

		function stack.Take(inventory, uniqueID, quantity)
			quantity = Round(quantity)

			if (quantity <= 0 or stack.Count(inventory, uniqueID) < quantity) then
				return false
			end

			local left = quantity

			for _, item in ipairs(inventory:GetItemsByUniqueID(uniqueID)) do
				if (left <= 0) then
					break
				end

				local have = stack.GetQuantity(item)
				local take = math.min(have, left)

				stack.SetQuantity(item, have - take)
				left = Round(left - take)
			end

			return true
		end

		function stack.Spawn(uniqueID, position, quantity, angles)
			local itemTable = ix.item.list[uniqueID]

			if (!itemTable) then
				return
			end

			if (!stack.IsStackable(itemTable)) then
				for _ = 1, math.Round(quantity) do
					ix.item.Spawn(uniqueID, position, nil, angles)
				end

				return
			end

			local left = Round(quantity)

			while (left > 0) do
				local amount = math.min(left, itemTable.stackLimit)

				ix.item.Spawn(uniqueID, position, nil, angles, {quantity = amount})
				left = Round(left - amount)
			end
		end
	end

	ix.stack = stack
end)
