
local PLUGIN = PLUGIN

PLUGIN.name = "Wear"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Clothing, boots and armour wear out with use and can be mended."
PLUGIN.readme = [[
Any item definition with `ITEM.wearPart` ("body", "outer", "feet", "hands" or "head") has a condition
(item data `condition`, 0 to 100) that what happens to it lowers: boots by the distance walked, the garment
covering a hit by the damage taken, everything worn a little per hour and more while swimming. Helix
outfits that replace the model (`outfitCategory == "model"`, the uniforms) count as "body" without opting
in. New clothing uses `base_wearable` from this plugin.

The API is `ix.wear` (libs/sh_wear.lua, libs/sv_wear.lua). Other plugins scale wear with
`ix.wear.AddModifier(id, fn)`, not with a hook, and read `ITEM.warmth` / `ITEM.waterproof` scaled by
`ix.wear.GetEffectiveness(item)`. `OnItemConditionLevelChanged` fires when a level boundary is crossed.

Definition fields: `wearPart`, `durability` (wear is divided by it), `warmth` (degrees C), `waterproof`
(0..1), `repairMaterial`, `repairQuantity`, `repairAmount`, `repairTool`, `bPlural` (the notice says "are"),
and for armoured clothing `plateMaterial`, `plateQuantity`, `plateAmount`, `plateTool`. `base_wearable`
items may also set `wearBodygroups = {name = value}`, applied while worn. The canonical body fields
(from the `body` plugin's `ix.body`) are `regions` (the canonical regions the garment covers, outer
first), `regionWearShare` (per-region share of hit wear, default 1) and `pockets`, a list of
`{id, name, region, capacity, concealment (0..1, default 0), key}` the datapad files carried items into.
]]

ix.config.Add("wearEnabled", true, "Whether clothing, boots and armour wear out. Off stops new wear; condition already lost still counts.", nil, {
	category = "Wear"
})

ix.config.Add("wearBootsDistance", 100, "Kilometres of ordinary walking that take boots of durability 1 from new to ruined.", nil, {
	data = {min = 1, max = 2000},
	category = "Wear"
})

ix.config.Add("wearDamageScale", 1, "Multiplier for the wear that damage taken does to the garment that covers the hit.", nil, {
	data = {min = 0, max = 10, decimals = 2},
	category = "Wear"
})

ix.config.Add("wearPerHour", 1, "Condition points every worn item loses per hour worn, before its durability.", nil, {
	data = {min = 0, max = 50, decimals = 1},
	category = "Wear"
})

ix.util.Include("sv_hooks.lua", "server")
ix.util.Include("cl_hooks.lua", "client")

-- Runs after every plugin and the schema have registered their items, so the uniforms get their defaults.
function PLUGIN:InitializedPlugins()
	ix.wear.ApplyToAll()
end

function PLUGIN:OnReloaded()
	ix.wear.ApplyToAll()

	if (SERVER) then
		self:StartTimers()
	end
end
