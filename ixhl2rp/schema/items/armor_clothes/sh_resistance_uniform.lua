
ITEM.name = "Resistance Uniform"
ITEM.description = "A resistance uniform with a symbol on the sleeve."
ITEM.category = "Clothing"
ITEM.price = 60
ITEM.flag = "v"
ITEM.maxArmor = 50

function ITEM:OnGetReplacement()
	return Schema:GetUniformModel(self.player:GetModel(), "group03")
end
