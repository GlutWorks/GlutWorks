
ITEM.name = "Metropolice Supplements"
ITEM.model = Model("models/props_lab/jar01b.mdl")
ITEM.description = "A tinned can containing a good portion of your daily nutrients."
ITEM.price = 5
ITEM.factions = {FACTION_MPF, FACTION_OTA}
ITEM.restoredHunger = 50
ITEM.restoredHealth = 30
ITEM.restoredStamina = 100

function ITEM:CanConsume(client)
	return client:IsCombine()
end
