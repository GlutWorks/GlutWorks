ITEM.name = "Winter Coat"
ITEM.description = "A thick padded coat. Warm, but it soaks up rain."
ITEM.model = Model("models/willardnetworks/skills/stitched_cloth.mdl")
ITEM.width = 2
ITEM.height = 2
ITEM.price = 90
ITEM.wearPart = "outer"
ITEM.regions = {"chest", "waist", "arms"}
ITEM.pockets = {
	{id = "outer", name = "Winter coat pockets", region = "chest", capacity = 4, concealment = 0.25},
	{id = "lining", name = "Winter coat inner pocket", region = "chest", capacity = 1, concealment = 0.75}
}
ITEM.durability = 1.5
ITEM.carryWeight = 2.4
ITEM.warmth = 10
ITEM.waterproof = 0.2
ITEM.repairMaterial = "fabric"
ITEM.repairQuantity = 0.5
ITEM.repairAmount = 25
ITEM.repairTool = "sewing_kit"
ITEM.wearBodygroups = {torso = 15} -- jacket
