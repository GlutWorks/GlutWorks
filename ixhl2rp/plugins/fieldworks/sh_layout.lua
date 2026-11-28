local PLUGIN = PLUGIN
local plate = "models/hunter/plates/plate2x2.mdl"
local timber = "models/props_wasteland/wood_fence01a"
local metal = "models/props_canal/metalwall005b"
local level = Vector(0, 0, 48)

PLUGIN.parts = {
	frame = {name = "Timber frame", model = "models/props_phx/construct/wood/wood_wire2x2b.mdl", item = "wooden_scrap", cost = 1},
	boards = {name = "Board cladding", model = plate, material = timber, item = "wooden_scrap", cost = 1},
	metal = {name = "Metal cladding", model = plate, material = metal, item = "metal_scrap", cost = 1},
	roof = {name = "Sheet roof", model = plate, material = metal, item = "metal_scrap", cost = 2}
}

function PLUGIN:CanWork(client)
	return client:Alive() and client:GetCharacter() and !client:IsRestricted() and !IsValid(client.ixRagdoll)
		and !client:InVehicle() and !client:IsFrozen() and (SERVER or client:GetLocalVar("ragdoll", 0) == 0)
end

local function Direction(turn)
	return Angle(0, turn * 90, 0):Forward()
end

function PLUGIN:PartPose(kind, foot, turn)
	local yaw = turn * 90
	if (kind == "roof") then return foot + Vector(0, 0, 97.5), Angle(0, yaw, 0) end
	local pos = foot + level
	if (kind == "frame") then pos = pos - Direction(turn) * 3 end
	return pos, Angle(90, yaw, 0)
end

function PLUGIN:IsWall(entity)
	return IsValid(entity) and entity:GetClass() == "ix_fieldpiece" and self.parts[entity:GetKind()] != nil
		and entity:GetKind() != "roof" and (CLIENT or !entity:IsMarkedForDeletion())
end

local function SamePoint(a, b)
	return a:DistToSqr(b) < 4
end

-- A sheet spans two parallel frames one sheet-width apart. Match their feet, including elevation.
function PLUGIN:OppositeWall(wall, sign)
	local target = wall:GetFoot() + Direction(wall:GetTurn()) * (sign * 96)
	for _, other in ipairs(ents.FindInSphere(target + level, 24)) do
		if (self:IsWall(other) and other:GetTurn() % 2 == wall:GetTurn() % 2 and SamePoint(other:GetFoot(), target)) then
			return other
		end
	end
end

function PLUGIN:HoldsRoof(wall)
	for _, entity in ipairs(ents.FindInSphere(wall:GetFoot() + Vector(0, 0, 96), 65)) do
		if (entity:GetClass() == "ix_fieldpiece" and entity:GetKind() == "roof" and (CLIENT or !entity:IsMarkedForDeletion())
			and entity:GetTurn() % 2 == wall:GetTurn() % 2) then
			local offset = Direction(wall:GetTurn()) * 48
			if (SamePoint(entity:GetFoot(), wall:GetFoot() + offset) or SamePoint(entity:GetFoot(), wall:GetFoot() - offset)) then
				return true
			end
		end
	end
end

PLUGIN.joins = {"Extend", "Turn corner", "Turn opposite corner", "Across one roof span", "Across opposite span"}

local benchBounds

local function IsFloor(trace)
	return trace.HitWorld and !trace.HitSky and trace.HitNormal.z > 0.96
end

-- Use a narrow box along the wall. Trimming the ends permits the shared post at a snapped corner.
-- All structure rotations are quarter turns, so these world-aligned tests match the orientation.
local function Blocked(pos, half, ignore)
	local trace = util.TraceHull({start = pos, endpos = pos, mins = -half, maxs = half, mask = MASK_PLAYERSOLID, filter = ignore})
	return trace.Hit or trace.StartSolid
end

