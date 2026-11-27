
-- Client half of ix.smelting: the smelter's tooltip and its entries in the entity (use key) menu.

-- Library files load alphabetically, so this one runs before sh_smelting.lua.
ix.smelting = ix.smelting or {}

local function AddRow(tooltip, id, text, color)
	local row = tooltip:AddRow(id)
	row:SetText(text)

	if (color) then
		row:SetBackgroundColor(color)
	end

	row:SizeToContents()
end

function ix.smelting.PopulateTooltip(entity, tooltip)
	local queue, output = ix.smelting.Decode(entity:GetSmeltContents())
	local remaining = entity:GetSmeltEnd() - CurTime()

	AddRow(tooltip, "smeltFuel", string.format("Fuel: %.1f operations", entity:GetSmeltFuel() / ix.smelting.FUEL_PER_OPERATION))

	if (entity:GetSmeltEnd() > 0) then
		AddRow(tooltip, "smeltStatus", string.format("Smelting (%d s)", math.max(math.ceil(remaining), 0)),
			derma.GetColor("Success", tooltip))
	else
		AddRow(tooltip, "smeltStatus", "Idle")
	end

	for index, entry in ipairs(queue) do
		local input = ix.smelting.inputs[entry[1]]
		local amount = input and ix.smelting.ToTenths(input.amount) * entry[2] or 0

		AddRow(tooltip, "smeltQueue" .. index, "Queued: " .. ix.smelting.GetItemName(entry[1]) .. " " ..
			ix.smelting.FormatQuantity(entry[1], amount))
	end

	for uniqueID, tenths in SortedPairs(output) do
		AddRow(tooltip, "smeltOutput" .. uniqueID, "Ready: " .. ix.smelting.GetItemName(uniqueID) .. " " ..
			ix.smelting.FormatQuantity(uniqueID, tenths), derma.GetColor("Warning", tooltip))
	end
end

-- One entry per fuel and smeltable item the player carries, plus collecting the output.
-- The server re-checks every choice.
function ix.smelting.AddMenuOptions(entity, client, options)
	local character = client:GetCharacter()
	local inventory = character and character:GetInventory()

	if (!inventory or !ix.stack) then
		return
	end

	for uniqueID in SortedPairs(ix.smelting.fuels) do
		local count = ix.stack.Count(inventory, uniqueID)

		if (count > 0) then
			options["Add fuel: " .. ix.smelting.GetItemName(uniqueID) .. " (" ..
				ix.smelting.FormatQuantity(uniqueID, ix.smelting.ToTenths(count)) .. ")"] = function()
				return {action = "fuel", uniqueID = uniqueID}
			end
		end
	end

	for uniqueID in SortedPairs(ix.smelting.inputs) do
		local count = ix.stack.Count(inventory, uniqueID)

		if (count > 0) then
			options["Smelt: " .. ix.smelting.GetItemName(uniqueID) .. " (" ..
				ix.smelting.FormatQuantity(uniqueID, ix.smelting.ToTenths(count)) .. ")"] = function()
				return {action = "smelt", uniqueID = uniqueID}
			end
		end
	end

	local _, output = ix.smelting.Decode(entity:GetSmeltContents())

	if (next(output)) then
		options["Collect output"] = function()
			return {action = "collect"}
		end
	end
end
