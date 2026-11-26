
-- Base for stackable items. Definitions that set ITEM.stackLimit receive these members through
-- ix.stack.ApplyBase even when they use another base (resources, components, ores).
ITEM.name = "Stackable"
ITEM.description = "A stack of items."
ITEM.category = "Stackables"
ITEM.width = 1
ITEM.height = 1
ITEM.stackLimit = 10
ITEM.stackStep = 1

if (CLIENT) then
	-- Called by the inventory icon as itemTable.PaintOver(panel, itemTable, width, height).
	function ITEM.PaintOver(panel, item, width, height)
		draw.SimpleText(
			ix.stack.Format(item, ix.stack.GetQuantity(item)), "DermaDefault", width - 5, height - 5,
			color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, color_black
		)
	end

	-- Also used for world items: the entity tooltip swaps in the networked data before calling this.
	function ITEM:PopulateTooltip(tooltip)
		local quantity = tooltip:AddRow("quantity")
		quantity:SetText(L("stackQuantity", ix.stack.Format(self, ix.stack.GetQuantity(self)),
			ix.stack.Format(self, self.stackLimit)))
		quantity:SetTextColor(Color(184, 184, 184))
		quantity:SizeToContents()
	end
end

-- Helix destroys a world item on its first hit (its entity never gets real health). For a stack that would be up
-- to a whole stack's worth at once, so stacks in the world ignore damage.
function ITEM:OnEntityTakeDamage(entity, damageInfo)
	return false
end

ITEM.functions.take = {
	tip = "takeTip",
	icon = "icon16/box.png",
	OnRun = function(item)
		local client = item.player
		local bSuccess, result = ix.stack.Pickup(client, item)

		if (!bSuccess) then
			client:NotifyLocalized(result or "unknownError")
			return false
		end

		client:EmitSound("npc/zombie/foot_slide" .. math.random(1, 3) .. ".wav", 75, math.random(90, 120), 1)

		-- A merged pickup already deleted the instance and its entity; a transferred one leaves the entity for
		-- PerformInventoryAction to remove.
		return result == "transferred"
	end,
	OnCanRun = function(item)
		return IsValid(item.entity)
	end
}

-- Run on the stack that was dropped onto; data[1] is the dragged stack's ID as sent by the client.
ITEM.functions.combine = {
	name = "stackCombine",
	icon = "icon16/arrow_join.png",
	OnRun = function(item, data)
		local bSuccess, reason = ix.stack.Combine(item.player, item, istable(data) and data[1] or nil)

		if (!bSuccess and reason) then
			item.player:NotifyLocalized(reason)
		end

		return false
	end,
	OnCanRun = function(item, data)
		if (!istable(data)) then
			return false
		end

		return ix.stack.CanCombine(item, ix.item.instances[data[1]]) == true
	end
}

-- The prompt opens on the client and its answer goes to the ixStackSplit receiver (sv_hooks.lua) with the stack's
-- ID, so two prompts open at once cannot answer each other. The server re-checks everything when the answer arrives.
ITEM.functions.split = {
	name = "stackSplit",
	icon = "icon16/arrow_divide.png",
	OnClick = function(item)
		local itemID = item:GetID()
		local default = tostring(ix.stack.FromUnits(item, math.floor(ix.stack.GetUnits(item) / 2)))

		Derma_StringRequest(L("stackSplitTitle"), L("stackSplitPrompt"), default, function(text)
			net.Start("ixStackSplit")
				net.WriteUInt(itemID, 32)
				net.WriteString(text)
			net.SendToServer()
		end)

		return false
	end,
	OnRun = function(item)
		return false
	end,
	OnCanRun = function(item)
		return !IsValid(item.entity) and ix.stack.GetUnits(item) > 1
	end
}
