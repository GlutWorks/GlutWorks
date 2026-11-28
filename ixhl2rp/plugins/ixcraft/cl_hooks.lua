
local PLUGIN = PLUGIN

-- The station's name and description, read by Examine (and then a smelter's state, from ix_station.lua).
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
