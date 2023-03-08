ITEM.name = "Workbench"
ITEM.description = "A shotty Workbench."
ITEM.model = Model("models/mosi/fnv/props/workstations/workbench.mdl")
ITEM.width = 3
ITEM.height = 2
ITEM.price = 100

ITEM.functions.place = 
{
	name = "Place",
	icon = "icon16/arrow_join.png",
	OnRun = function(item)
		local workbench = ents.Create("ix_station_"..item.entityName)
		position = item:GetOwner():GetItemDropPos(workbench)
		workbench:Spawn()
		workbench:SetAngles(Angle(0, item:GetOwner():EyeAngles().y - 180, 0))
		workbench:SetPos(Vector(position.x, position.y, item:GetOwner():GetPos().z))
		workbench:Activate()

		hook.Run("OnItemSpawned", workbench)
		return workbench
	end,
	OnCanRun = function()
		return true
	end
}