local PLUGIN = PLUGIN 
PLUGIN.refine = PLUGIN.refine or {}
PLUGIN.refine.smelter = PLUGIN.refine.smelter or {}
PLUGIN.refine.smelter.list = PLUGIN.refine.smelter.list or {}
PLUGIN.refine.list = PLUGIN.refine.list or {}
PLUGIN.refine.class = PLUGIN.refine.class or {}
PLUGIN.refine.values = PLUGIN.refine.values or {}
PLUGIN.refine.maxValues = PLUGIN.refine.maxValues or {}
PLUGIN.refine.lastSmeltTime = PLUGIN.refine.lastSmeltTime or {}
PLUGIN.refine.maxValues = PLUGIN.refine.maxValues or {}
PLUGIN.refine.maxValues["interactive_smelter"] = {
	["coal"] = 20,
	["smeltable_junk"] = 20
}
PLUGIN.refine.smeltTime = PLUGIN.refine.smeltTime or {}
PLUGIN.refine.smeltTime["interactive_smelter"] = 10