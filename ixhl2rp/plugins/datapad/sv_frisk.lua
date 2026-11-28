local pad = ix.datapad
local INVENTORY = ix.meta.inventory
local ITEM = ix.meta.item
util.AddNetworkString("ixPadFrisk")
util.AddNetworkString("ixPadFriskStart")
pad.HIDDEN_THRESHOLD = pad.HIDDEN_THRESHOLD or 0.7
pad.searchOrder = ix.body and ix.body.FRISK_ORDER or {"waist", "chest", "arms", "legs", "head", "feet"}
local sessions, subjects = {}, {}

function pad.NormalizeFriskMode(mode)
	if (isstring(mode)) then
		local lower = string.lower(string.Trim(mode))
		if (lower == "hasty" or lower == "quick" or lower == "fast") then
			return "hasty"
		end
	end
	return "thorough"
end

function pad.FriskFindsPlace(place, mode)
	if (!istable(place)) then return false end
	mode = (mode == "hasty") and "hasty" or "thorough"
	local concealment = isnumber(place.concealment) and place.concealment or 0
	if (mode == "hasty") then
		return concealment < pad.HIDDEN_THRESHOLD
	end
	return true
end

function pad.BuildFriskPlan(inv, mode)
	mode = (mode == "hasty") and "hasty" or "thorough"
	local stepDuration = mode == "hasty" and 0.85 or 1.6
	local order = ix.body and ix.body.FRISK_ORDER or pad.searchOrder
	local orderIndex = {}
	local stages = {}

	for idx, region in ipairs(order) do
		orderIndex[region] = idx
		stages[#stages + 1] = {
			region = region,
			hidden = false,
			duration = stepDuration,
			label = ix.body and ix.body.GetRegionLabel(region) or region
		}
	end

	if (mode == "thorough" and inv) then
		local hiddenPlaces = {}
		for _, place in ipairs(pad.Layout(inv)) do
			local concealment = isnumber(place.concealment) and place.concealment or 0
			if (concealment >= pad.HIDDEN_THRESHOLD) then
				hiddenPlaces[#hiddenPlaces + 1] = place
			end
		end

		table.sort(hiddenPlaces, function(a, b)
			local ca, cb = a.concealment or 0, b.concealment or 0
			if (ca != cb) then return ca < cb end
			local oa, ob = orderIndex[a.region] or 99, orderIndex[b.region] or 99
			if (oa != ob) then return oa < ob end
			return tostring(a.key) < tostring(b.key)
		end)

		for _, place in ipairs(hiddenPlaces) do
			stages[#stages + 1] = {
				region = place.region,
				hidden = true,
				placeKey = place.key,
				concealment = place.concealment,
				duration = stepDuration,
				label = "Hidden pockets (" .. place.region .. ")"
			}
		end
	end

	return stages, stepDuration
end

function pad.GetFriskSession(client)
	return sessions[client]
end

-- The discovered set a hasty frisk left on an inventory, and who it belongs to. A bag inside
-- the searched inventory usually carries a copy of the storage context; when it does not
-- (its inventory was restored on send), fall back to the storage the viewer has open.
local function friskFilterFor(client, inv)
	if (!inv) then return nil end

	local info = inv.storageInfo
	if (info and info.datapadFoundIDs) then
		return info.datapadFoundIDs, info.entity
	end

	local open = IsValid(client) and client.ixOpenStorage
	local openInfo = open and open.storageInfo
	if (!openInfo or !openInfo.datapadFoundIDs) then return nil end
	if (inv == open) then
		return openInfo.datapadFoundIDs, openInfo.entity
	end

	if (isfunction(open.Iter)) then
		for item, _ in open:Iter() do
			if (item.isBag and item:GetInventory() == inv) then
				return openInfo.datapadFoundIDs, openInfo.entity
			end
		end
	end

	return nil
end

--- Whether `client` may receive or act on item `itemID` inside `inv`. Only a hasty frisk
-- restricts anyone, and never the subject: they keep full access to their own items.
function pad.FriskCanSee(client, inv, itemID)
	local found, subject = friskFilterFor(client, inv)
	if (!found or client == subject) then return true end
	return found[itemID] == true
end

local function receiverSet(list)
	local set = {}
	for _, ply in ipairs(list) do set[ply] = true end
	return set
end

-- Temporarily hides an inventory from the receivers a hasty frisk left in the dark, so a
-- removal replicates only to people who ever received the item.
local function withHiddenReceiversStashed(inv, itemID, fn)
	local stashed = {}

	if (istable(inv.receivers)) then
		for ply, _ in pairs(inv.receivers) do
			if (IsValid(ply) and ply:IsPlayer() and !pad.FriskCanSee(ply, inv, itemID)) then
				stashed[#stashed + 1] = ply
			end
		end
	end

	if (#stashed == 0) then
		return fn()
	end

	local infoBefore = inv.storageInfo
	for _, ply in ipairs(stashed) do inv.receivers[ply] = nil end
	local results = {pcall(fn)}
	local ok = table.remove(results, 1)

	-- If the storage session ended during the call, its receivers stay removed.
	if (inv.storageInfo == infoBefore) then
		for _, ply in ipairs(stashed) do
			if (IsValid(ply)) then inv.receivers[ply] = true end
		end
	end

	if (!ok) then error(results[1]) end
	return unpack(results)
end

--- Holds every Helix replication and transfer path to the discovered set of a hasty frisk:
-- full syncs, slot updates, item data, removals, and `item:Transfer` with a player behind it.
-- Server-initiated transfers (no client) and the subject's own access are untouched.
function pad.WrapFriskReplication()
	pad.stockSync = pad.stockSync or INVENTORY.Sync
	pad.stockSendSlot = pad.stockSendSlot or INVENTORY.SendSlot
	pad.stockInvRemove = pad.stockInvRemove or INVENTORY.Remove
	pad.stockSetData = pad.stockSetData or ITEM.SetData
	pad.stockTransfer = pad.stockTransfer or ITEM.Transfer
	pad.stockItemRemove = pad.stockItemRemove or ITEM.Remove

	pad.friskSync = function(self, receiver, ...)
		local receivers

		if (IsValid(receiver) and receiver:IsPlayer()) then
			receivers = {receiver}
		elseif (istable(receiver)) then
			receivers = receiver
		else
			return pad.stockSync(self, receiver, ...)
		end

		local full, filtered = {}, {}

		for _, ply in ipairs(receivers) do
			if (!IsValid(ply) or !ply:IsPlayer()) then continue end
			local found, subject = friskFilterFor(ply, self)
			if (found and ply != subject) then
				filtered[#filtered + 1] = {ply = ply, found = found}
			else
				full[#full + 1] = ply
			end
		end

		if (#filtered == 0) then
			return pad.stockSync(self, receiver, ...)
		end

		if (#full > 0) then
			pad.stockSync(self, #full == 1 and full[1] or full, ...)
		end

		for _, entry in ipairs(filtered) do
			local slots = {}

			for x, items in pairs(self.slots) do
				for y, item in pairs(items) do
					if (istable(item) and item.gridX == x and item.gridY == y and entry.found[item.id]) then
						slots[#slots + 1] = {x, y, item.uniqueID, item.id, item.data}
					end
				end
			end

			net.Start("ixInventorySync")
				net.WriteTable(slots)
				net.WriteUInt(self:GetID(), 32)
				net.WriteUInt(self.w, 6)
				net.WriteUInt(self.h, 6)
				net.WriteType(self.owner)
				net.WriteTable(self.vars or {})
			net.Send(entry.ply)

			for item, _ in self:Iter() do
				if (entry.found[item.id]) then
					item:Call("OnSendData", entry.ply)
				end
			end
		end
	end

	pad.friskSendSlot = function(self, x, y, item)
		if (!item) then
			return pad.stockSendSlot(self, x, y, item)
		end

		local full, hidden = {}, {}

		for _, ply in ipairs(self:GetReceivers()) do
			if (pad.FriskCanSee(ply, self, item.id)) then
				full[#full + 1] = ply
			else
				hidden[#hidden + 1] = ply
			end
		end

		if (#hidden == 0) then
			return pad.stockSendSlot(self, x, y, item)
		end

		local saved = self.receivers
		local ok, err = pcall(function()
			if (#full > 0) then
				self.receivers = receiverSet(full)
				pad.stockSendSlot(self, x, y, item)
			end
			self.receivers = receiverSet(hidden)
			pad.stockSendSlot(self, x, y, nil)
		end)
		self.receivers = saved
		if (!ok) then error(err) end
	end

	pad.friskInvRemove = function(self, id, bNoReplication, bNoDelete, bTransferring)
		if (bNoReplication) then
			return pad.stockInvRemove(self, id, bNoReplication, bNoDelete, bTransferring)
		end

		return withHiddenReceiversStashed(self, id, function()
			return pad.stockInvRemove(self, id, bNoReplication, bNoDelete, bTransferring)
		end)
	end

	pad.friskSetData = function(self, key, value, receivers, noSave, noCheckEntity)
		if (receivers == false) then
			return pad.stockSetData(self, key, value, receivers, noSave, noCheckEntity)
		end

		local inv = ix.item.inventories[self.invID or 0]
		if (!inv) then
			return pad.stockSetData(self, key, value, receivers, noSave, noCheckEntity)
		end

		local targets = receivers or (inv.GetReceivers and inv:GetReceivers()) or self:GetOwner()
		if (!targets) then
			return pad.stockSetData(self, key, value, receivers, noSave, noCheckEntity)
		end

		local list = (IsValid(targets) and targets:IsPlayer()) and {targets} or targets
		if (!istable(list)) then
			return pad.stockSetData(self, key, value, receivers, noSave, noCheckEntity)
		end

		local allowed, bFiltered = {}, false

		for _, ply in ipairs(list) do
			if (IsValid(ply) and ply:IsPlayer() and !pad.FriskCanSee(ply, inv, self.id)) then
				bFiltered = true
			else
				allowed[#allowed + 1] = ply
			end
		end

		if (!bFiltered) then
			return pad.stockSetData(self, key, value, receivers, noSave, noCheckEntity)
		end

		return pad.stockSetData(self, key, value, #allowed > 0 and allowed or false, noSave, noCheckEntity)
	end

	pad.friskTransfer = function(self, invID, x, y, client, noReplication, isLogical)
		if (IsValid(client)) then
			local curInv = ix.item.inventories[self.invID or 0]

			if (curInv and !pad.FriskCanSee(client, curInv, self.id)) then
				return false, "notAllowed"
			end
		end

		return pad.stockTransfer(self, invID, x, y, client, noReplication, isLogical)
	end

	pad.friskItemRemove = function(self, bNoReplication, bNoDelete)
		local inv = ix.item.inventories[self.invID or 0]

		if (bNoReplication or !inv or (self.invID or 0) == 0) then
			return pad.stockItemRemove(self, bNoReplication, bNoDelete)
		end

		return withHiddenReceiversStashed(inv, self.id, function()
			return pad.stockItemRemove(self, bNoReplication, bNoDelete)
		end)
	end

	INVENTORY.Sync = pad.friskSync
	INVENTORY.SendSlot = pad.friskSendSlot
	INVENTORY.Remove = pad.friskInvRemove
	ITEM.SetData = pad.friskSetData
	ITEM.Transfer = pad.friskTransfer
	ITEM.Remove = pad.friskItemRemove
end

local function reachable(client, target)
	if (!pad.Available(client) or !IsValid(target) or !target:Alive() or !target:IsRestricted()) then return false end
	local eyes = client:GetShootPos()
	local point = target:NearestPoint(eyes)
	if (eyes:DistToSqr(point) > 96 * 96) then return false end
	return !util.TraceLine({start = eyes, endpos = point, filter = {client, target}, mask = MASK_SOLID}).Hit
end

--- The body snapshot one frisk viewer may see now. The subject always gets their own full
-- reading; the searcher only learns of a region's wound (or last-hit mark) once a stage
-- covering that region has finished, as with the items in it.
function pad.FriskBodyFor(s, viewer)
	local body = pad.ReadBody(s.target, viewer)

	if (viewer != s.client or !istable(body)) then
		return body
	end

	local searched = {}

	for i = 1, (s.stage or 1) - 1 do
		local stage = s.plan and s.plan[i]
		if (stage and stage.region) then searched[stage.region] = true end
	end

	if (istable(body.wounds)) then
		for region in pairs(body.wounds) do
			if (!searched[region]) then body.wounds[region] = nil end
		end
	end

	if (istable(body.mark) and body.mark.part and !searched[body.mark.part]) then
		body.mark = nil
	end

	return body
end

local function update(s, stageInfo, found, bStart)
	local region = istable(stageInfo) and stageInfo.region or nil
	local label = istable(stageInfo) and stageInfo.label or ""
	local bHidden = istable(stageInfo) and stageInfo.hidden == true or false
	for _, viewer in ipairs({s.client, s.target}) do
		if (!IsValid(viewer)) then continue end
		net.Start("ixPadFrisk")
			net.WriteEntity(s.target)
			net.WriteBool(viewer == s.target)
			net.WriteString(region or "")
			net.WriteFloat(s.duration or 1.6)
			net.WriteTable(found or {})
			net.WriteTable(region and pad.FriskBodyFor(s, viewer) or {})
			net.WriteString(s.mode or "thorough")
			net.WriteString(label)
			net.WriteBool(bHidden)
			net.WriteBool(bStart == true)
		net.Send(viewer)
	end
end

function pad.EndFrisk(client)
	local s = sessions[client]
	if (!s) then return end
	sessions[client], subjects[s.target] = nil, nil
	update(s)
	if (IsValid(client) and client.ixOpenStorage == s.inv) then ix.storage.Close(s.inv, client) end
end

function pad.BeginFrisk(client, target, mode)
	if (!reachable(client, target) or !target:GetCharacter() or client == target) then return false end
	local inv = target:GetCharacter():GetInventory()
	if (!inv or subjects[target] or sessions[client] or client.ixOpenStorage or ix.storage.InUse(inv)) then return false end
	mode = pad.NormalizeFriskMode(mode)
	local plan, stepDuration = pad.BuildFriskPlan(inv, mode)
	local s = {
		client = client,
		target = target,
		char = client:GetCharacter(),
		inv = inv,
		mode = mode,
		plan = plan,
		duration = stepDuration,
		stage = 1,
		foundIDs = {},
		foundOrder = {},
		next = CurTime() + stepDuration
	}
	sessions[client], subjects[target] = s, s
	update(s, plan[1], nil, true)
	target:Notify("You feel someone searching you. Tab shows what they have reached.")
	return true
end

local function stageMatchesPlace(stage, place)
	local concealment = isnumber(place.concealment) and place.concealment or 0
	if (stage.hidden) then
		if (stage.placeKey) then
			return place.key == stage.placeKey
		end
		return place.region == stage.region and concealment >= pad.HIDDEN_THRESHOLD
	end
	return place.region == stage.region and concealment < pad.HIDDEN_THRESHOLD
end

function pad.UpdateFrisks(now)
	for client, s in pairs(sessions) do
		if (!reachable(client, s.target) or client:GetCharacter() != s.char or !s.target:GetCharacter()
			or s.target:GetCharacter():GetInventory() != s.inv or (client.ixOpenStorage and client.ixOpenStorage != s.inv)) then
			pad.EndFrisk(client)
		elseif (!s.complete and now >= s.next) then
			local stage = s.plan[s.stage]
			local found = {}
			if (stage) then
				for _, place in ipairs(pad.Layout(s.inv)) do
					if (!stageMatchesPlace(stage, place)) then continue end
					for _, item in ipairs(place.items) do
						if (s.foundIDs[item.id]) then continue end
						s.foundIDs[item.id] = true
						local row = {
							id = item.id,
							name = item:GetName(),
							place = place.name,
							region = stage.region,
							hidden = stage.hidden and true or false,
							flagged = pad.Contraband(item) and true or false
						}
						found[#found + 1] = row
						s.foundOrder[#s.foundOrder + 1] = row
					end
				end
			end
			s.stage = s.stage + 1
			s.next = now + s.duration
			local nextStage = s.plan[s.stage]
			update(s, nextStage or {region = "complete", label = "Search complete", hidden = false}, found, false)
			if (!nextStage) then
				s.complete = true
				if (ix.storage.InUse(s.inv)) then
					pad.EndFrisk(client)
				else
					local foundFilter = s.mode == "hasty" and table.Copy(s.foundIDs) or nil
					ix.storage.Open(client, s.inv, {
						entity = s.target,
						name = hook.Run("GetDisplayedName", s.target) or s.target:Name(),
						maxDistance = 96,
						datapadFrisk = true,
						datapadFriskMode = s.mode,
						datapadFoundIDs = foundFilter,
						data = {
							friskMode = s.mode,
							foundIDs = foundFilter
						},
						OnPlayerClose = function()
							-- Storage is still inside RemoveReceiver here.
							if (sessions[client] == s) then
								sessions[client], subjects[s.target] = nil, nil
								update(s)
							end
						end
					})
				end
			end
		end
	end
end

timer.Create("ixDatapadFrisk", 0.15, 0, function() pad.UpdateFrisks(CurTime()) end)

net.Receive("ixPadFriskStart", function(_, client)
	if (!ix.item.AllowNet(client) or !pad.Available(client)) then return end
	local target = net.ReadEntity()
	local mode = net.ReadString()
	if (#mode > 16) then return end
	if (!IsValid(target) or !target:IsPlayer() or target == client or !target:IsRestricted()) then return end
	Schema:SearchPlayer(client, target, mode)
end)

-- Storage and its child bags re-check reach for every operation after the search completes.
function PLUGIN:InitializedPlugins()
	if (ix.body) then pad.searchOrder = ix.body.FRISK_ORDER end
	if (pad.WrapInventoryAction) then pad.WrapInventoryAction() end
	if (pad.WrapFriskReplication) then pad.WrapFriskReplication() end
	if (ix.storage.InReach == pad.checkFriskReach) then return end
	local original = ix.storage.InReach
	pad.checkFriskReach = function(client, inv)
		local info = inv.storageInfo
		if (info and info.datapadFrisk and !reachable(client, info.entity)) then return false end
		return original(client, inv)
	end
	ix.storage.InReach = pad.checkFriskReach
end
