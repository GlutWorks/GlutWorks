
ITEM.name = "Medic Uniform"
ITEM.description = "A resistance uniform with medical insignia on the sleeve."
ITEM.category = "Clothing"
ITEM.price = 60
ITEM.flag = "v"

function ITEM:OnGetReplacement()
	return Schema:GetUniformModel(self.player:GetModel(), "group03m")
end
