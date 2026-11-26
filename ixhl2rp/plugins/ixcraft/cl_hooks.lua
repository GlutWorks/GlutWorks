
local PLUGIN = PLUGIN

PLUGIN.spawners = {}

function PLUGIN:BuildCraftingMenu()
	if (table.IsEmpty(self.craft.GetCategories(LocalPlayer()))) then
		return false
	end
end

function PLUGIN:PopulateRecipeTooltip(tooltip, recipe)
	local canCraft, failString, c, d, e, f = recipe:OnCanCraft(LocalPlayer())

	local name = tooltip:AddRow("name")
	name:SetImportant()
	name:SetText(recipe.category..": "..(recipe.GetName and recipe:GetName() or L(recipe.name)))
	name:SetMaxWidth(math.max(name:GetMaxWidth(), ScrW() * 0.5))
	name:SizeToContents()

	if (!canCraft and isstring(failString)) then
		if (failString:sub(1, 1) == "@") then
			failString = L(failString:sub(2), c, d, e, f)
		end

		local errorRow = tooltip:AddRow("errorRow")
		errorRow:SetText(L(failString))
		errorRow:SetBackgroundColor(Color(255,24,0))
		errorRow:SizeToContents()
	end

	local description = tooltip:AddRow("description")
	description:SetText(recipe.GetDescription and recipe:GetDescription() or L(recipe.description))
	description:SizeToContents()

	local function AddList(id, title, color, entries)
		if (#entries == 0) then
			return
		end

		local header = tooltip:AddRow(id)
		header:SetText(L(title))
		header:SetBackgroundColor(color)
		header:SizeToContents()

		local list = tooltip:AddRow(id .. "List")
		list:SetText("- " .. table.concat(entries, ", "))
		list:SizeToContents()
	end

	local function Describe(uniqueID, amount)
		local itemTable = ix.item.list[uniqueID]
		local name = itemTable and itemTable.name or uniqueID

		if (itemTable and itemTable.stackUnit) then
			local quantity = isnumber(amount) and ix.stack.Format(itemTable, amount) or (amount .. " " .. itemTable.stackUnit)

			return quantity .. " " .. name
		end

		return amount .. "x " .. name
	end

	local tools = {}

	for _, uniqueID in ipairs(recipe.tools or {}) do
		local itemTable = ix.item.list[uniqueID]

		tools[#tools + 1] = itemTable and itemTable.name or uniqueID
	end

	AddList("tools", "CraftTools", Color(150, 150, 25), tools)

	local requirements = {}

	for uniqueID, amount in SortedPairs(recipe.requirements or {}) do
		requirements[#requirements + 1] = Describe(uniqueID, amount)
	end

	AddList("requirements", "CraftRequirements", Color(25, 150, 150), requirements)

	local options = {}

	for uniqueID, amount in SortedPairs(recipe.interchangeable_req or {}) do
		options[#options + 1] = Describe(uniqueID, amount)
	end

	AddList("interchangeable", "CraftInterchangeable", Color(25, 150, 25), options)

	local results = {}

	for uniqueID, amount in SortedPairs(recipe.results or {}) do
		if (istable(amount)) then
			amount = (amount["min"] or amount[1]) .. "-" .. (amount["max"] or amount[#amount])
		end

		results[#results + 1] = Describe(uniqueID, amount)
	end

	AddList("result", "CraftResults", derma.GetColor("Warning", tooltip), results)

	if (recipe.PopulateTooltip) then
		recipe:PopulateTooltip(tooltip)
	end
end

function PLUGIN:PopulateStationTooltip(tooltip, station)
	local name = tooltip:AddRow("name")
	name:SetImportant()
	name:SetText(station.GetName and station:GetName() or L(station.name))
	name:SetMaxWidth(math.max(name:GetMaxWidth(), ScrW() * 0.5))
	name:SizeToContents()

	local description = tooltip:AddRow("description")
	description:SetText(station.GetDescription and station:GetDescription() or L(station.description))
	description:SizeToContents()

	if (station.PopulateTooltip) then
		station:PopulateTooltip(tooltip)
	end
end