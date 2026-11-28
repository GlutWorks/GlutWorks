local PLUGIN = PLUGIN
local plate = "models/hunter/plates/plate2x2.mdl"
local timber = "models/props_wasteland/wood_fence01a"
local metal = "models/props_canal/metalwall005b"
-- Sink the stock frame's six-unit sill below both feet on accepted floor grades.
-- This leaves about 79 units clear under the lintel for a standing 72-unit player.
local level = Vector(0, 0, 37.5)

-- Definitions for reclaiming saved workshops from the earlier modular trial.
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
	if (kind == "roof") then return foot + Vector(0, 0, 86.8), Angle(0, yaw, 0) end
	local pos = foot + level
	if (kind == "frame") then pos = pos - Direction(turn) * 3 end
	return pos, Angle(90, yaw, 0)
end

local function SamePoint(a, b)
	return a:DistToSqr(b) < 4
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

local benchBounds

local function IsFloor(trace)
	return (trace.HitWorld or PLUGIN:IsBuildPiece(trace.Entity)) and !trace.HitSky and trace.HitNormal.z > 0.96
end

local function Blocked(pos, half, ignore)
	local trace = util.TraceHull({start = pos, endpos = pos, mins = -half, maxs = half, mask = MASK_PLAYERSOLID, filter = ignore})
	return trace.Hit or trace.StartSolid
end

-- Solves the same contact point on both sides. The second return is a refusal, including when a
-- candidate exists and can be drawn in the world to show which space needs clearing.
function PLUGIN:BenchLayout(trace, step)
	if (!trace.Hit or trace.HitSky) then return nil, "Aim at level floor." end
	local foot, turn = trace.HitPos, step % 4
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
