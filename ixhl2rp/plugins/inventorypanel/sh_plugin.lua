local PLUGIN = PLUGIN

PLUGIN.name = "Inventory Panel"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Your bag, containers, corpses and searches as an open case of real things held in the world."
PLUGIN.readme = [[
Tab holds your bag in front of you at the waist as an open case (ix.worldcase, in worldui): the character's real
inventory grid as a lined tray, with every item lying in its own cells as its own model, and your money in a pocket
at the side. Nothing else is written on it: the thing you aim at lifts a little and shows its name and amount
(and whether it is worn or equipped). Tab, right click, or Use aimed off the case puts it away; looking well away,
dying, being tied or knocked out and opening a menu close it too.

Handling is the game's grammar. Tapping Use on an item does its obvious action (PLUGIN:GetTapAction: the first of
Unequip, Equip, Eat, Drink, Apply, Use, Read, Open and View it offers now; a carried bag's View opens it beside your
own). An item with none of those opens its options, as holding Use on any item does: what the old right-click menu
offered for it (functions passing `OnCanRun`, with `isMulti` sub-options such as Split's amounts), sent exactly as
the old menu sent them (`ixInventoryAction`, a function's own `OnClick`), then Examine and Drop.

Holding the attack button on an item picks it up: it follows your aim over the case. Let go over free cells to put
it there (`ixInventoryPanelMove` with the cell), over another item to combine them (`ixInventoryPanelCombine`: the
target's own `combine` function, as dragging one onto the other did: stacks merge, a bag takes the item), over the
other side of a storage to move it across, or well off the case to drop it. Where it cannot go it shows red and
going back is all that happens. While the case is open the attack never reaches the weapon.

Opening a container, searching a corpse or a tied player, or opening a carried bag shows both grids on one case:
theirs on the left, lined differently, and yours on the right. While both are shown a tap moves an item across to
any free cell (a stack merges into stacks there); holding offers part of a stack, and a bag inside a storage can be
opened in place of the storage's grid (right click goes back). Money there moves by holding Use on it (all of it, or
a preset amount) through Helix's own `ixStorageMoneyTake` and `ixStorageMoneyGive`, and a tap moves all of it. However
the case closes, the server is told with `ixStorageClose`, as the window did.

The rest of Helix's menu (settings, help, scoreboard, characters and the other tabs) opens on F1 (the `gm_showhelp`
bind) or with /Menu, and has no Inventory tab. A locked container's password is still typed into Helix's text prompt.
]]

-- The obvious action a tap on a carried item runs: the first of these item functions it offers now (its OnCanRun
-- passes). Anything else is in its options. Equipping comes first so that a tap on something worn takes it off.
PLUGIN.tapActions = {"EquipUn", "Equip", "Eat", "Drink", "Apply", "Use", "use", "read", "Open", "View"}

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

--- How much of an inventory's own grid its items take up: the phrase for it (what aiming at a bag says about it),
-- the share (0 to 1), cells used and cells in all. Items in bags inside it are not counted; the bag item itself is.
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

--- What a tap on a carried item does: the first of PLUGIN.tapActions among its actions now (GetItemActions), as
-- {key = key, info = function table}, or nil when it has none of them.
function PLUGIN:GetTapAction(item, client)
	local actions = self:GetItemActions(item, client)

	for _, key in ipairs(self.tapActions) do
		for _, action in ipairs(actions) do
			if (action.key == key) then
				return action
			end
		end
	end
end

--- Why putting `item` onto `target` would do nothing, as a phrase the player is told: a bag never goes into a bag,
-- nothing equipped goes into one, a bag with no room takes nothing, a full stack takes no more. Nil when nothing
-- known stands in the way (the server still finds out by trying). On the client a bag's room is judged by its top
-- left cells only, so it is a hint there.
function PLUGIN:GetCombineRefusal(item, target)
	if (!istable(item) or !istable(target)) then
		return
	end

	if (target.isBag) then
		if (item.isBag) then
			return "invPanelNoBagInBag"
		elseif (item:GetData("equip")) then
			return "invPanelTakeOffFirst"
		end

		local inner = target.GetInventory and target:GetInventory()

		if (inner and inner.FindEmptySlot and !inner:FindEmptySlot(item.width or 1, item.height or 1, true)) then
			return "invPanelBagFull"
		end
	elseif (ix.stack and ix.stack.IsStackable(target) and target.uniqueID == item.uniqueID) then
		local _, reason = ix.stack.CanCombine(target, item)

		if (reason == "stackFull") then
			return reason
		end
	end
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
