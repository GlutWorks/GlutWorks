local PLUGIN = PLUGIN

-- Both materials use the same rectangular cut. Face area determines consumption in 0.1 kg units.
PLUGIN.stock = {
	timber = {name = "Timber", item = "wooden_scrap", material = "models/props_wasteland/wood_fence01a", thickness = 5, areaPerKg = 3000},
	sheet = {name = "Sheet metal", item = "metal_scrap", material = "models/props_canal/metalwall005b", thickness = 3, areaPerKg = 4500}
}
PLUGIN.cutReach = 192
PLUGIN.maxCut = 192

function PLUGIN:StockCost(kind, size)
	return math.max(1, math.ceil(size.x * size.y * 10 / self.stock[kind].areaPerKg - 0.00001)) / 10
end

function PLUGIN:IsBuildPiece(entity)
	return IsValid(entity) and (entity:GetClass() == "ix_build_stock" or entity:GetClass() == "ix_fieldpiece")
		and (CLIENT or !entity:IsMarkedForDeletion())
end

-- Snap to an edge, corner or midpoint on the face the player actually touched.
function PLUGIN:Contact(trace, snap)
	local ent = trace.Entity
	if (!snap or !self:IsBuildPiece(ent) or ent:GetClass() != "ix_build_stock") then return trace.HitPos end
	local p, h = ent:WorldToLocal(trace.HitPos), ent:GetSize() / 2
	for i = 1, 3 do
		local nearest = math.abs(p[i]) < h[i] / 2 and 0 or (p[i] < 0 and -h[i] or h[i])
		if (math.abs(nearest - p[i]) <= 5) then p[i] = nearest end
	end
	return ent:LocalToWorld(p)
end

function PLUGIN:PlaneNormal(mode, normal, yaw)
	if (mode == "upright") then return Angle(0, yaw, 0):Forward() end
	if (mode == "surface") then return normal end
	if (mode == "level") then return Vector(0, 0, 1) end
end

-- Project the third mark perpendicular to the first edge. The resulting four corners describe
-- the back face. Orient its thickness out from the anchor so a sheet can sit flush against it.
function PLUGIN:CutPose(kind, a, b, c, normal, plane)
	local stock = self.stock[kind]
	local edge = b - a
	if (plane) then edge = edge - plane * edge:Dot(plane) end
	local length = edge:Length()
	if (length < 4 or length > self.maxCut + 0.05) then return nil, "Mark an edge between 4 and 192 units long." end
	local along = edge / length
	local side = c - a
	if (plane) then side = side - plane * side:Dot(plane) end
	side = side - along * side:Dot(along)
	local width = side:Length()
	if (width < 3 or width > self.maxCut + 0.05) then return nil, "Mark a width between 3 and 192 units." end
	local up = along:Cross(side / width):GetNormalized()
	if (up:Dot(normal) < -0.001) then up = -up end
	local size = Vector(length, width, stock.thickness)
	-- If only a corner or an edge meets an angled surface, put the entire thickness outside it.
	return {pos = a + (edge + side + up * size.z) / 2, ang = along:AngleEx(up), size = size}
end

-- Sweep the length of the oriented box. Only split its cross-section when the enclosing
-- axis-aligned hull touches something. This keeps a diagonal plank's empty AABB corners usable.
local function Sweep(center, along, side, up, w, h, budget)
	local extent = Vector(math.abs(side.x) * w + math.abs(up.x) * h,
		math.abs(side.y) * w + math.abs(up.y) * h, math.abs(side.z) * w + math.abs(up.z) * h)
	local trace = util.TraceHull({start = center - along, endpos = center + along, mins = -extent, maxs = extent, mask = MASK_PLAYERSOLID})
	if (!trace.Hit and !trace.StartSolid) then return false end
	-- When width and depth already line up with world axes this swept hull is exact.
	local aligned = math.max(math.abs(side.x), math.abs(side.y), math.abs(side.z)) > 0.99999
		and math.max(math.abs(up.x), math.abs(up.y), math.abs(up.z)) > 0.99999
	if (aligned or math.max(w, h) < 0.75 or budget.left <= 0) then return true end
	budget.left = budget.left - 1
	local offset
	if (w > h) then
		w = w / 2
		offset = side * w
	else
		h = h / 2
		offset = up * h
	end
	return Sweep(center - offset, along, side, up, w, h, budget) or Sweep(center + offset, along, side, up, w, h, budget)
end

function PLUGIN:CutBlocked(pose)
	local half = pose.size / 2 - Vector(0.35, 0.35, 0.35)
	return Sweep(pose.pos, pose.ang:Forward() * half.x, pose.ang:Right(), pose.ang:Up(), half.y, half.z, {left = 128})
end
