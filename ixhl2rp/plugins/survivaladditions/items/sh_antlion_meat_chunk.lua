
ITEM.name = "Antlion Meat Chunk"
ITEM.model = Model("models/mosi/fallout4/props/food/radroachmeat.mdl")
ITEM.width = 1
ITEM.height = 1
ITEM.description = "A raw chunk of antlion. It's slimy texture and smell of insect may be offputting to some, but it can be a delicacy if cooked properly."
ITEM.category = "Consumables"

ITEM.functions.Eat = {
	OnRun = function(itemTable)
		local client = itemTable.player

		client:SetHealth(math.min(client:Health() + 10, client:GetMaxHealth()))
		client:EmitSound("npc/antlion_grub/squashed.wav", 75, 150, 0.25)

		return true
	end,
}
