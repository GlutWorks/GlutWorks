
ITEM.name = "Refinery"
ITEM.description = "A refinery used for synthesis."
ITEM.model = Model("models/props_c17/substation_transformer01d.mdl")
ITEM.entityName = "refinery"

ITEM.functions.place = 
{
	name = "Place",
	icon = "icon16/arrow_join.png",
	OnRun = function(item)
		local workbench = ents.Create("ix_station_"..item.entityName)
		position = item:GetOwner():GetItemDropPos(workbench)
		workbench:Spawn()
		workbench:SetAngles(Angle(0, item:GetOwner():EyeAngles().y - 180, 0))
		workbench:SetPos(Vector(position.x, position.y, (item:GetOwner():GetPos().z+27)))
		workbench:Activate()

		hook.Run("OnItemSpawned", workbench)
		return workbench
	end,
	OnCanRun = function()
		return true
	end
}