
ITEM.base = "base_outfit"
ITEM.name = "Armored Clothes"
ITEM.description = "A suitcase full of clothes."
ITEM.model = Model("models/props_c17/suitcase_passenger_physics.mdl")
ITEM.category = "Armored Clothing"
ITEM.width = 2
ITEM.height = 2
ITEM.maxArmor = 0
-- The armour points are kept in data "armor" while not worn and given to the wearer while worn. With the
-- wear plugin the points it can hold are maxArmor scaled by its condition, and new plating comes from
-- kevlar ("Replace plating"); the garment itself is mended like any other uniform.
ITEM.plateMaterial = "kevlar_roll"
ITEM.plateQuantity = 1
ITEM.plateAmount = 25

if (CLIENT) then
	function ITEM:PopulateTooltip(tooltip)
		local panel = tooltip:AddRowAfter("name", "armor")
		panel:SetBackgroundColor(derma.GetColor("Warning", tooltip))
		panel:SetText(L("armorAmount", self:GetArmor()))
		panel:SizeToContents()
	end
end

--- The armour points the item can hold now: maxArmor while in good condition, less as it wears.
function ITEM:GetArmorCapacity()
	local effectiveness = ix.wear and ix.wear.GetEffectiveness(self) or 1

	return math.floor(self.maxArmor * effectiveness)
end

--- The wearer, if this item is equipped by the character it belongs to.
function ITEM:GetArmorWearer()
	if (!self.id or !self:GetData("equip")) then
		return
	end

	if (CLIENT) then
		return LocalPlayer()
	end

	local owner = self:GetOwner()

	return IsValid(owner) and owner or nil
end

--- The armour points stored on the item (full when never set), up to what it can hold.
function ITEM:GetStoredArmor()
	local capacity = self:GetArmorCapacity()

	if (!self.id) then
		return capacity
	end

	return math.Clamp(tonumber(self:GetData("armor", self.maxArmor)) or 0, 0, capacity)
end

--- The armour points the item has now: the wearer's armour while worn, its stored points otherwise.
function ITEM:GetArmor()
	local wearer = self:GetArmorWearer()

	if (IsValid(wearer)) then
		return math.Clamp(wearer:Armor(), 0, self:GetArmorCapacity())
	end

	return self:GetStoredArmor()
end

function ITEM:OnEquipped()
	self.player:SetArmor(self:GetStoredArmor())
end

function ITEM:OnUnequipped()
	self:SetData("armor", math.Clamp(self.player:Armor(), 0, self:GetArmorCapacity()))
	self.player:SetArmor(0)
end

--- Restores armour points, up to what the item can hold. Returns the points restored.
function ITEM:Repair(amount)
	local old = self:GetArmor()
	local new = math.Clamp(old + (tonumber(amount) or 0), 0, self:GetArmorCapacity())
	local wearer = self:GetArmorWearer()

	self:SetData("armor", new)

	if (SERVER and IsValid(wearer)) then
		wearer:SetArmor(new)
	end

	return new - old
end

-- Called by ix.wear.SetCondition: a worn garment cannot hold more than its condition allows.
function ITEM:OnConditionChanged(old, new, client)
	local capacity = self:GetArmorCapacity()
	local wearer = self:GetArmorWearer()

	if (IsValid(wearer) and wearer:Armor() > capacity) then
		wearer:SetArmor(capacity)
	elseif (!IsValid(wearer) and (tonumber(self:GetData("armor", self.maxArmor)) or 0) > capacity) then
		self:SetData("armor", capacity)
	end
end

function ITEM:OnLoadout()
	if (self:GetData("equip")) then
		self.player:SetArmor(self:GetStoredArmor())
	end
end

function ITEM:OnSave()
	if (self:GetData("equip")) then
		self:SetData("armor", math.Clamp(self.player:Armor(), 0, self:GetArmorCapacity()))
	end
end
