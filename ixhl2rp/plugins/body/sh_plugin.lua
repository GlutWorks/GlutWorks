
local PLUGIN = PLUGIN

PLUGIN.name = "Body"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Canonical body region map shared by hits, clothing coverage, garment pockets and frisks."
PLUGIN.readme = [[
Defines the single canonical body region vocabulary (`ix.body` in libs/sh_body.lua):
`head`, `chest`, `waist`, `arms`, `legs`, `feet`.

Hits (`ix.body.HitGroupToRegion`), garment coverage (`ITEM.regions`, `ITEM.regionWearShare`,
`ix.body.CoversRegion`, `ix.body.GetCoveringGarments`), garment pockets and concealment
(`ITEM.pockets`, `ix.body.GetItemPockets`, `ix.body.BASE_PLACES`), and frisk order
(`ix.body.FRISK_ORDER`) all use the same region IDs with no translation between plugins.
]]
