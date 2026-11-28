-- A station in item form. `entityName` is the ixcraft station ID; "Place" puts ix_station_<entityName>
-- where the player is looking, and the station's "Pick Up" option turns it back into this item.
ITEM.name = "Workbench"
ITEM.description = "A shotty Workbench."
ITEM.model = Model("models/mosi/fnv/props/workstations/workbench.mdl")
ITEM.width = 3
ITEM.height = 2
ITEM.price = 100

if (CLIENT) then
	function ITEM:PopulateTooltip(tooltip)
		if (self:GetData("smelter")) then
			local contents = tooltip:AddRow("smelter")
			contents:SetText("It still holds fuel or smelting.")
			contents:SizeToContents()
		end
	end
end

ITEM.functions.place = {
	name = "Place",
	icon = "icon16/arrow_down.png",
	OnClick = function(item)
		if (item.entityName == "workbench" and ix.plugin.list.fieldworks) then
			ix.plugin.list.fieldworks:StartPlacement(item, "workbench")
			return false
		end
	end,
	OnRun = function(item, data)
		if (istable(data) and data.kind and ix.plugin.list.fieldworks) then
			return ix.plugin.list.fieldworks:PlaceItem(item, data)
		end
		local client = item.player
		local entity, message = ix.station.Place(client, item.entityName, item:GetData("smelter"))

		if (!IsValid(entity)) then
			client:Notify(message)
			return false
		end

		-- returning nothing lets Helix remove the item: it now exists as the placed station
	end,
	OnCanRun = function(item)
		return isstring(item.entityName) and !IsValid(item.entity)
	end
}
