ITEM.name = "Smelter V2"
ITEM.description = "A cool smelter."
ITEM.model = Model("models/props_forest/furnace01.mdl")
ITEM.entityName = "interactive_smelter"
ITEM.width = 3
ITEM.height = 2
ITEM.price = 100

ITEM.functions.place = 
{
	name = "Place",
	icon = "icon16/arrow_join.png",
	OnRun = function(item)
		local workbench = ents.Create("ix_interactive_smelter")
		local position = item:GetOwner():GetItemDropPos(workbench)
		workbench:Spawn()
		workbench:SetAngles(Angle(0, item:GetOwner():EyeAngles().y - 180, 0))
		workbench:SetPos(Vector(position.x, position.y, (item:GetOwner():GetPos().z)))
		workbench:Activate()

		hook.Run("OnItemSpawned", workbench)
		return workbench
	end,
	OnCanRun = function()
		return true
	end
}