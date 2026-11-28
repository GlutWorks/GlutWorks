
local PLUGIN = PLUGIN

PLUGIN.name = "Better Crafting"
PLUGIN.author = "wowm0d"
PLUGIN.description = "Recipes made at stations in the world, and the stations themselves."
PLUGIN.license = [[
Copyright 2020 wowm0d
This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/4.0/.
]]
PLUGIN.readme = [[
Adds a better crafting solution to helix.

In GlutWorks things are made in the world: tapping Use on a bench (any station that does not smelt) opens a
world panel beside it (ix.worldui) listing that station's recipes and the ones that need no station, by category,
with the ones that cannot be made yet greyed. Choosing one crafts it through `ixCraftRecipe`; choosing a greyed one
says in a private line what it needs and what is missing. A loose world item that a recipe needing no station uses
offers it among its held-Use options ("Break down"), through `ixCraftFromItem`. There is no Crafting tab.
`PLUGIN.craft.GetStationList` builds the list (shared, so the server can be asked what a player would be shown).
---
> The better crafting plugin is a fully featured and robust crafting system.
Recipes are put into the /recipes/ folder and crafting stations are put into the /stations/ folder.

When creating recipes you can add hooks to before and after any action, example:
```lua
RECIPE:PostHook("OnCanCraft", function(recipeTable, client)
	for _, v in pairs(ents.FindByClass("ix_station_workbench")) do
		if (client:GetPos():DistToSqr(v:GetPos()) < 100 * 100) then
			return true
		end
	end

	return false, "You need to be near a workbench."
end)
```
This will check for a unique crafting station within range called workbench - this hook is called after every other check inside OnCanCraft is made, if you want to hook this before OnCanCraft you would use PreHook instead of PostHook. This hooking feature allows you to literally do anything within your recipes. Available hooks are `"OnCanCraft", "OnCanSee", "OnCraft"` they all have the recipeTable and client as arguments.
Recipe Format:
```lua
RECIPE.name = "RecipeName" -- the row in the station panel, and what the craft is called
RECIPE.description = "Description" -- kept with the recipe; not shown
RECIPE.model = "models/..." -- kept with the recipe; not shown
RECIPE.category = "Category" -- the heading it is listed under in the station panel
RECIPE.requirements = {
	["item_uniqueID"] = 1,
	["item_uniqueID"] = 0.5 -- quantity consumed, counted across stacks (see the stacking plugin)
}
RECIPE.interchangeable_req = {
	["item_uniqueID"] = 1, -- any one of these is consumed, the first in uniqueID order the player has
	["item_uniqueID"] = 1
}
RECIPE.results = {
	["item_uniqueID"] = 1,
	["item_uniqueID"] = {1, 2, 5}, -- table of amounts to choose from
	["item_uniqueID"] = {["min"] = 1, ["max"] = 10} -- table of min and max value
}
RECIPE.tools = {"item_uniqueID", "item_uniqueID"} -- list of items that must be held, not consumed
RECIPE.station = "workbench" -- eyes within RECIPE.stationRange (default 128) of an ix_station_workbench's surface
RECIPE.flag = "F" -- flag to restrict visibility and a requirement
RECIPE.stamina = 5 -- crafting stamina spent on success (default 5; breakdowns 2, weapons 20 in this plugin)
```
Crafting stamina is a per-character pool (`craftStaminaMax`, default 100) that regains
`craftStaminaRegen` points a minute (default 5, a full pool in about 20 minutes), worked out from
the time it was last spent (character data `craftStamina`/`craftStaminaAt`), with no timer.
`OnCanCraft` refuses with the `CraftTooTired` phrase when the pool is below a recipe's `stamina`,
and a successful craft spends it; the pool never goes below zero. Nothing draws it: a greyed
recipe's needs and the refusal line say the maker is too tired.
Results go into the inventory through ix.stack.Give, merging into existing stacks; whatever does not fit is
dropped in front of the player.
Station Format:
```lua
STATION.name = "Name" -- the station panel's title and the start of Examine
STATION.description = "Description" -- read by Examine
STATION.model = "WorldModel"
STATION.smelting = {...} -- makes it a smelter (see sh_smelter.lua); a station without it is a bench
```

Support for the original plugin can be found here: https://discord.gg/mntpDMU
]]

ix.config.Add("craftStaminaMax", 100, "Crafting stamina a rested character holds. Each recipe spends its RECIPE.stamina (default 5) on success.", nil, {
	data = {min = 1, max = 10000},
	category = "Crafting"
})

ix.config.Add("craftStaminaRegen", 5, "Crafting stamina regained per minute. At 5 a full 100 pool is about 20 minutes of work.", nil, {
	data = {min = 0, max = 1000, decimals = 1},
	category = "Crafting"
})

ix.util.Include("cl_hooks.lua", "client")
ix.util.Include("cl_panel.lua", "client")
ix.util.Include("sh_hooks.lua", "shared")

ix.util.Include("meta/sh_recipe.lua", "shared")
ix.util.Include("meta/sh_station.lua", "shared")
