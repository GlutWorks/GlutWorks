local pad = ix.datapad
util.AddNetworkString("ixPadRaised")
util.AddNetworkString("ixPadMove")
util.AddNetworkString("ixPadReceipt")

local HEAVY_HIT_DAMAGE = 15
local INSTANT_ACTIONS = {
	take = true,
	View = true,
	drop = true,
	split = true
}

local function charWetness(char)
	return char and char.GetWetness and char:GetWetness() or 0
end

local function raise(client, value)
	if (client:GetNetVar("datapadRaised") == value) then return end
	client:SetNetVar("datapadRaised", value)
	if (value) then client:SetWepRaised(false) end
end

local function stopHeavyBreath(client)
	if (!IsValid(client)) then return end
	timer.Remove("ixPadBreathStop_" .. client:EntIndex())
	if (client.ixPadBreathSound) then
		client.ixPadBreathSound:Stop()
	end
end

local function playHeavyBreath(client, band)
	if (!IsValid(client) or !client:Alive()) then return end
	if (!client.ixPadBreathSound) then
		client.ixPadBreathSound = CreateSound(client, "player/breathe1.wav")
	end
	local snd = client.ixPadBreathSound
	if (!snd) then return end
	snd:SetSoundLevel(62)
	snd:PlayEx(band >= 3 and 0.34 or 0.22, band >= 3 and math.random(92, 98) or math.random(98, 104))
	local idx = client:EntIndex()
	timer.Create("ixPadBreathStop_" .. idx, 1.15, 1, function()
		if (IsValid(client) and client.ixPadBreathSound) then
			client.ixPadBreathSound:Stop()
		end
	end)
end

function pad.CancelTimedAccess(client, bKeepAction)
	if (!IsValid(client)) then return end
	local had = client.ixPadRummage != nil or client:GetNetVar("datapadRummaging") != nil
	client.ixPadRummage = nil
	if (client:GetNetVar("datapadRummaging") != nil) then
		client:SetNetVar("datapadRummaging", nil)
	end
	if (had and !bKeepAction) then
		client:SetAction(false)
	end
end

function pad.StartTimedAccess(client, place, label, onComplete)
	if (!pad.Available(client)) then return false end
	local delay = pad.GetAccessTime(place)
	if (delay <= 0) then
		if (isfunction(onComplete)) then onComplete(client) end
		return true
	end

	if (client.ixPadRummage) then
		pad.CancelTimedAccess(client, true)
	end

	local char = client:GetCharacter()
	local charID = char and char:GetID()
	local placeName = (istable(place) and place.name) or "bag"
	local seq = (client.ixPadRummageSeq or 0) + 1
	client.ixPadRummageSeq = seq
	client.ixPadRummage = {
		seq = seq,
		charID = charID,
		place = placeName,
		finish = CurTime() + delay
	}
	client:SetNetVar("datapadRummaging", placeName)
	client:EmitSound("npc/combine_soldier/gear" .. math.random(1, 6) .. ".wav", 68, math.random(84, 96), 0.52)

	client:SetAction(label or ("Reaching into " .. placeName .. "..."), delay, function(ply)
		if (!IsValid(ply)) then return end
		local active = ply.ixPadRummage
		if (!active or active.seq != seq) then return end
		ply.ixPadRummage = nil
		ply:SetNetVar("datapadRummaging", nil)
		if (!pad.Available(ply)) then return end
		local curChar = ply:GetCharacter()
		if (!curChar or curChar:GetID() != charID) then return end
		if (isfunction(onComplete)) then onComplete(ply) end
	end)

	return true
end

function pad.GetSlungWeapon(client, overrideActiveClass)
	if (!IsValid(client) or !client:Alive()) then return nil end
	local char = client:GetCharacter()
	local inv = char and char:GetInventory()
	if (!inv) then return nil end

	local activeClass = overrideActiveClass
	if (activeClass == nil) then
		local active = client:GetActiveWeapon()
		activeClass = IsValid(active) and active:GetClass() or ""
	end

	local groups = pad.Layout(inv, charWetness(char))
	for _, place in ipairs(groups) do
		if (place.key != "sling") then continue end
		for _, item in ipairs(place.items) do
			if (item.isWeapon and isstring(item.class) and item.class != "" and item.class != activeClass) then
				return item
			end
		end
		break
	end
	return nil
end

