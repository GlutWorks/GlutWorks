ITEM.name = "Carpentry Tools"
ITEM.description = "A salvage hammer and hand tools for framing, cladding and bench assembly."
ITEM.model = "models/props_c17/tools_wrench01a.mdl"
ITEM.width = 1
ITEM.height = 1

ITEM.functions.build = {
	name = "Build",
	OnCanRun = function(item)
		return !IsValid(item.entity)
	end,
	OnClick = function(item)
		ix.plugin.list.fieldworks:OpenTools(item)
		return false
	end,
	OnRun = function(item, data)
		return ix.plugin.list.fieldworks:PlaceItem(item, data)
	end
}
