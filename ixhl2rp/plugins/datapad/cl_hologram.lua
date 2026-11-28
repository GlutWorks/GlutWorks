local pad = ix.datapad
local holo = pad.hologram or {}
pad.hologram = holo

-- The body on the datapad is the character's own model as a hologram: a translucent figure of
-- light, dim where it faces the viewer and glowing at its edges, ruled with level contour lines,
-- standing on a projector's ring. Its mesh is read once (util.GetModelMeshes) in the pose it was
-- made in, its arms set a little out from the body like a statue's, and split by body region:
-- each triangle goes to the region of the bones it follows most (pad.BoneMap), so every region
-- can be lit in its own colour, picked by pointing at it, and shaken on its own. It is built a
-- little a frame and kept per model and bodygroups, so clothing shows as the character wears it.

-- Degrees each arm stands out from straight down.
local ARM_OUT = 28
local MESH_TRIANGLES = 8000
-- Seconds of building a frame, and how many models are kept.
local BUDGET = 0.003
local KEEP = 12
-- Degrees a second the hologram turns, and how long it holds still after being turned by hand.
local SPIN, HOLD = 10, 3
local PITCH = 10
local REVEAL = 0.6
-- Screen pixels from one contour line to the next.
local LINE_PIXELS = 6
local MATERIAL_NO_DRAW = 4
local AMBER = Color(240, 179, 89)

holo.cache = holo.cache or {}
holo.queue = holo.queue or {}

local function regionIndex()
	local index = {}
	for i, region in ipairs(ix.body.REGIONS) do index[region] = i end
	return index
end

local function bodyMask(ent)
	local mask, base = 0, 1
	for i = 0, ent:GetNumBodyGroups() - 1 do
		mask = mask + ent:GetBodygroup(i) * base
		base = base * math.max(ent:GetBodygroupCount(i), 1)
	end
	return mask
end