function pad.UpdateSlungWeapon(client, overrideActiveClass)
	if (!IsValid(client)) then return end
	local item = pad.GetSlungWeapon(client, overrideActiveClass)
	local nextVal = item and {
		model = item:GetModel(),
		name = item:GetName(),
		class = item.class
	} or nil
	local cur = client:GetNetVar("ixSlungWeapon")
	if (cur == nil and nextVal == nil) then return end
	if (istable(cur) and istable(nextVal) and cur.model == nextVal.model and cur.name == nextVal.name and cur.class == nextVal.class) then
		return
	end
	client:SetNetVar("ixSlungWeapon", nextVal)
end

net.Receive("ixPadRaised", function(_, client)
	local up = net.ReadBool()
	if (up and (!pad.Available(client) or !ix.item.AllowNet(client))) then return end
	raise(client, up or nil)
	if (!up and pad.EndFrisk) then pad.EndFrisk(client) end
end)

function PLUGIN:PostEntityTakeDamage(client, dmg, taken)
	if (!taken or !client:IsPlayer() or dmg:GetDamage() <= 0) then return end
	if (client.ixPadRummage and (!client:Alive() or dmg:GetDamage() >= HEAVY_HIT_DAMAGE)) then
		pad.CancelTimedAccess(client)
	end
	if (!client:Alive()) then return end
	local kind = "Impact"
	if (dmg:IsBulletDamage()) then kind = "Gunshot"
	elseif (dmg:IsDamageType(DMG_SLASH)) then kind = "Cut"
	elseif (dmg:IsDamageType(DMG_BURN) or dmg:IsDamageType(DMG_SLOWBURN)) then kind = "Burn"
	elseif (dmg:IsDamageType(DMG_CLUB) or dmg:IsDamageType(DMG_CRUSH)) then kind = "Bruise"
	elseif (dmg:IsDamageType(DMG_POISON)) then kind = "Poisoned" end
	local part = ix.body.HitGroupToRegion(client:LastHitGroup(), dmg:GetDamageType())
	client:SetNetVar("datapadHit", {kind = kind, part = part})
end

function PLUGIN:PlayerSpawn(client)
	raise(client, nil)
	pad.CancelTimedAccess(client)
	stopHeavyBreath(client)
	client:SetNetVar("datapadHit", nil)
	pad.UpdateSlungWeapon(client)
end

function PLUGIN:PlayerLoadout(client)
	pad.UpdateSlungWeapon(client)
end

function PLUGIN:PlayerDeath(client)
	raise(client, nil)
	pad.CancelTimedAccess(client)
	stopHeavyBreath(client)
	pad.UpdateSlungWeapon(client)
end

function PLUGIN:PlayerDisconnected(client)
	timer.Remove("ixAct" .. client:SteamID64())
	pad.CancelTimedAccess(client, true)
	stopHeavyBreath(client)
	client.ixPadBreathSound = nil
end

function PLUGIN:PlayerLoadedCharacter(client)
	pad.CancelTimedAccess(client)
	stopHeavyBreath(client)
	pad.UpdateSlungWeapon(client)
end

function PLUGIN:OnPlayerRestricted(client)
	pad.CancelTimedAccess(client)
end

function PLUGIN:PlayerSwitchWeapon(client, _, newWeapon)
	local nextClass = IsValid(newWeapon) and newWeapon:GetClass() or ""
	pad.UpdateSlungWeapon(client, nextClass)
	timer.Simple(0, function()
		if (IsValid(client)) then pad.UpdateSlungWeapon(client) end
	end)
end

local function receipt(client, item, place)
	net.Start("ixPadReceipt")
		net.WriteString(item:GetName())
		net.WriteString(place.name)
	net.Send(client)
end

function PLUGIN:OnWorldStackMerged(client, stack)
	local char = client:GetCharacter()
	local groups = pad.Layout(char:GetInventory(), charWetness(char))
	local place = pad.Locate(groups, stack.id)
	if (place) then receipt(client, stack, place) end
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
	local wetness = charWetness(char)
	local groups = pad.Layout(inv, wetness)
	local current = pad.Locate(groups, item.id)
	if (!current) then return end
	table.RemoveByValue(current.items, item)
	current.used = current.used - pad.Size(item)
	current.kg = current.kg - pad.Weight(item, wetness)
	local place = pad.Destination(groups, item, char:GetData("carryPrefs", {})[item.category])
	if (place and moveTo(client, item, place)) then receipt(client, item, place) end
	pad.UpdateSlungWeapon(client)
end

