local PLUGIN = PLUGIN

PLUGIN.name = "Inventory Panel"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Your bag, containers, corpses and searches on world panels instead of inventory windows."
PLUGIN.readme = [[
Tab holds your bag in front of you as a world panel (ix.worldui, `held`): what you carry, one row per item, equipped
things first and then by category, under a heading that says how full the bag is and what money you have. It moves
with you and turns once you look well away; Tab, right click, or Use off the panel puts it away. Choosing an item
shows what the old right-click menu offered for it (the item's functions that pass `OnCanRun`, with sub-options for
`isMulti` ones, such as Split's amounts), then "Combine with..." where dragging it onto another item did something
(merging stacks, putting it in a bag), Examine and Drop. They are sent exactly as the old menu sent them
(`ixInventoryAction`, a function's own `OnClick`). "Rearrange" repacks the bag on the server, largest first
(`ixInventoryPanelTidy`); a carried bag's View opens it as a second panel to move things in and out.

Opening a container, searching a corpse or a tied player shows one panel at the thing instead of `ixStorageView`: its
contents under one heading and your bag under another. Choosing a row moves that item across
(`ixInventoryPanelMove`): a stack merges into stacks already there, and part of a stack can be moved with Split's
amounts. Money in a storage is taken or left in a few preset amounts through Helix's own `ixStorageMoneyTake` and
`ixStorageMoneyGive`. However the panel closes, the server is told with `ixStorageClose`, as the window did.

The rest of Helix's menu (settings, help, scoreboard, characters and the other tabs) opens on F1 (the `gm_showhelp`
bind), from the Menu row at the bottom of the bag, or with /Menu, and has no Inventory tab. A locked container's password is still typed into Helix's text prompt.
]]

-- How full a bag reads, by the share of its grid cells items take up: the first entry whose share is not
-- exceeded. Shared so checks and tools read the same words.
PLUGIN.fullness = {
	{0, "invPanelEmpty"},
	{0.3, "invPanelLight"},
	{0.6, "invPanelHalf"},
	{0.85, "invPanelMostly"},
	{0.9999, "invPanelNearly"},
	{1, "invPanelFull"}
}

--- How much of an inventory's own grid its items take up: the phrase for it, the share (0 to 1), cells used and
-- cells in all. Items in bags inside it are not counted; the bag item itself is.
function PLUGIN:GetFullness(inventory)
	local used, total = 0, 0

	if (istable(inventory) and inventory.w and inventory.h) then
		total = inventory.w * inventory.h

		for _, item in pairs(inventory:GetItems(true)) do
			used = used + (item.width or 1) * (item.height or 1)
		end
	end

	local share = total > 0 and math.min(used / total, 1) or 1

	for _, entry in ipairs(self.fullness) do
		if (share <= entry[1]) then
			return entry[2], share, used, total
		end
	end

	return "invPanelFull", share, used, total
end

--- The item functions the old right-click menu listed for this item, in its order: every function but drop and
-- combine that passes its OnCanRun, sorted by key, as {key = key, info = function table}; then drop, when it
-- passes, as the second value. `client` becomes item.player while OnCanRun runs, as the menu did.
function PLUGIN:GetItemActions(item, client)
	local actions = {}
	local drop

	if (!istable(item) or !istable(item.functions)) then
		return actions
	end

	item.player = client

	for key, info in SortedPairs(item.functions) do
		if (key == "drop" or key == "combine" or (info.OnCanRun and info.OnCanRun(item) == false)) then
			continue
		end

		actions[#actions + 1] = {key = key, info = info}
	end

	-- as the old menu: only a drop whose OnCanRun exists and allows it
	local info = item.functions.drop

	if (info and info.OnCanRun and info.OnCanRun(item) != false) then
		drop = {key = "drop", info = info}
	end

	item.player = nil

	return actions, drop
end

--- The items `item` could be dragged onto in the old grid to combine it with them: every other item in `items`
-- whose own combine function accepts it (stacks of the same item that are not full, a bag it is not in). A bag is
-- never offered another bag.
function PLUGIN:GetCombineTargets(item, items, client)
	local targets = {}

	if (!istable(item)) then
		return targets
	end

	for _, other in pairs(items) do
		local info = istable(other.functions) and other.functions.combine

		if (!info or other:GetID() == item:GetID() or (item.isBag and other.isBag) or
			(other.isBag and other:GetData("id") == item.invID)) then
			continue
		end

		other.player = client

		local bAllowed = !info.OnCanRun or info.OnCanRun(other, {item:GetID()}) != false

		other.player = nil

		if (bAllowed) then
			targets[#targets + 1] = other
		end
	end

	table.sort(targets, function(a, b)
		return a:GetID() < b:GetID()
	end)

	return targets
end

ix.util.Include("sv_plugin.lua")
ix.util.Include("cl_plugin.lua")

ix.command.Add("Menu", {
	description = "@cmdInvPanelMenu",
	OnRun = function(self, client)
		PLUGIN:OpenMenu(client)
	end
})
