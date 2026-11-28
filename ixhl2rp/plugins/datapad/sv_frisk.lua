local pad = ix.datapad
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

local function reachable(client, target)
	if (!pad.Available(client) or !IsValid(target) or !target:Alive() or !target:IsRestricted()) then return false end
	local eyes = client:GetShootPos()
	local point = target:NearestPoint(eyes)
	if (eyes:DistToSqr(point) > 96 * 96) then return false end
	return !util.TraceLine({start = eyes, endpos = point, filter = {client, target}, mask = MASK_SOLID}).Hit
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
			net.WriteTable(region and pad.ReadBody(s.target) or {})
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
	if (ix.storage.InReach == pad.checkFriskReach) then return end
	local original = ix.storage.InReach
	pad.checkFriskReach = function(client, inv)
		local info = inv.storageInfo
		if (info and info.datapadFrisk and !reachable(client, info.entity)) then return false end
		return original(client, inv)
	end
	ix.storage.InReach = pad.checkFriskReach
end