-- The built hologram of an entity's model as it is dressed now, or nil while it is being built
-- (or could not be: the second value then has `failed`, and it is tried again after a while).
local RETRY = 10
function holo.For(ent)
	if (!IsValid(ent)) then return end
	local model = ent:GetModel()
	if (!isstring(model) or model == "") then return end
	model = model:lower()
	local mask = bodyMask(ent)
	local key = model .. "#" .. mask
	local entry = holo.cache[key]
	if (entry and !(entry.failed and RealTime() - entry.failedAt > RETRY)) then
		entry.used = RealTime()
		return entry.ready and entry or nil, entry
	end
	entry = {key = key, model = model, mask = mask, used = RealTime()}
	holo.cache[key] = entry
	holo.queue[#holo.queue + 1] = entry
end

local function pause()
	if (SysTime() > holo.deadline) then coroutine.yield() end
end

local function fail(entry)
	entry.failed, entry.failedAt = true, RealTime()
end

-- The rotation carrying unit vector a onto unit vector b.
local function rotationBetween(a, b)
	local axis = a:Cross(b)
	local s, c = axis:Length(), a:Dot(b)
	if (s < 1e-6) then return Matrix() end
	axis:Div(s)
	local x, y, z, t = axis.x, axis.y, axis.z, 1 - c
	return Matrix({
		{t * x * x + c, t * x * y - s * z, t * x * z + s * y, 0},
		{t * x * y + s * z, t * y * y + c, t * y * z - s * x, 0},
		{t * x * z - s * y, t * y * z + s * x, t * z * z + c, 0},
		{0, 0, 0, 1}
	})
end

-- Which way the body faces as it was made: crosswise from the right shoulder to the left is its
-- left, and its left crossed with up is its front. (Many models are made facing sideways, and their
-- root bone turns them.) Returns the turn that faces it forward (+X), and its left as made.
local function facing(map, made)
	local left, right
	for b = 0, map.count - 1 do
		if (made[b] and map.name[b]:lower():find("upperarm", 1, true)) then
			if (map.side[b] == -1) then left = made[b]:GetTranslation() elseif (map.side[b] == 1) then right = made[b]:GetTranslation() end
		end
	end
	local across = (left and right) and left - right or Vector(0, 1, 0)
	across.z = 0
	if (across:LengthSqr() < 0.01) then across = Vector(0, 1, 0) end
	across:Normalize()
	local front = across:Cross(vector_up)
	local turn = Matrix()
	turn:Rotate(Angle(0, -math.deg(math.atan2(front.y, front.x)), 0))
	return turn, across
end

-- The statue's pose: the pose the model was made in, each arm turned at the shoulder to stand
-- ARM_OUT degrees from straight down, out to its side (`left` is the body's left as made).
-- Returns, per bone that moves, the matrix that moves it (and every vertex it carries) from where
-- it was made.
local function statue(map, made, left)
	local moves = {}
	for b = 0, map.count - 1 do
		local name = map.name[b]:lower()
		if (!name:find("upperarm", 1, true) or !map.side[b] or !made[b]) then continue end
		local hand
		local function find(i)
			for _, c in ipairs(map.child[i] or {}) do
				if (!hand and map.name[c]:lower():find("hand", 1, true)) then hand = c end
				find(c)
			end
		end
		find(b)
		if (!hand or !made[hand]) then continue end
		local shoulder = made[b]:GetTranslation()
		local reach = made[hand]:GetTranslation() - shoulder
		if (reach:LengthSqr() < 1) then continue end
		reach:Normalize()
		local out = map.side[b] == -1 and 1 or -1
		local angle = math.rad(ARM_OUT)
		local turn = rotationBetween(reach, left * (out * math.sin(angle)) + Vector(0, 0, -math.cos(angle)))
		local to, from = Matrix(), Matrix()
		to:SetTranslation(shoulder)
		from:SetTranslation(-shoulder)
		local move = to * turn * from
		local function carry(i)
			moves[i] = move
			for _, c in ipairs(map.child[i] or {}) do carry(c) end
		end
		carry(b)
	end
	return moves
end

local function chunks(list)
	local meshes = {}
	for from = 1, #list, MESH_TRIANGLES * 3 do
		local part = list
		if (#list > MESH_TRIANGLES * 3) then
			-- (Copied, not unpacked: unpack stops at about 8000 values.)
			part = {}
			for i = from, math.min(from + MESH_TRIANGLES * 3 - 1, #list) do part[#part + 1] = list[i] end
		end
		local mesh = Mesh()
		mesh:BuildFromTriangles(part)
		meshes[#meshes + 1] = mesh
		pause()
	end
	return meshes
end

-- Eyes, teeth and the inside of the mouth are left out: detail a scan of the body has no use for.
local function skipped(path)
	local material = Material(path or "")
	if (bit.band(material:GetInt("$flags") or 0, MATERIAL_NO_DRAW) != 0) then return true end
	local shader = (material:GetShader() or ""):lower()
	return shader:find("eye", 1, true) or shader:find("teeth", 1, true)
end

local function build(entry)
	local started = SysTime()
	-- An entity of the model only to read its bones and hitboxes.
	local ent = ClientsideModel(entry.model, RENDERGROUP_OTHER)
	if (!IsValid(ent)) then return fail(entry) end
	ent:SetNoDraw(true)
	-- Its bones read as __INVALIDBONE__ until they are first set up.
	ent:SetupBones()
	local map = pad.BoneMap(ent)
	ent:Remove()
	local meshes, binds = util.GetModelMeshes(entry.model, 0, entry.mask)
	if (!map or !meshes or !binds) then return fail(entry) end
	entry.readSeconds = SysTime() - started
	pause()
	local made, bones = {}, {}
	for b = 0, map.count - 1 do
		if (binds[b]) then made[b] = binds[b].matrix:GetInverse() end
	end
	local forward, left = facing(map, made)
	local moves = statue(map, made, left)
	local skin = {}
	for b = 0, map.count - 1 do
		local move = moves[b] and forward * moves[b] or forward
		if (made[b]) then bones[b] = move * made[b] end
		local t = move:ToTable()
		skin[b] = {t[1][1], t[1][2], t[1][3], t[1][4], t[2][1], t[2][2], t[2][3], t[2][4], t[3][1], t[3][2], t[3][3], t[3][4]}
	end
	local regions, index = ix.body.REGIONS, regionIndex()
	local boneRegion = {}
	for b = 0, map.count - 1 do boneRegion[b] = index[map.region[b]] or index.chest end

	local fills = {}
	local px, py, pz, nx, ny, nz, tr = {}, {}, {}, {}, {}, {}, {}
	local mins, maxs = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
	local boxes, centres = {}, {}
	local placed = {}
	local rigid = {{bone = 0, weight = 1}}
	local weightOf = {}

	-- A vertex where the statue holds it: each bone's move (none for most) blended by weight.
	local function place(c)
		local done = placed[c]
		if (done) then return done end
		local x, y, z = c.pos.x, c.pos.y, c.pos.z
		local n = c.normal or vector_up
		local ax, ay, az = n.x, n.y, n.z
		local qx, qy, qz, rx, ry, rz, total = 0, 0, 0, 0, 0, 0, 0
		local weights = c.weights
		if (!weights or !weights[1]) then weights = rigid end
		for k = 1, #weights do
			local w = weights[k]
			local m, f = skin[w.bone], w.weight
			if (m) then
				qx = qx + f * (m[1] * x + m[2] * y + m[3] * z + m[4])
				qy = qy + f * (m[5] * x + m[6] * y + m[7] * z + m[8])
				qz = qz + f * (m[9] * x + m[10] * y + m[11] * z + m[12])
				rx = rx + f * (m[1] * ax + m[2] * ay + m[3] * az)
				ry = ry + f * (m[5] * ax + m[6] * ay + m[7] * az)
				rz = rz + f * (m[9] * ax + m[10] * ay + m[11] * az)
			else
				qx, qy, qz = qx + f * x, qy + f * y, qz + f * z
				rx, ry, rz = rx + f * ax, ry + f * ay, rz + f * az
			end
			total = total + f
		end
		if (total <= 0) then qx, qy, qz, rx, ry, rz, total = x, y, z, ax, ay, az, 1 end
		qx, qy, qz = qx / total, qy / total, qz / total
		local length = math.sqrt(rx * rx + ry * ry + rz * rz)
		if (length > 0) then rx, ry, rz = rx / length, ry / length, rz / length end
		-- Its share of each region, by the weight of the bones it follows: where two regions meet,
		-- one fades into the next across the same span the skin bends over.
		local share = {}
		for i = 1, #regions do share[i] = 0 end
		for k = 1, #weights do
			local r = boneRegion[weights[k].bone] or index.chest
			share[r] = share[r] + weights[k].weight / total
		end
		done = {qx, qy, qz, rx, ry, rz, weights, share}
		placed[c] = done
		return done
	end

	local count = 0
	for _, each in ipairs(meshes) do
		if (skipped(each.material)) then continue end
		local corners = each.triangles or {}
		for t = 1, #corners - 2, 3 do
			local a, b, c = place(corners[t]), place(corners[t + 1]), place(corners[t + 2])
			-- The region the triangle's corners follow most, and its side.
			for i = 1, #regions do weightOf[i] = 0 end
			local side = 0
			for _, corner in ipairs({a, b, c}) do
				for _, w in ipairs(corner[7]) do
					local r = boneRegion[w.bone] or index.chest
					weightOf[r] = weightOf[r] + w.weight
					side = side + (map.side[w.bone] or 0) * w.weight
				end
			end
			local region, most = index.chest, -1
			for i = 1, #regions do
				if (weightOf[i] > most) then region, most = i, weightOf[i] end
			end
			side = side > 0.5 and 1 or side < -0.5 and -1 or 0
			-- Drawn in every region it touches, each corner as bright as its share of that region.
			for r = 1, #regions do
				if (a[8][r] + b[8][r] + c[8][r] > 0.001) then
					local fill = fills[r] or {}
					fills[r] = fill
					for _, corner in ipairs({a, b, c}) do
						local lit = math.Round(255 * corner[8][r])
						-- v is the height, so a texture of stripes rules the body with level contour lines.
						fill[#fill + 1] = {pos = Vector(corner[1], corner[2], corner[3]), normal = Vector(corner[4], corner[5], corner[6]),
							u = 0.5, v = corner[3], color = Color(lit, lit, lit)}
					end
				end
			end
			local box = boxes[region] or {Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)}
			boxes[region] = box
			centres[region] = centres[region] or {}
			local sum = centres[region][side] or {0, 0, 0, 0}
			centres[region][side] = sum
			for _, corner in ipairs({a, b, c}) do
				local x, y, z, ax, ay, az = corner[1], corner[2], corner[3], corner[4], corner[5], corner[6]
				local n = #px + 1
				px[n], py[n], pz[n], nx[n], ny[n], nz[n] = x, y, z, ax, ay, az
				mins.x, mins.y, mins.z = math.min(mins.x, x), math.min(mins.y, y), math.min(mins.z, z)
				maxs.x, maxs.y, maxs.z = math.max(maxs.x, x), math.max(maxs.y, y), math.max(maxs.z, z)
				box[1].x, box[1].y, box[1].z = math.min(box[1].x, x), math.min(box[1].y, y), math.min(box[1].z, z)
				box[2].x, box[2].y, box[2].z = math.max(box[2].x, x), math.max(box[2].y, y), math.max(box[2].z, z)
				sum[1], sum[2], sum[3], sum[4] = sum[1] + x, sum[2] + y, sum[3] + z, sum[4] + 1
			end
			tr[#tr + 1] = region
			count = count + 1
			if (count % 64 == 0) then pause() end
		end
	end
	if (count == 0) then return fail(entry) end
	entry.skinSeconds = SysTime() - started - entry.readSeconds

	entry.parts = {}
	for i, region in ipairs(regions) do
		if (fills[i]) then
			entry.parts[region] = {fill = chunks(fills[i])}
			fills[i] = nil
		end
	end
	entry.centres, entry.boxes = {}, {}
	for i, region in ipairs(regions) do
		if (boxes[i]) then
			entry.boxes[region] = boxes[i]
			entry.centres[region] = {}
			for side, sum in pairs(centres[i]) do
				entry.centres[region][side] = Vector(sum[1] / sum[4], sum[2] / sum[4], sum[3] / sum[4])
			end
		end
	end
	entry.map, entry.bones, entry.index = map, bones, index
	entry.px, entry.py, entry.pz, entry.nx, entry.ny, entry.nz, entry.tr = px, py, pz, nx, ny, nz, tr
	entry.mins, entry.maxs, entry.triangles = mins, maxs, count
	entry.snaps = {}
	entry.buildSeconds = SysTime() - started
	entry.ready, entry.readyAt = true, RealTime()
end

local function evict()
	local ready = {}
	for _, entry in pairs(holo.cache) do
		if (entry.ready) then ready[#ready + 1] = entry end
	end
	if (#ready <= KEEP) then return end
	table.SortByMember(ready, "used", true)
	for i = 1, #ready - KEEP do
		local entry = ready[i]
		if (RealTime() - entry.used < 5) then continue end
		for _, part in pairs(entry.parts) do
			for _, mesh in ipairs(part.fill) do mesh:Destroy() end
		end
		holo.cache[entry.key] = nil
	end
end

hook.Add("Think", "ixDatapadHologramBuild", function()
	local job = holo.job
	if (!job) then
		local entry = table.remove(holo.queue, 1)
		if (!entry) then return end
		job = {entry = entry, routine = coroutine.create(build)}
		holo.job = job
	end
	holo.deadline = SysTime() + BUDGET
	local ok, err = coroutine.resume(job.routine, job.entry)
	if (!ok) then
		fail(job.entry)
		ErrorNoHalt("[datapad] hologram of " .. job.entry.model .. " could not be built: " .. tostring(err) .. "\n")
	end
	if (!ok or coroutine.status(job.routine) == "dead") then
		holo.job = nil
		evict()
	end
end)

-- The character's own hologram is built ahead, so the pad shows it the moment it is raised.
timer.Create("ixDatapadHologramWarm", 2, 0, function()
	local client = LocalPlayer()
	if (IsValid(client) and client:GetCharacter()) then holo.For(client) end
end)

-- The camera looks at the body from a little above and orbits it: an orthographic view, so a
-- point's place on the pad is two dot products and pointing at it is a straight ray. (Drawn, the
-- camera stays put and the body turns the other way, which is the same picture: see renderView.)
function holo.Camera(entry, yaw)
	local mins, maxs = entry.mins, entry.maxs
	local centre = (mins + maxs) * 0.5
	local angles = Angle(PITCH, yaw + 180, 0)
	local forward = angles:Forward()
	return {origin = centre - forward * 300, angles = angles, forward = forward, right = angles:Right(),
		up = angles:Up(), half = (maxs.z - mins.z) * 0.58, centre = centre, yaw = yaw}
end

function holo.Project(view, pos)
	local camera, rect = view.cam, view.rect
	local rel = pos - camera.origin
	local u, v = rel:Dot(camera.right), rel:Dot(camera.up)
	return rect.x + (u + camera.half) / (2 * camera.half) * rect.w, rect.y + (camera.half - v) / (2 * camera.half) * rect.h
end

-- The region under a point of the pad: the nearest triangle a ray through it meets.
function holo.Pick(view, mx, my)
	local entry, camera, rect = view.entry, view.cam, view.rect
	if (!camera) then return end
	local u = (mx - rect.x) / rect.w * 2 * camera.half - camera.half
	local v = camera.half - (my - rect.y) / rect.h * 2 * camera.half
	local o = camera.origin + camera.right * u + camera.up * v
	local d = camera.forward
	local ox, oy, oz, dx, dy, dz = o.x, o.y, o.z, d.x, d.y, d.z
	local px, py, pz, tr = entry.px, entry.py, entry.pz, entry.tr
	local best, nearest = nil, math.huge
	for i = 1, #tr do
		local k = i * 3 - 2
		local ax, ay, az = px[k], py[k], pz[k]
		local e1x, e1y, e1z = px[k + 1] - ax, py[k + 1] - ay, pz[k + 1] - az
		local e2x, e2y, e2z = px[k + 2] - ax, py[k + 2] - ay, pz[k + 2] - az
		local hx, hy, hz = dy * e2z - dz * e2y, dz * e2x - dx * e2z, dx * e2y - dy * e2x
		local det = e1x * hx + e1y * hy + e1z * hz
		if (det > 1e-9 or det < -1e-9) then
			local inv = 1 / det
			local sx, sy, sz = ox - ax, oy - ay, oz - az
			local a = (sx * hx + sy * hy + sz * hz) * inv
			if (a >= 0 and a <= 1) then
				local qx, qy, qz = sy * e1z - sz * e1y, sz * e1x - sx * e1z, sx * e1y - sy * e1x
				local b = (dx * qx + dy * qy + dz * qz) * inv
				if (b >= 0 and a + b <= 1) then
					local t = (e2x * qx + e2y * qy + e2z * qz) * inv
					if (t > 0 and t < nearest) then best, nearest = tr[i], t end
				end
			end
		end
	end
	return best and ix.body.REGIONS[best]
end

-- A spot kept as a bone and a point in its frame (pad.StruckPoint), on this hologram's skin: the
-- nearest vertex of that bone's region to it. Returns its place on the pad and whether its skin
-- faces the viewer, so a mark on the far side is hidden as the body turns.
function holo.Spot(view, bone, at)
	local entry = view.entry
	local index = isstring(bone) and entry.map.index[bone]
	local matrix = index and entry.bones[index]
	if (!matrix or !isvector(at) or !view.cam) then return end
	local key = bone .. " " .. tostring(at)
	local snap = entry.snaps[key]
	if (!snap) then
		local p = matrix * at
		local region = entry.index[entry.map.region[index]]
		local px, py, pz, tr = entry.px, entry.py, entry.pz, entry.tr
		local best, nearest = nil, math.huge
		for i = 1, #tr do
			if (tr[i] == region) then
				for k = i * 3 - 2, i * 3 do
					local dx, dy, dz = px[k] - p.x, py[k] - p.y, pz[k] - p.z
					local d = dx * dx + dy * dy + dz * dz
					if (d < nearest) then best, nearest = k, d end
				end
			end
		end
		snap = best and {pos = Vector(px[best], py[best], pz[best]), normal = Vector(entry.nx[best], entry.ny[best], entry.nz[best])}
			or {pos = p, normal = -view.cam.forward}
		entry.snaps[key] = snap
	end
	local x, y = holo.Project(view, snap.pos)
	return x, y, snap.normal:Dot(view.cam.forward) < -0.05
end

-- The middle of a region on the pad, or of one side of it (-1 left, 1 right) for a pair of limbs.
function holo.Centre(view, region, side)
	local centres = view.entry.centres[region]
	local centre = centres and (centres[side or 0] or (side == nil and (centres[-1] or centres[1])))
	if (!centre or !view.cam) then return end
	return holo.Project(view, centre)
end

-- A region's extent on the pad, as x, y, x2, y2.
function holo.Box(view, region)
	local box = view.entry.boxes[region]
	if (!box or !view.cam) then return end
	local x, y, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
	for i = 0, 7 do
		local corner = Vector(bit.band(i, 1) == 0 and box[1].x or box[2].x, bit.band(i, 2) == 0 and box[1].y or box[2].y,
			bit.band(i, 4) == 0 and box[1].z or box[2].z)
		local sx, sy = holo.Project(view, corner)
		x, y, x2, y2 = math.min(x, sx), math.min(y, sy), math.max(x2, sx), math.max(y2, sy)
	end
	return x, y, x2, y2
end

-- The height the scan has reached as it first draws the body, on the pad, or nil once it is whole.
function holo.RevealLine(view)
	if (!view.cam or (view.reveal or 1) >= 1) then return end
	local entry = view.entry
	local z = entry.mins.z + (entry.maxs.z - entry.mins.z) * view.reveal
	local _, y = holo.Project(view, Vector(view.cam.centre.x, view.cam.centre.y, z))
	return y
end

-- The glow is the picture at GLOW texels across, blurred and stretched back over it; GLOW_TAP is
-- each of its nine copies' share of the light.
local SIZE, GLOW, GLOW_TAP = 1024, 96, 60
local CLAMP = bit.bor(4, 8)
local target = GetRenderTargetEx("ixDatapadHologram", SIZE, SIZE, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_SEPARATE,
	CLAMP, 0, IMAGE_FORMAT_RGBA8888)
local glow = GetRenderTargetEx("ixDatapadHologramHalo", GLOW, GLOW, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_NONE,
	CLAMP, 0, IMAGE_FORMAT_RGBA8888)
-- One period of the contour lines, eight texels tall: a thin bright line, its falloff, a dark gap.
local lines = GetRenderTargetEx("ixDatapadHologramRules", 4, 8, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_NONE,
	0, 0, IMAGE_FORMAT_RGBA8888)
local LINE_ROWS = {255, 110, 52, 38, 34, 38, 52, 110}
-- The unruled sheen's share of a region's light.
local SHEEN = 0.45
-- Added onto the screen as light. Not $vertexalpha: additive blending would then scale by the
-- target's alpha, which the opaque meshes leave low (measured: a fifth of the brightness).
local function light(name, texture)
	return CreateMaterial(name, "UnlitGeneric", {["$basetexture"] = texture:GetName(), ["$additive"] = "1", ["$vertexcolor"] = "1"})
end
local screen, screenGlow = light("ixDatapadHologramLight", target), light("ixDatapadHologramHaloLight", glow)
local copy = light("ixDatapadHologramCopyLight", target)
local worldMaterial = CreateMaterial("ixDatapadHologramWorld", "UnlitGeneric", {["$basetexture"] = "color/white",
	["$additive"] = "1", ["$vertexcolor"] = "1"})
-- One material a region, so each is set to one colour once a frame. Lit, unlike the rest: the
-- light (set in renderView) makes the figure dim where it faces the viewer and bright at its edges.
-- Added as light, each vertex by its share of the region (its vertex colour), so the regions sum
-- to one smooth figure, and see-through where one part passes in front of another.
local bodyMaterials, sheenMaterials = {}, {}
local function bodyMaterial(region)
	if (!bodyMaterials[region]) then
		-- (Set again after creating it: a material of that name made before is handed back as it was.)
		bodyMaterials[region] = CreateMaterial("ixDatapadHologramRuled_" .. region, "VertexLitGeneric",
			{["$basetexture"] = lines:GetName(), ["$additive"] = "1", ["$vertexcolor"] = "1"})
		bodyMaterials[region]:SetTexture("$basetexture", lines)
		sheenMaterials[region] = CreateMaterial("ixDatapadHologramShine_" .. region, "VertexLitGeneric",
			{["$basetexture"] = "color/white", ["$additive"] = "1", ["$vertexcolor"] = "1"})
	end
	return bodyMaterials[region], sheenMaterials[region]
end

local function tint(material, key, color, k)
	material:SetVector(key, Vector(color.r / 255 * k, color.g / 255 * k, color.b / 255 * k))
end

-- The projector under the feet: a faint plate and a dashed ring, level, fixed while the body turns.
local RING_DASHES = 30
local function projector(entry, camera, color)
	local z = entry.mins.z - 0.3
	local radius = math.max(entry.maxs.x - entry.mins.x, 12) * 0.95
	local c = camera.centre
	render.SetColorMaterial()
	mesh.Begin(MATERIAL_POLYGON, 40)
	for i = 0, 39 do
		local a = i / 40 * math.pi * 2
		mesh.Position(Vector(c.x + math.cos(a) * radius, c.y + math.sin(a) * radius, z))
		mesh.Color(color.r * 0.16, color.g * 0.16, color.b * 0.16, 255)
		mesh.AdvanceVertex()
	end
	mesh.End()
	mesh.Begin(MATERIAL_QUADS, RING_DASHES)
	for i = 0, RING_DASHES - 1 do
		local a1, a2 = i / RING_DASHES * math.pi * 2, (i + 0.55) / RING_DASHES * math.pi * 2
		for _, corner in ipairs({{a1, 0.94}, {a2, 0.94}, {a2, 1.06}, {a1, 1.06}}) do
			mesh.Position(Vector(c.x + math.cos(corner[1]) * radius * corner[2], c.y + math.sin(corner[1]) * radius * corner[2], z + 0.05))
			mesh.Color(color.r, color.g, color.b, 255)
			mesh.AdvanceVertex()
		end
	end
	mesh.End()
end

local function renderView(view)
	local entry, camera, pixels = view.entry, view.cam, view.pixels
	local phase = ix.option.Get("reduceMotionEffects", false) and 0 or RealTime()
	-- The stripes are drawn every frame: a render target's contents can be lost to a mode change.
	render.PushRenderTarget(lines)
		cam.Start2D()
			for row, value in ipairs(LINE_ROWS) do
				surface.SetDrawColor(value, value, value, 255)
				surface.DrawRect(0, row - 1, 4, 1)
			end
		cam.End2D()
	render.PopRenderTarget()
	-- Contour lines a fixed number of screen pixels apart, whatever size the body is shown at.
	local density = Matrix()
	density:Scale(Vector(1, pixels / (2 * camera.half) / LINE_PIXELS, 1))
	-- Drawn from a fixed camera with the body turned the other way: the light stays with the view.
	local still = holo.Camera(entry, 0)
	local turn = Matrix()
	turn:Translate(camera.centre)
	turn:Rotate(Angle(0, -camera.yaw, 0))
	turn:Translate(-camera.centre)
	render.PushRenderTarget(target)
	render.Clear(0, 0, 0, 255, true, true)
	cam.Start({type = "3D", origin = still.origin, angles = still.angles, x = 0, y = 0, w = pixels, h = pixels,
		znear = 1, zfar = 600, ortho = {left = -camera.half, right = camera.half, top = -camera.half, bottom = camera.half}})
		projector(entry, still, AMBER)
		local clipping
		if ((view.reveal or 1) < 1) then
			clipping = render.EnableClipping(true)
			render.PushCustomClipPlane(Vector(0, 0, -1), -(entry.mins.z + (entry.maxs.z - entry.mins.z) * view.reveal))
		end
		-- Lit from every side but the viewer's: faces turned to the viewer are dim, edges bright.
		render.SuppressEngineLighting(true)
		render.ResetModelLighting(0, 0, 0)
		render.SetModelLighting(BOX_FRONT, 0.03, 0.03, 0.03)
		render.SetModelLighting(BOX_BACK, 0.03, 0.03, 0.03)
		render.SetModelLighting(BOX_LEFT, 1, 1, 1)
		render.SetModelLighting(BOX_RIGHT, 1, 1, 1)
		render.SetModelLighting(BOX_TOP, 0.75, 0.75, 0.75)
		render.SetModelLighting(BOX_BOTTOM, 0.4, 0.4, 0.4)
		-- The lines and an unruled sheen in the same light, both added: the edges glow as one
		-- unbroken outline while the lines stay the brightest thing on the body.
		for region, part in pairs(entry.parts) do
			local style = view.styles[region]
			local material, sheen = bodyMaterial(region)
			tint(material, "$color2", style.color, style.fill)
			tint(sheen, "$color2", style.color, style.fill * SHEEN)
			material:SetMatrix("$basetexturetransform", density)
			local placed = turn
			if (style.shake != 0) then
				placed = Matrix()
				placed:SetTranslation(still.right * style.shake * math.sin(phase * 23))
				placed = placed * turn
			end
			cam.PushModelMatrix(placed)
				render.SetMaterial(material)
				for _, piece in ipairs(part.fill) do piece:Draw() end
				render.SetMaterial(sheen)
				for _, piece in ipairs(part.fill) do piece:Draw() end
			cam.PopModelMatrix()
		end
		render.SuppressEngineLighting(false)
		render.ResetModelLighting(1, 1, 1)
		if (clipping != nil) then
			render.PopCustomClipPlane()
			render.EnableClipping(clipping)
		end
	cam.End3D()
	render.PopRenderTarget()
	-- The glow: the picture shrunk and blurred, laid under it on the screen.
	-- (Blurred by hand, nine shifted copies added up: render.BlurRenderTarget, run before the
	-- frame is drawn, leaves the whole frame black.)
	render.PushRenderTarget(glow)
		render.Clear(0, 0, 0, 255)
		cam.Start2D()
			surface.SetMaterial(copy)
			surface.SetDrawColor(GLOW_TAP, GLOW_TAP, GLOW_TAP, 255)
			for dx = -1, 1 do
				for dy = -1, 1 do
					surface.DrawTexturedRectUV(dx * 2, dy * 2, GLOW, GLOW, 0, 0, pixels / SIZE, pixels / SIZE)
				end
			end
		cam.End2D()
	render.PopRenderTarget()
end

-- A body shown on the pad: the hologram of `ent` in `rect` (pad units). Its styles, one a region
-- ({color, fill, shake}), are what the next frame draws; its camera is this frame's, for placing
-- marks and pointing.
function holo.View(s, ent, rect)
	local entry, pending = holo.For(ent)
	if (!entry) then return nil, pending and pending.failed end
	local view = s.holo
	if (!view or view.key != entry.key) then
		view = {key = entry.key, created = RealTime(), styles = {}, spin = 20}
		s.holo = view
	end
	view.entry, view.ent, view.rect, view.asked = entry, ent, rect, RealTime()
	view.revealFrom = math.max(view.created, s.started or 0, entry.readyAt)
	local plane = s.plane
	if (plane) then
		local a = (plane.pos + plane.right * rect.x * plane.scale):ToScreen()
		local b = (plane.pos + plane.right * (rect.x + rect.w) * plane.scale):ToScreen()
		view.pixels = math.Clamp(math.ceil(math.abs(b.x - a.x)), 96, SIZE)
	else
		view.pixels = 256
	end
	return view
end

function holo.Blit(view)
	if (!view.cam or view.drawn != view.key) then return false end
	local rect, k = view.rect, view.drawnPixels / SIZE
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(screenGlow)
	surface.DrawTexturedRect(rect.x, rect.y, rect.w, rect.h)
	surface.SetMaterial(screen)
	surface.DrawTexturedRectUV(rect.x, rect.y, rect.w, rect.h, 0, 0, k, k)
	return true
end

hook.Add("PreRender", "ixDatapadHologram", function()
	local s = pad.screen
	local view = s and s.holo
	if (!view or !view.entry or !view.entry.ready or RealTime() - (view.asked or 0) > 0.25) then return end
	local now = RealTime()
	local dt = math.min(now - (view.last or now), 0.1)
	view.last = now
	if (!ix.option.Get("reduceMotionEffects", false) and now - (s.holoHeld or 0) > HOLD) then
		view.spin = (view.spin + dt * SPIN) % 360
	end
	view.cam = holo.Camera(view.entry, view.spin + (s.holoYaw or 0))
	view.reveal = math.Clamp((now - view.revealFrom) / REVEAL, 0, 1)
	for _, region in ipairs(ix.body.REGIONS) do
		view.styles[region] = view.styles[region] or {color = AMBER, fill = 0.85, shake = 0}
	end
	renderView(view)
	view.drawn, view.drawnPixels = view.key, view.pixels
end)

-- The same body, small and in one colour, standing on the screen of a datapad someone else holds:
-- feet at `feet`, facing out along `normal`, `height` units tall.
function holo.DrawWorld(ent, feet, right, up, normal, height, color)
	local entry = holo.For(ent)
	if (!entry) then return end
	local k = height / math.max(entry.maxs.z - entry.mins.z, 1)
	local centre = (entry.mins + entry.maxs) * 0.5
	-- The model's forward goes out of the screen, its left to the viewer's right (it faces them)
	-- and its up up the screen. SetRight stores the negated vector as the second column.
	local matrix = Matrix()
	matrix:SetForward(normal * k)
	matrix:SetRight(-right * k)
	matrix:SetUp(up * k)
	matrix:SetTranslation(feet - (normal * centre.x + right * centre.y + up * entry.mins.z) * k)
	tint(worldMaterial, "$color", color, 0.7)
	cam.PushModelMatrix(matrix)
		render.SetMaterial(worldMaterial)
		for _, part in pairs(entry.parts) do
			for _, piece in ipairs(part.fill) do piece:Draw() end
		end
	cam.PopModelMatrix()
end
