local pad = ix.datapad
util.AddNetworkString("ixPadRaised")
util.AddNetworkString("ixPadMove")
util.AddNetworkString("ixPadReceipt")

local function raise(client, value)
	if (client:GetNetVar("datapadRaised") == value) then return end
	client:SetNetVar("datapadRaised", value)
	if (value) then client:SetWepRaised(false) end
end

net.Receive("ixPadRaised", function(_, client)
	local up = net.ReadBool()
	if (up and (!pad.Available(client) or !ix.item.AllowNet(client))) then return end
	raise(client, up or nil)
	if (!up and pad.EndFrisk) then pad.EndFrisk(client) end
end)

local bodyParts = {
	[HITGROUP_HEAD] = "head", [HITGROUP_LEFTARM] = "left arm", [HITGROUP_RIGHTARM] = "right arm",
	[HITGROUP_LEFTLEG] = "left leg", [HITGROUP_RIGHTLEG] = "right leg", [HITGROUP_STOMACH] = "waist"
}

function PLUGIN:PostEntityTakeDamage(client, dmg, taken)
	if (!taken or !client:IsPlayer() or !client:Alive() or dmg:GetDamage() <= 0) then return end
	local kind = "Impact"
	if (dmg:IsBulletDamage()) then kind = "Gunshot"
	elseif (dmg:IsDamageType(DMG_SLASH)) then kind = "Cut"
	elseif (dmg:IsDamageType(DMG_BURN) or dmg:IsDamageType(DMG_SLOWBURN)) then kind = "Burn"
	elseif (dmg:IsDamageType(DMG_CLUB) or dmg:IsDamageType(DMG_CRUSH)) then kind = "Bruise"
	elseif (dmg:IsDamageType(DMG_POISON)) then kind = "Poisoned" end
	local part = bodyParts[client:LastHitGroup()] or "chest"
	client:SetNetVar("datapadHit", {kind = kind, part = part})
end

function PLUGIN:PlayerSpawn(client)
	raise(client, nil)
	client:SetNetVar("datapadHit", nil)
end

local function receipt(client, item, place)
	net.Start("ixPadReceipt")
		net.WriteString(item:GetName())
		net.WriteString(place.name)
	net.Send(client)
end

local function moveTo(client, item, place)
	if (item.invID != place.inv:GetID()) then
		local x, y = place.inv:FindEmptySlot(item.width, item.height, true)
		if (!x) then return false, "noFit" end
		local ok, why = item:Transfer(place.inv:GetID(), x, y, client)
		if (!ok) then return false, why end
	end
	local key = !place.maxKg and place.key != "storage" and place.key or nil
	if (item:GetData("carryPlace") != key) then item:SetData("carryPlace", key) end
	return true
end

-- Exclude a newly added item from its provisional location while deciding its permanent one.
local function autoFile(inv, item)
	local client = inv:GetOwner()
	local char = IsValid(client) and client:GetCharacter()
	if (!char or char:GetInventory() != inv or item.invID != inv:GetID()) then return end
	local groups = pad.Layout(inv)
	local current = pad.Locate(groups, item.id)
	if (!current) then return end
	table.RemoveByValue(current.items, item)
	current.used = current.used - pad.Size(item)
	current.kg = current.kg - pad.Weight(item)
	local place = pad.Destination(groups, item, char:GetData("carryPrefs", {})[item.category])
	if (place and moveTo(client, item, place)) then receipt(client, item, place) end
end

function PLUGIN:InventoryItemAdded(old, inv, item)
	if (!inv.GetOwner or (old and old:GetID() != 0)) then return end
	timer.Simple(0, function()
		if (ix.item.instances[item.id] == item) then autoFile(inv, item) end
	end)
end

