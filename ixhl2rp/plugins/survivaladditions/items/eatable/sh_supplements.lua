
ITEM.name = "Supplements"
ITEM.model = Model("models/props_lab/jar01a.mdl")
ITEM.description = "A white plastic jar containing a good portion of your daily nutrients."
ITEM.restoredHunger = 40
ITEM.restoredHealth = 20
ITEM.restoredStamina = 100

function ITEM:CanConsume(client)
	return !client:IsCombine()
end
