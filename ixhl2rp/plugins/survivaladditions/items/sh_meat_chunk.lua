
ITEM.name = "Meat Chunk"
ITEM.model = Model("models/mosi/fallout4/props/food/bloatflygland.mdl")
ITEM.width = 1
ITEM.height = 1
ITEM.description = "A raw chunk of meat. Your mouth waters at the sight."
ITEM.category = "Consumables"
ITEM.permit = "consumables"

ITEM.functions.Eat = {
	OnRun = function(itemTable)
		local client = itemTable.player

		client:SetHealth(math.min(client:Health() + 10, client:GetMaxHealth()))
		client:EmitSound("npc/antlion_grub/squashed.wav", 75, 150, 0.25)

		return true
	end,
}
