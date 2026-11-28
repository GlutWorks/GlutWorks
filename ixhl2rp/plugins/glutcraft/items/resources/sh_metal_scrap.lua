ITEM.name = "Metal Scrap"
ITEM.description = "A collection of random metal pieces."
ITEM.model = Model("models/props_combine/combine_explosivepanel_shard01b.mdl")
ITEM.functions.handTools = {
	name = "Make carpentry tools (1 kg wood, 1 kg metal)",
	OnCanRun = function(item)
		return !IsValid(item.entity) and ix.plugin.list.fieldworks != nil
	end,
	OnRun = function(item)
		ix.plugin.list.ixcraft.craft.CraftRecipe(item.player, "carpentry_tools")
		return false -- the recipe takes the required quantities
	end
}
