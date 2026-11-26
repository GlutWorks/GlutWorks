
-- ix.station: placing station entities from their items, picking them back up, and keeping them
-- (with their smelter contents) across restarts. The entities themselves are ix_station_<id> in
-- the ixcraft plugin.
local PLUGIN = PLUGIN

ix.station = ix.station or {}

-- Saved records that could not be spawned on load (ixcraft disabled, a station renamed or removed).
-- They are written back with every save, so they are not lost before someone can fix that.
ix.station.unloaded = ix.station.unloaded or {}

local PLACE_RANGE = 128

local function GetStations()
	local ixcraft = ix.plugin.list.ixcraft

	return ixcraft and ixcraft.craft and ixcraft.craft.stations or {}
end

--- The uniqueID of the item that places this station.
function ix.station.GetItemID(stationID)
	for uniqueID, itemTable in pairs(ix.item.list) do
		if (itemTable.base == "base_station" and itemTable.entityName == stationID) then
			return uniqueID
		end
	end
end

function ix.station.Spawn(stationID, position, angles, ownerID, smelter)
	if (!GetStations()[stationID]) then
		return
	end

	local entity = ents.Create("ix_station_" .. stationID)

	if (!IsValid(entity)) then
		return
	end

	entity:SetPos(position)
	entity:SetAngles(angles or angle_zero)
	entity:Spawn()
	entity:Activate()
	entity:SetOwnerCharacter(ownerID or 0)

	if (smelter and entity.ixSmelting) then
		ix.smelting.Restore(entity, smelter)
	end

	return entity
end

--- Places a station on the floor where the player is looking, facing them.
-- @treturn[1] Entity the station
-- @treturn[2] nil
-- @treturn[2] string why it could not be placed
function ix.station.Place(client, stationID, smelter)
	local character = client:GetCharacter()

	if (!character) then
		return nil, "You need a character to do that."
	end

	local start = client:GetShootPos()
	local trace = util.TraceLine({
		start = start,
		endpos = start + client:GetAimVector() * PLACE_RANGE,
		filter = client
	})

	if (!trace.Hit or trace.HitSky or trace.HitNormal.z < 0.7) then
		return nil, "Look at the floor where you want to place it."
	end

	local entity = ix.station.Spawn(stationID, trace.HitPos, Angle(0, client:EyeAngles().y + 180, 0),
		character:GetID(), smelter)

	if (!IsValid(entity)) then
		return nil, "This station cannot be placed."
	end

	-- rest the bottom of the model on the floor, then make sure it is not inside anything
	-- (including the player placing it); the box is shrunk a little so the floor itself does not count
	entity:SetPos(trace.HitPos - Vector(0, 0, entity:OBBMins().z))

	local mins, maxs = entity:GetRotatedAABB(entity:OBBMins(), entity:OBBMaxs())
	local blocked = util.TraceHull({
		start = entity:GetPos(),
		endpos = entity:GetPos(),
		mins = mins + Vector(2, 2, 4),
		maxs = maxs - Vector(2, 2, 2),
		filter = entity,
		mask = MASK_SOLID
	})

	if (blocked.Hit or blocked.StartSolid) then
		entity:Remove()

		return nil, "There is not enough room to place it there."
	end

	ix.station.Save()

	return entity
end

--- Turns a placed station back into its item in the player's inventory, smelter contents included.
-- @treturn bool whether it was picked up
function ix.station.PickUp(client, entity)
	-- a removed entity lingers until the end of the frame; this stops it being picked up twice
	if (entity:IsMarkedForDeletion()) then
		return false
	end

	if (!entity:CanPickUp(client)) then
		client:Notify("Only the owner can pick this station up.")
		return false
	end

	local uniqueID = ix.station.GetItemID(entity:GetStationID())

	if (!uniqueID) then
		client:Notify("This station cannot be picked up.")
		return false
	end

	local data = {}

	if (entity.ixSmelting) then
		data.smelter = ix.smelting.Serialize(entity)
	end

	local bSuccess, reason = client:GetCharacter():GetInventory():Add(uniqueID, 1, data)

	if (!bSuccess) then
		client:NotifyLocalized(reason or "noFit")
		return false
	end

	entity:Remove()
	ix.station.Save()

	return true
end

function ix.station.Save()
	local data = table.Copy(ix.station.unloaded)

	for stationID in SortedPairs(GetStations()) do
		for _, entity in ipairs(ents.FindByClass("ix_station_" .. stationID)) do
			if (!entity:IsMarkedForDeletion()) then
				data[#data + 1] = {
					station = stationID,
					pos = entity:GetPos(),
					ang = entity:GetAngles(),
					owner = entity:GetOwnerCharacter(),
					smelter = entity.ixSmelting and ix.smelting.Serialize(entity) or nil
				}
			end
		end
	end

	PLUGIN:SetData(data)
end

--- Saves shortly after, coalescing many changes (such as a map cleanup) into one write.
function ix.station.QueueSave()
	if (!ix.shuttingDown) then
		timer.Create("ixStationSave", 1, 1, ix.station.Save)
	end
end

function ix.station.Load()
	ix.station.unloaded = {}

	for _, v in ipairs(PLUGIN:GetData()) do
		if (istable(v) and isstring(v.station) and isvector(v.pos)) then
			local entity = ix.station.Spawn(v.station, v.pos, isangle(v.ang) and v.ang or angle_zero, tonumber(v.owner), v.smelter)

			if (!IsValid(entity)) then
				ix.station.unloaded[#ix.station.unloaded + 1] = v
			end
		end
	end
end