-- Only inventories actually attached to the character or current storage can participate.
function pad.Move(client, id, targetKey)
	if (!pad.Available(client)) then return end
	local char = client:GetCharacter()
	local inv = char:GetInventory()
	local own = pad.Layout(inv)
	local storage = client.ixOpenStorage
	local away = {}
	if (storage and ix.storage.CanAccess(client, storage)) then
		local info = storage.storageInfo
		away = info.entity:IsPlayer() and pad.Layout(storage) or pad.StorageGroups(storage, info.name)
	end
	local from, item = pad.Locate(own, id)
	local carried = item != nil
	if (!item) then from, item = pad.Locate(away, id) end
	if (!item or !from.inv:OnCheckAccess(client) or !ix.item.CanInteract(client, "move", id, {})) then return end
	if (targetKey == "auto" or targetKey == "storage") then
		if ((targetKey == "storage") != carried) then return end
		local groups = carried and away or own
		local preference = !carried and char:GetData("carryPrefs", {})[item.category]
		local plan = pad.PlanTransfer(groups, item, preference, function(place, stack)
			return place.inv:OnCheckAccess(client) and ix.stack.CanAccess(client, item) and ix.stack.CanAccess(client, stack)
				and ix.item.CanInteract(client, "combine", stack.id, {id})
				and hook.Run("CanTransferItem", item, from.inv, place.inv) != false
				and (!item.CanTransfer or item:CanTransfer(from.inv, place.inv) != false)
		end)
		if (!plan) then return false, "noFit" end
		-- Do the fallible physical transfer first. A refused transfer leaves both stacks untouched.
		if (plan.place) then
			if (!plan.place.inv:OnCheckAccess(client)) then return end
			local ok, why = moveTo(client, item, plan.place)
			if (!ok) then return false, why end
		end
		for _, merge in ipairs(plan.merges) do
			local ok, why = ix.stack.Combine(client, merge.stack, id)
			if (!ok) then return false, why end
		end
		receipt(client, item, plan.place or plan.merges[1].place)
		return true
	end

	for _, dest in ipairs(own) do
		if (dest.key != targetKey) then continue end
		if (dest == from or !dest.inv:OnCheckAccess(client) or !pad.Fits(dest, item)) then return false, "noFit" end
		local ok, why = moveTo(client, item, dest)
		if (!ok) then return false, why end
		if (item.category) then
			local prefs = char:GetData("carryPrefs", {})
			prefs[item.category] = dest.key
			char:SetData("carryPrefs", prefs)
		end
		receipt(client, item, dest)
		return true
	end
	return false, "noFit"
end

net.Receive("ixPadMove", function(_, client)
	if (!ix.item.AllowNet(client)) then return end
	local id, key = net.ReadUInt(32), net.ReadString()
	if (#key > 32) then return end
	local ok, why = pad.Move(client, id, key)
	if (ok == false) then client:NotifyLocalized(why or "notAllowed") end
end)

timer.Create("ixDatapadLoad", 1, 0, function()
	for _, client in player.Iterator() do
		local char = client:GetCharacter()
		if (!pad.Available(client)) then raise(client, nil) end
		if (client:GetNetVar("datapadHit") and client:Health() >= client:GetMaxHealth()) then
			client:SetNetVar("datapadHit", nil)
		end
		local inv = char and char:GetInventory()
		local kg = 0
		if (inv) then
			for _, item in pairs(inv:GetItems()) do kg = kg + pad.Weight(item) end
		end
		local _, band = pad.LoadBand(kg)
		if (client:GetLocalVar("carryBand", 1) != band) then client:SetLocalVar("carryBand", band) end
		if (band > 1 and client.ConsumeStamina and client:Alive() and client:OnGround() and client:IsRunning()) then
			client:ConsumeStamina(band == 3 and 1.5 or 0.6)
		end
	end
end)

util.AddNetworkString("ixPadStorageClose")
net.Receive("ixPadStorageClose", function(_, client)
	local id = net.ReadUInt(32)
	local inv = client.ixOpenStorage
	if (inv and inv:GetID() == id) then ix.storage.Close(inv, client) end
end)

function PLUGIN:PlayerFootstep(client, _, foot)
	local band = client:GetLocalVar("carryBand", 1)
	if (band > 1 and foot == 0 and !client:Crouching()) then
		client:EmitSound("npc/combine_soldier/gear" .. math.random(1, 6) .. ".wav", band == 3 and 62 or 55, 88, 0.27)
	end
end
