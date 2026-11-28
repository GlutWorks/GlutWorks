
-- Clothing that is worn without changing the player's model: boots, coats, gloves, hats. One item per
-- outfitCategory (the wearPart by default) can be equipped. Unlike base_outfit it never touches the model,
-- skin, sub-materials or the character's saved bodygroups; wearBodygroups = {name = value} sets bodygroups
-- on the player only while worn (the Enhanced and Extended Citizens models have torso, hands and beanies).
ITEM.name = "Clothing"
ITEM.description = "Something to wear."
ITEM.category = "Clothing"
ITEM.model = Model("models/props_junk/garbage_bag001a.mdl")
ITEM.width = 1
ITEM.height = 1
ITEM.wearPart = "body"
ITEM.durability = 1
ITEM.carryWeight = 0.7
ITEM.warmth = 0
ITEM.waterproof = 0
ITEM.repairAmount = 25
ITEM.wearBodygroups = nil

function ITEM:GetSlot()
	return self.outfitCategory or self.wearPart
end

if (CLIENT) then
	function ITEM:PaintOver(item, w, h)
		if (item:GetData("equip")) then
			surface.SetDrawColor(110, 255, 110, 100)
			surface.DrawRect(w - 14, h - 14, 8, 8)
		end
	end
end

function ITEM:ApplyBodygroups(client)
	if (!istable(self.wearBodygroups) or !IsValid(client)) then
		return
	end

	for name, value in pairs(self.wearBodygroups) do
		local index = client:FindBodygroupByName(name)

		if (index > -1 and value < client:GetBodygroupCount(index)) then
			client:SetBodygroup(index, value)
		end
	end
end

-- Puts back the bodygroups the character has saved (Helix's "groups" data), without writing it.
function ITEM:RestoreBodygroups(client)
	local character = IsValid(client) and client:GetCharacter()

	if (!istable(self.wearBodygroups) or !character) then
		return
	end

	local groups = character:GetData("groups", {})

	for name in pairs(self.wearBodygroups) do
		local index = client:FindBodygroupByName(name)

		if (index > -1) then
			client:SetBodygroup(index, tonumber(groups[index] or groups[tostring(index)]) or 0)
		end
	end
end

-- The other equipped item in this item's slot, if any.
function ITEM:GetSlotConflict(client)
	local character = IsValid(client) and client:GetCharacter()

	if (!character) then
		return
	end

	for other in character:GetInventory():Iter() do
		if (other.id != self.id and other:GetData("equip") and isfunction(other.GetSlot) and other:GetSlot() == self:GetSlot()) then
			return other
		end
	end
end

function ITEM:EquipWearable(client)
	self:SetData("equip", true)
	self:ApplyBodygroups(client)
	self:OnEquipped(client)
end

function ITEM:UnequipWearable(client)
	self:SetData("equip", false)
	self:RestoreBodygroups(client)
	self:OnUnequipped(client)
end

function ITEM:OnEquipped(client)
end

function ITEM:OnUnequipped(client)
end

function ITEM:CanEquipWearable(client)
	return true
end

ITEM.functions.EquipUn = { -- sorry, for name order.
	name = "unequip",
	tip = "unequipTip",
	icon = "icon16/cross.png",
	OnRun = function(item)
		item:UnequipWearable(item.player)
		return false
	end,
	OnCanRun = function(item)
		local client = item.player

		return !IsValid(item.entity) and IsValid(client) and item:GetData("equip") == true and
			hook.Run("CanPlayerUnequipItem", client, item) != false
	end
}

ITEM.functions.Equip = {
	name = "equip",
	tip = "equipTip",
	icon = "icon16/tick.png",
	OnRun = function(item)
		local client = item.player

		if (item:GetSlotConflict(client)) then
			client:NotifyLocalized(item.equippedNotify or "outfitAlreadyEquipped")
			return false
		end

		item:EquipWearable(client)
		return false
	end,
	OnCanRun = function(item)
		local client = item.player

		return !IsValid(item.entity) and IsValid(client) and item:GetData("equip") != true and
			item:CanEquipWearable(client) != false and hook.Run("CanPlayerEquipItem", client, item) != false
	end
}

-- Neither moved nor dropped while worn: unequip first.
function ITEM:CanTransfer(oldInventory, newInventory)
	if (self:GetData("equip")) then
		return false
	end

	return true
end

function ITEM:OnLoadout()
	if (self:GetData("equip")) then
		self:ApplyBodygroups(self.player)
	end
end

function ITEM:OnRemoved()
	if (self.invID != 0 and self:GetData("equip")) then
		local client = self:GetOwner()

		self.data.equip = false

		if (IsValid(client)) then
			self:RestoreBodygroups(client)
			self:OnUnequipped(client)
		end
	end
end