-- Solves the same contact point on both sides. The second return is a refusal, including when a
-- candidate exists and can be drawn in the world to show which space needs clearing.
function PLUGIN:Layout(client, kind, trace, step)
	if (!trace.Hit or trace.HitSky) then return nil, "Aim at the floor or a timber frame." end
	local wall = self:IsWall(trace.Entity) and trace.Entity
	local foot, turn = trace.HitPos, step % 4
	if (kind == "workbench") then
		if (!IsFloor(trace)) then return nil, "The workbench needs level ground." end
		-- Keep the existing station placement fallback for unmounted Workshop assets.
		local model = ix.item.list.workbench.model
		local mins, maxs = Vector(-24, -24, 0), Vector(24, 24, 48)
		if (!benchBounds) then benchBounds = util.GetModelInfo(model) or {} end
		if (benchBounds.HullMin) then mins, maxs = benchBounds.HullMin, benchBounds.HullMax end
		local ang = Angle(0, turn * 90, 0)
		local pos = foot - Vector(0, 0, mins.z)
		local center = LocalToWorld((maxs + mins) / 2, angle_zero, pos, ang)
		local half = (maxs - mins) / 2 - Vector(0.25, 0.25, 0.25)
		if (turn % 2 == 1) then half = Vector(half.y, half.x, half.z) end
		local pose = {pos = pos, ang = ang}
		if (Blocked(center, half)) then return pose, "Clear enough room for the workbench." end
		return pose
	end

	if (!self.parts[kind]) then return nil, "Choose a construction piece." end
	if (kind == "frame" and !wall) then
		if (!IsFloor(trace)) then return nil, "Aim at level ground or a frame to join." end
	elseif (!wall) then
		return nil, "Aim at a post or beam of the supporting frame."
	else
		turn, foot = wall:GetTurn(), wall:GetFoot()
		local forward, across = Direction(turn), Direction(turn + 1)
		if (kind == "frame") then
			local join = step % #self.joins
			local side = (trace.HitPos - foot):Dot(across) >= 0 and 1 or -1
			if (join == 0) then
				foot = foot + across * (side * 96)
			elseif (join < 3) then
				foot = foot + across * (side * 48) + forward * (join == 1 and 48 or -48)
				turn = (turn + 1) % 4
			else
				foot = foot + forward * (join == 3 and 96 or -96)
			end
		elseif (kind == "roof") then
			local sign = step % 2 == 0 and 1 or -1
			if (!self:OppositeWall(wall, sign)) then sign = -sign end
			foot = foot + forward * (sign * 48)
			if (!self:OppositeWall(wall, sign)) then
				local pos, ang = self:PartPose(kind, foot, turn)
				return {pos = pos, ang = ang}, "Place a parallel frame across one roof span first."
			end
		elseif (wall:GetKind() != "frame") then
			return nil, "That frame already has cladding."
		end
	end

	local pos, ang = self:PartPose(kind, foot, turn)
	local pose = {pos = pos, ang = ang, foot = foot, turn = turn, wall = wall}
	if (kind == "frame") then
		local offset = Direction(turn + 1) * 44
		for _, endPoint in ipairs({foot + offset, foot - offset}) do
			local floor = util.TraceLine({start = endPoint + Vector(0, 0, 4), endpos = endPoint - Vector(0, 0, 4),
				mask = MASK_SOLID_BRUSHONLY})
			if (!IsFloor(floor) or floor.StartSolid) then return pose, "Both frame posts need level ground." end
		end
	end

	local half = kind == "roof" and Vector(47.4, 47.4, 1.4) or Vector(2.9, 44.6, 47.2)
	if (turn % 2 == 1) then half = Vector(half.y, half.x, half.z) end
	local center = kind == "roof" and pos or foot + level
	local cladding = kind == "boards" or kind == "metal"
	if (Blocked(center, half, cladding and wall or nil)) then return pose, "Something occupies this space." end
	-- A snap may reach beyond the point aimed at. A map partition between them still blocks it.
	local path = util.TraceLine({start = trace.HitPos + trace.HitNormal, endpos = center,
		mask = MASK_SOLID_BRUSHONLY, filter = wall})
	if (path.Hit and path.Fraction < 0.99) then return pose, "The join is behind a wall." end
	return pose
end