function PLUGIN:InventoryItemAdded(old, inv, item)
	if (old and old.GetOwner) then
		local oldOwner = old:GetOwner()
		if (IsValid(oldOwner)) then pad.UpdateSlungWeapon(oldOwner) end
	end
	if (inv and inv.GetOwner) then
		local owner = inv:GetOwner()
		if (IsValid(owner)) then pad.UpdateSlungWeapon(owner) end
	end
	if (!inv.GetOwner or (old and old:GetID() != 0)) then return end
	timer.Simple(0, function()
		if (ix.item.instances[item.id] == item) then autoFile(inv, item) end
	end)
end

function PLUGIN:InventoryItemRemoved(inv, _)
	if (inv and inv.GetOwner) then
		local owner = inv:GetOwner()
		if (IsValid(owner)) then pad.UpdateSlungWeapon(owner) end
	end
end

function PLUGIN:CanPlayerInteractItem(client, _, item)
	local storage = IsValid(client) and client.ixOpenStorage
	local foundIDs = storage and storage.storageInfo and storage.storageInfo.datapadFoundIDs
	if (!foundIDs) then return end
	local itemID = isnumber(item) and item or (istable(item) and item.id) or nil
	if (!itemID or foundIDs[itemID]) then return end
	local inst = ix.item.instances[itemID]
	if (!inst) then return end
	local inv = ix.item.inventories[inst.invID]
	if (inv and inv.storageInfo and inv.storageInfo.datapadFoundIDs and !inv.storageInfo.datapadFoundIDs[itemID]) then
		return false
	end
end

-- Only inventories actually attached to the character or current storage can participate.
function pad.Move(client, id, targetKey)
	if (!pad.Available(client)) then return end
	local char = client:GetCharacter()
	local inv = char:GetInventory()
	local own = pad.Layout(inv, charWetness(char))
	local storage = client.ixOpenStorage
	local storageInfo = storage and ix.storage.CanAccess(client, storage) and storage.storageInfo or nil
	local away = {}
	if (storageInfo) then
		away = storageInfo.entity:IsPlayer() and pad.Layout(storage, charWetness(storageInfo.entity:GetCharacter())) or pad.StorageGroups(storage, storageInfo.name)
	end
	local from, item = pad.Locate(own, id)
	local carried = item != nil
	if (!item) then from, item = pad.Locate(away, id) end
	if (!item) then return end
	if (!carried and storageInfo and storageInfo.datapadFoundIDs and !storageInfo.datapadFoundIDs[item.id]) then
		return false, "notAllowed"
	end
	if (!from.inv:OnCheckAccess(client) or !ix.item.CanInteract(client, "move", id, {})) then return end
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
		pad.UpdateSlungWeapon(client)
		if (storageInfo and IsValid(storageInfo.entity) and storageInfo.entity:IsPlayer()) then
			pad.UpdateSlungWeapon(storageInfo.entity)
		end
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
		pad.UpdateSlungWeapon(client)
		return true
	end
	return false, "noFit"
end

function pad.RequestMove(client, id, targetKey)
	if (!pad.Available(client)) then return end
	local char = client:GetCharacter()
	local inv = char:GetInventory()
	local own = pad.Layout(inv, charWetness(char))
	local from, item = pad.Locate(own, id)

	local slowPlace
	if (targetKey == "storage") then
		if (from and from.maxKg != nil) then
			slowPlace = from
		end
	elseif (targetKey != "auto") then
		local dest
		for _, place in ipairs(own) do
			if (place.key == targetKey) then
				dest = place
				break
			end
		end
		if (dest) then
			if (item and (dest == from or !dest.inv:OnCheckAccess(client) or !pad.Fits(dest, item))) then
				return false, "noFit"
			end
			local fromTime = from and pad.GetAccessTime(from) or 0
			local destTime = pad.GetAccessTime(dest)
			if (destTime > fromTime) then
				slowPlace = dest
			elseif (fromTime > 0) then
				slowPlace = from
			end
		end
	end

	if (slowPlace and pad.GetAccessTime(slowPlace) > 0) then
		return pad.StartTimedAccess(client, slowPlace, "Reaching into " .. slowPlace.name .. "...", function(ply)
			local ok, why = pad.Move(ply, id, targetKey)
			if (ok == false) then ply:NotifyLocalized(why or "notAllowed") end
		end)
	end

	return pad.Move(client, id, targetKey)
end

