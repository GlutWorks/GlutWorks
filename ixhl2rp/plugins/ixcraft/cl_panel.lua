
-- Crafting in the world: the panel beside a bench listing what can be made there, and "Break down" (or "Make
-- ...") among the held-Use options of a loose world item that a recipe needing no station uses. Both send the
-- server's own requests (ixCraftRecipe, ixCraftFromItem); the server checks everything again.

local PLUGIN = PLUGIN

-- Seconds between two rebuilds of an open station panel (the inventory, the player's state and the distance to
-- the station can all change what can be made).
PLUGIN.panelRefresh = 0.5
PLUGIN.panelRows = 8

local COLOR_LINE = Color(175, 170, 152)

-- A private line in the chat, styled as Examine's.
local function Say(text)
	local class = ix.chat.classes.examine

	chat.AddText(class and class.color or COLOR_LINE, text)
end

PLUGIN.Say = Say

local function Sound(kind)
	local interaction = ix.plugin.list.interaction

	if (interaction and interaction.PlayActionSound) then
		interaction:PlayActionSound(kind)
	else
		surface.PlaySound(kind == "cancel" and "buttons/button10.wav" or "buttons/button14.wav")
	end
end

--- The world panel rows for a station: PLUGIN.craft.GetStationList as headings and recipe rows. A recipe that
-- cannot be made yet is greyed (`dim`) but can still be chosen, to learn what it needs.
function PLUGIN:BuildStationRows(entity)
	local rows = {}

	for _, entry in ipairs(self.craft.GetStationList(LocalPlayer(), entity:GetStationID())) do
		if (entry.heading) then
			rows[#rows + 1] = {label = entry.heading, heading = true}
		else
			rows[#rows + 1] = {
				label = L(self.craft.GetRecipeName(entry.recipe)),
				detail = L(entry.bCanCraft and "craftReady" or "craftNotYet"),
				dim = !entry.bCanCraft,
				uniqueID = entry.uniqueID,
				bCanCraft = entry.bCanCraft
			}
		end
	end

	if (#rows == 0) then
		rows[1] = {label = L("craftNothing"), enabled = false}
	end

	return rows
end

local function Signature(rows)
	local parts = {}

	for i, row in ipairs(rows) do
		parts[i] = tostring(row.label) .. "|" .. tostring(row.detail) .. "|" .. tostring(row.dim)
	end

	return table.concat(parts, "\n")
end

--- Chooses a recipe row: crafts one that can be made, and says what a greyed one needs.
function PLUGIN:ChooseRecipe(row)
	local recipe = self.craft.recipes[row.uniqueID]

	if (!recipe) then
		return
	end

	if (!row.bCanCraft) then
		Sound("cancel")
		Say(self.craft.DescribeNeeds(LocalPlayer(), recipe))
		return
	end

	if ((self.nextCraftRequest or 0) > RealTime()) then
		return
	end

	self.nextCraftRequest = RealTime() + 0.3

	net.Start("ixCraftRecipe")
		net.WriteString(row.uniqueID)
	net.SendToServer()
end

--- Opens the panel of what can be made at a station, beside it. It stays open while the player chooses, and
-- follows the inventory.
function PLUGIN:OpenStationPanel(entity)
	if (!IsValid(entity) or !ix.worldui) then
		return
	end

	local station = entity:GetStationTable()
	local rows = self:BuildStationRows(entity)
	local panel = ix.worldui.Open({
		anchor = entity,
		title = station and L(station.name) or nil,
		rows = rows,
		bKeepOpen = true,
		maxRows = self.panelRows,
		reach = math.min(self.craft.panelReach, self.meta.recipe.stationRange),
		OnSelect = function(_, row)
			self:ChooseRecipe(row)
		end
	})

	panel.craftEntity = entity
	panel.craftSignature = Signature(rows)
	panel.craftRefresh = RealTime() + self.panelRefresh

	self.stationPanel = panel

	return panel
end

--- The open station panel, if any.
function PLUGIN:GetStationPanel()
	local panel = self.stationPanel

	if (panel and panel:IsOpen()) then
		return panel
	end
end

function PLUGIN:RefreshStationPanel(bNow)
	local panel = self:GetStationPanel()

	if (!panel or (!bNow and RealTime() < panel.craftRefresh) or !IsValid(panel.craftEntity)) then
		return
	end

	panel.craftRefresh = RealTime() + self.panelRefresh

	local rows = self:BuildStationRows(panel.craftEntity)
	local signature = Signature(rows)

	if (signature != panel.craftSignature) then
		panel.craftSignature = signature
		panel:SetRows(rows)
	end
end

function PLUGIN:Think()
	if (self.stationPanel) then
		self:RefreshStationPanel()
	end
end

-- "Break down" (a Breakdown recipe) or "Make <recipe>" for a loose item that a recipe needing no station uses.
function PLUGIN:PopulateInteractionOptions(entity, client, options)
	if (entity:GetClass() != "ix_item" or !entity.GetItemTable) then
		return
	end

	local itemTable = entity:GetItemTable()

	if (!itemTable) then
		return
	end

	local recipes = self.craft.GetRecipesUsing(client, itemTable.uniqueID)

	for _, entry in ipairs(recipes) do
		local label = entry.recipe.category == "Breakdown" and L("craftBreakDown") or L("craftMake", L(entry.name))

		if (#recipes > 1 and entry.recipe.category == "Breakdown") then
			label = label .. ": " .. L(entry.name)
		end

		options[label] = function()
			net.Start("ixCraftFromItem")
				net.WriteEntity(entity)
				net.WriteString(entry.uniqueID)
			net.SendToServer()

			return false
		end
	end
end

net.Receive("ixCraftRefresh", function()
	PLUGIN:RefreshStationPanel(true)
end)

-- What the server said about a craft asked for from a panel or a world item.
net.Receive("ixCraftResult", function()
	local bSuccess = net.ReadBool()
	local text = net.ReadString()

	Sound(bSuccess and "complete" or "cancel")

	if (text != "") then
		Say(text)
	end
end)
