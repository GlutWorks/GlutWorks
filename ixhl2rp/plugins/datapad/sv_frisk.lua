local pad = ix.datapad
util.AddNetworkString("ixPadFrisk")
pad.searchOrder = {"waist", "chest", "hands", "legs", "back", "feet"}
local sessions, subjects = {}, {}
local duration = 1.6

local function reachable(client, target)
	if (!pad.Available(client) or !IsValid(target) or !target:Alive() or !target:IsRestricted()) then return false end
	local eyes = client:GetShootPos()
	local point = target:NearestPoint(eyes)
	if (eyes:DistToSqr(point) > 96 * 96) then return false end
	return !util.TraceLine({start = eyes, endpos = point, filter = {client, target}, mask = MASK_SOLID}).Hit
end

local function update(s, region, found)
	for _, viewer in ipairs({s.client, s.target}) do
		if (!IsValid(viewer)) then continue end
		net.Start("ixPadFrisk")
			net.WriteEntity(s.target)
			net.WriteBool(viewer == s.target)
			net.WriteString(region or "")
			net.WriteFloat(duration)
			net.WriteTable(found or {})
			net.WriteTable(region and pad.ReadBody(s.target) or {})
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

function pad.BeginFrisk(client, target)
	if (!reachable(client, target) or !target:GetCharacter() or client == target) then return false end
	local inv = target:GetCharacter():GetInventory()
	if (!inv or subjects[target] or sessions[client] or client.ixOpenStorage or ix.storage.InUse(inv)) then return false end
	local s = {client = client, target = target, char = client:GetCharacter(), inv = inv, stage = 1, next = CurTime() + duration}
	sessions[client], subjects[target] = s, s
	update(s, pad.searchOrder[1])
	target:Notify("You feel someone searching you. Tab shows what they have reached.")
	return true
end

timer.Create("ixDatapadFrisk", 0.15, 0, function()
	for client, s in pairs(sessions) do
		if (!reachable(client, s.target) or client:GetCharacter() != s.char or !s.target:GetCharacter()
			or s.target:GetCharacter():GetInventory() != s.inv or (client.ixOpenStorage and client.ixOpenStorage != s.inv)) then
			pad.EndFrisk(client)
		elseif (!s.complete and CurTime() >= s.next) then
			local region = pad.searchOrder[s.stage]
			local found = {}
			for _, place in ipairs(pad.Layout(s.inv)) do
				if (place.region != region) then continue end
				for _, item in ipairs(place.items) do
					found[#found + 1] = {id = item.id, name = item:GetName(), place = place.name, region = region, flagged = pad.Contraband(item) and true or false}
				end
			end
			s.stage = s.stage + 1
			s.next = CurTime() + duration
			local nextRegion = pad.searchOrder[s.stage]
			update(s, nextRegion or "complete", found)
			if (!nextRegion) then
				s.complete = true
				if (ix.storage.InUse(s.inv)) then
					pad.EndFrisk(client)
				else
					ix.storage.Open(client, s.inv, {
						entity = s.target, name = hook.Run("GetDisplayedName", s.target) or s.target:Name(),
						maxDistance = 96, datapadFrisk = true,
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
end)

-- Storage and its child bags re-check reach for every operation after the search completes.
function PLUGIN:InitializedPlugins()
	if (ix.storage.InReach == pad.checkFriskReach) then return end
	local original = ix.storage.InReach
	pad.checkFriskReach = function(client, inv)
		local info = inv.storageInfo
		if (info and info.datapadFrisk and !reachable(client, info.entity)) then return false end
		return original(client, inv)
	end
	ix.storage.InReach = pad.checkFriskReach
end