net.Receive("ixPadMove", function(_, client)
	if (!ix.item.AllowNet(client)) then return end
	local id, key = net.ReadUInt(32), net.ReadString()
	if (#key > 64) then return end
	local ok, why = pad.RequestMove(client, id, key)
	if (ok == false) then client:NotifyLocalized(why or "notAllowed") end
end)

function pad.WrapInventoryAction()
	if (ix.item.PerformInventoryAction == pad.performInventoryAction) then return end
	local original = ix.item.PerformInventoryAction
	pad.performInventoryAction = function(client, action, item, invID, data)
		if (pad._performingAction or !IsValid(client) or isentity(item) or INSTANT_ACTIONS[action]) then
			local res = original(client, action, item, invID, data)
			if (IsValid(client)) then pad.UpdateSlungWeapon(client) end
			return res
		end

		local char = client:GetCharacter()
		local inv = char and char:GetInventory()
		local itemID = istable(item) and item.id or tonumber(item)
		if (!inv or !itemID) then
			return original(client, action, item, invID, data)
		end

		local own = pad.Layout(inv, charWetness(char))
		local place, foundItem = pad.Locate(own, itemID)
		if (!place or pad.GetAccessTime(place) <= 0) then
			local res = original(client, action, item, invID, data)
			pad.UpdateSlungWeapon(client)
			return res
		end

		local targetInv = ix.item.inventories[invID or foundItem.invID or 0]
		if (!targetInv or !targetInv:OnCheckAccess(client) or !ix.item.CanInteract(client, action, foundItem, data)) then
			return original(client, action, item, invID, data)
		end

		local fn = foundItem.functions and foundItem.functions[action]
		if (!fn) then
			return original(client, action, item, invID, data)
		end

		foundItem.player = client
		local canRun = !fn.OnCanRun or fn.OnCanRun(foundItem, data) != false
		foundItem.player = nil
		if (!canRun) then
			return original(client, action, item, invID, data)
		end

		return pad.StartTimedAccess(client, place, "Reaching into " .. place.name .. "...", function(ply)
			local inst = ix.item.instances[itemID]
			if (!inst) then return end
			local curChar = ply:GetCharacter()
			local curInv = curChar and curChar:GetInventory()
			if (!curInv or !pad.Locate(pad.Layout(curInv, charWetness(curChar)), itemID)) then return end
			pad._performingAction = true
			local ok, err = pcall(original, ply, action, itemID, inst.invID, data)
			pad._performingAction = nil
			pad.UpdateSlungWeapon(ply)
			if (!ok) then ErrorNoHalt(tostring(err) .. "\n") end
		end)
	end
	ix.item.PerformInventoryAction = pad.performInventoryAction
end

timer.Create("ixDatapadLoad", 1, 0, function()
	local now = CurTime()
	for _, client in player.Iterator() do
		local char = client:GetCharacter()
		if (!pad.Available(client)) then
			raise(client, nil)
			if (client.ixPadRummage) then pad.CancelTimedAccess(client) end
		elseif (client.ixPadRummage and (now > client.ixPadRummage.finish + 0.5 or !timer.Exists("ixAct" .. client:SteamID64()))) then
			pad.CancelTimedAccess(client, true)
		end
		if (client:GetNetVar("datapadHit") and client:Health() >= client:GetMaxHealth()) then
			client:SetNetVar("datapadHit", nil)
		end
		pad.UpdateSlungWeapon(client)
		local inv = char and char:GetInventory()
		local wetness = charWetness(char)
		local kg = 0
		if (inv) then
			for _, item in pairs(inv:GetItems()) do kg = kg + pad.Weight(item, wetness) end
		end
		local _, band = pad.LoadBand(kg)
		if (client:GetLocalVar("carryBand", 1) != band) then client:SetLocalVar("carryBand", band) end
		local netBand = band > 1 and band or nil
		if (client:GetNetVar("carryBand") != netBand) then client:SetNetVar("carryBand", netBand) end
		if (band > 1 and client.ConsumeStamina and client:Alive() and client:OnGround() and client:IsRunning()) then
			client:ConsumeStamina(band == 3 and 1.5 or 0.6)
		end
		if (client:Alive() and !client:InVehicle() and client:WaterLevel() < 3) then
			local stamina = client:GetLocalVar("stm", 100)
			local speed = client:GetVelocity():Length2D()
			if (pad.ShouldEmitHeavyBreath(band, stamina, speed) and now >= (client.ixPadNextBreath or 0)) then
				client.ixPadNextBreath = now + math.Rand(3.5, 5.0)
				playHeavyBreath(client, band)
			end
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
	local info = pad.GetFootstepSound(client:GetLocalVar("carryBand", 1), foot, client:Crouching())
	if (info) then
		client:EmitSound(info.sound, info.level, info.pitch, info.volume)
	end
end
