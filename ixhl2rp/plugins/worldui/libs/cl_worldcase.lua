--[[--
An open case held in the world.

A case is one or more grids of cells drawn as a shallow lined tray in the world, holding objects:
client-side models of real things, each lying in its own cells in a resting pose chosen from its
bounds (thinnest axis up, unless its own up is nearly as thin; longest along the longer side of its
cells; a model whose declared bounds are far larger than it is laid out by its collision hull),
scaled to fit them and lit by the world's light where the case is (never quite black, so a dark room
still shows it). A model that is missing is a plain block in its cells. It is held in front of the
player at the waist and tilted toward them (`held`), or held between the player and a thing
(`anchor`), and it is handled by aiming at it: there is no cursor, no icon and nothing on the HUD.
In first person it is drawn over the world as hands are; in third person it is held ahead and right
of the body, larger, and the body stands in front of it.
The object under the aim lifts a little and shows a small label (its `label` and `detail`); nothing
else is written anywhere. Only one case is open at a time.

While a case is open it takes Use and both attack buttons (worldui.PlayerBindPress), the weapon and
hands are not drawn and the weapon never fires:
- tapping Use on an object calls OnTap; holding it calls OnHold, which usually opens an ix.worldui
  panel of options beside the object (`case:FollowObject(panel, object)`); letting go on a row of
  that panel chooses it, letting go anywhere else closes it, as everywhere else in the game;
- holding attack on an object (CanCarry) carries it with the aim, and the case holds still while it
  does; Evaluate says what letting go at a place would do (nil: nothing, and the object shows red),
  and letting go calls OnRelease (false: nothing was done; otherwise the object shows where it was
  put until SetObjects moves it, for up to a second); if the game window loses focus while it is
  carried it goes back where it was;
- right click puts a carried object back, else calls OnBack (true: it went back somewhere), else
  closes the case; Use aimed off the case closes it.

	local case = ix.worldcase.Open({
		held = true,                -- or `anchor = entity`: held toward it, closed beyond `reach`
		name = "bag",               -- for tools: the harness reports it
		grids = {                   -- left to right
			{id = "theirs", w = 4, h = 4, style = "wood"},
			{id = "own", w = 6, h = 4, style = "lined", pocket = true} -- a strip at the side for loose things
		},
		OnTap = function(case, object) end,
		OnHold = function(case, object) return panel end,
		CanCarry = function(case, object) return true end,
		Evaluate = function(case, object, place) return "move", "hint shown while carrying" end,
		OnRelease = function(case, object, place, result) return true end,
		OnBack = function(case) return false end,
		OnClose = function(case, reason) end   -- reason: one of ix.worldui.reasons
	})

	case:SetObjects({                -- replaces them all; models are kept for keys that stay
		{key = 12, grid = "own", x = 1, y = 1, w = 2, h = 1, model = "models/weapons/w_pistol.mdl",
			skin = 0, material = nil, bodygroups = nil, label = "Pistol", detail = "equipped"},
		{key = "money", grid = "own", pocket = true, model = "models/props_lab/box01a.mdl", label = "35 tokens"}
	})
	case:SetGrids(grids)             -- other grids (a bag opened in place of a storage's)
	case:GetAimed()                  -- the object under the aim (or nil), and the place under it
	case:GetCarry()                  -- the carried object, the place it would go and Evaluate's answer
	case:GetAimPos(target)           -- a world point to aim at: an object, {grid, x, y} or {off = true}
	case:IsAimedAt()                 -- whether the aim is on the case
	case:FollowObject(panel, object, place) -- a panel at a `position` stays beside the object or the place (and the case holds still)
	case:Press("use" | "attack" | "attack2", buttonCode, bVirtual) / case:Release(kind)
	case:Close()

A place is {grid = id, x = column, y = row, cx = aimed column, cy = aimed row, over = the object in
the aimed cell} on a grid (x, y: where a carried object's top left cell would go), {grid = id,
pocket = true} on a pocket, {edge = true} on the case but in no cell, or {off = true} clearly off it.
Styles are in ix.worldcase.styles (stock materials only). The models exist only while the case is
open: they are made when it opens or an object first appears and removed when it closes, whatever
closes it (death, a character switch, a Lua refresh).
]]
-- @module ix.worldcase

ix.worldcase = ix.worldcase or {}

local worldcase = ix.worldcase

-- A Lua refresh: the case the last copy of this file opened goes, with its models.
if (worldcase.open and worldcase.open.Close) then
	worldcase.open:Close("interrupted")
end

for entity in pairs(worldcase.models or {}) do
	if (IsValid(entity)) then
		entity:Remove()
	end
end

worldcase.models = setmetatable({}, {__mode = "k"})

-- Sizes in world units. A cell is CELL_MAX across at most, less when the case would be wider than WIDTH (one grid)
-- or WIDTH_PAIR (two), or deeper than DEPTH; never under CELL_MIN.
local CELL_MAX, CELL_MIN = 3.7, 1.9
local WIDTH, WIDTH_PAIR, DEPTH = 27, 43, 16
local RIM = 0.75 -- the frame around a tray
local WALL = 1.3 -- the frame's top above the lining
local BELOW = 1.1 -- the tray's underside below the lining
local GAP = 1.4 -- between two trays
local POCKET = 1.3 -- a pocket's width, in cells
local DIVIDER = 0.22 -- the low wall between the cells and the pocket
local DIVIDER_HEIGHT = 0.55
local SEAM = 0.07 -- the lines between cells
local HIT = 0.7 -- the aim is read at this height above the lining
local OFF = 1.3 -- cells beyond the case's edge where a carried thing is off it
local LIFT, CARRY_LIFT = 0.7, 3.4 -- how far an aimed and a carried object rise
local FILL = 0.84 -- the share of its cells' size an object may take
local UPRIGHT = 1.2 -- a model stays on its own base when its height is within this of its thinnest side
local MAX_SCALE = 2
local TEXTURE = 7 -- world units per repeat of a lining or frame texture

-- Where it is held: ahead of the eyes and below them (about the waist), turned with the view only once the view's
-- yaw is HELD_FOLLOW degrees from it, and tilted TILT degrees toward the player. In third person the camera orbits
-- behind the head, so a case beside the body would take a turn of some 70 degrees to look at (and would turn away
-- as the view did): it is held THIRD_AHEAD ahead of the eyes and THIRD_SIDE to the right instead, about 24 degrees
-- right of the view when looking at it, THIRD_SCALE times larger as though nearer the camera, and turned with the
-- view only past THIRD_FOLLOW degrees. Held toward an anchor, it is ANCHOR_AHEAD ahead.
local HELD_AHEAD, HELD_BELOW, HELD_FOLLOW = 18, 21, 28
local THIRD_AHEAD, THIRD_SIDE, THIRD_BELOW, THIRD_SCALE, THIRD_FOLLOW = 40, 20, 22, 1.8, 42
local ANCHOR_AHEAD, PAIR_AHEAD = 28, 28
local TILT = 18
local GRACE = 0.3 -- seconds after opening before looking away can close it
local RISE = 0.14 -- seconds it takes to come up into the hands

-- Light: what the case and its things reflect is the world's light where it is, never darker than this (a dark room
-- still shows them, dimly), for the tray (gamma) and the models (linear).
local TRAY_FLOOR, MODEL_FLOOR = 0.48, 0.12

local COLOR_LABEL_BACK = Color(14, 13, 11, 228)
local COLOR_LABEL = Color(238, 233, 220)
local COLOR_LABEL_DETAIL = Color(170, 165, 152)
local COLOR_AIM = Color(255, 248, 230, 16)
local COLOR_AIM_THING = Color(255, 246, 222, 42)
local COLOR_FITS = Color(225, 236, 210, 34)
local COLOR_REFUSED = Color(255, 92, 70, 46)

local UP = Vector(0, 0, 1)
local ANGLE_PER_UNIT = 0.0013 -- as worldui's panels: a label's text is as tall as a panel's, a little smaller

--- Tray styles: the lining's and frame's stock materials (their base texture is used) and colours.
worldcase.styles = worldcase.styles or {}
worldcase.styles.lined = {
	lining = "models/props_c17/furniturefabric001a", liningColor = Color(122, 104, 80),
	frame = "models/props_c17/furnituremetal001a", frameColor = Color(92, 86, 74)
}
worldcase.styles.wood = {
	lining = "models/props_wasteland/wood_fence01a", liningColor = Color(150, 136, 116),
	frame = "models/props_wasteland/wood_fence01a", frameColor = Color(104, 90, 74)
}
worldcase.styles.cloth = {
	lining = "models/props_c17/furniturefabric003a", liningColor = Color(118, 116, 122),
	frame = "models/props_c17/furniturefabric001a", frameColor = Color(84, 78, 64)
}
worldcase.styles.metal = {
	lining = "models/props_c17/furniturefabric002a", liningColor = Color(128, 86, 76),
	frame = "models/props_canal/metalwall005b", frameColor = Color(112, 112, 108)
}

local reasons -- ix.worldui.reasons, once cl_worldui.lua has run

local resolution = 1
local materials = {}

-- An unlit copy of a stock material's base texture, made once, coloured by its mesh and by the light each frame.
local function CaseMaterial(path)
	if (materials[path]) then
		return materials[path]
	end

	local source = Material(path)
	local texture = !source:IsError() and source:GetTexture("$basetexture")
	local name = texture and !texture:IsError() and texture:GetName() or "vgui/white"

	materials[path] = CreateMaterial("ixWorldCase" .. util.CRC(path), "UnlitGeneric", {
		["$basetexture"] = name,
		["$vertexcolor"] = 1,
		["$nocull"] = 1
	})

	return materials[path]
end

local blockMaterial = CreateMaterial("ixWorldCaseBlock", "UnlitGeneric", {
	["$basetexture"] = "vgui/white",
	["$vertexcolor"] = 1,
	["$nocull"] = 1
})

local CASE = {}
CASE.__index = CASE

--- Opens a case, closing the one already open. See the top of this file.
-- @realm client
-- @tab info Grids, callbacks and options
-- @treturn table The case
function worldcase.Open(info)
	if (!istable(info) or !istable(info.grids) or #info.grids == 0 or (!info.held and !IsValid(info.anchor))) then
		error("ix.worldcase.Open needs `grids` and `held` or an `anchor` entity", 2)
	end

	reasons = ix.worldui.reasons

	if (worldcase.open) then
		worldcase.open:Close(reasons.replaced)
	end

	local client = LocalPlayer()
	local character = client:GetCharacter()

	local case = setmetatable({
		info = info,
		name = info.name,
		bHeld = info.held == true,
		anchor = !info.held and info.anchor or nil,
		reach = info.reach or 128,
		lookAway = math.cos(math.rad(info.lookAway or 75)),
		objects = {},
		byKey = {},
		openedAt = RealTime(),
		characterID = character and character:GetID(),
		-- reused every frame
		matrix = Matrix(),
		toEntity = Matrix(),
		offset = Matrix(),
		full = Matrix(),
		vector = Vector(),
		color = Vector(1, 1, 1)
	}, CASE)

	case:SetGrids(info.grids)
	case:Update(client)

	worldcase.open = case

	return case
end

--- The open case, or nil.
function worldcase.GetOpen()
	local case = worldcase.open

	if (case and !case.bClosed) then
		return case
	end
end

--- Closes the open case, if any.
function worldcase.Close(reason)
	if (worldcase.open) then
		worldcase.open:Close(reason)
	end
end

function CASE:IsOpen()
	return !self.bClosed
end

-- One quad of a mesh being built: four corners {x, y, z}, a normal, a colour for each corner (or one for all) and
-- texture coordinates taken from the two axes the quad lies along.
local function Quad(quads, a, b, c, d, normal, colors)
	quads[#quads + 1] = {a, b, c, d, normal, colors}
end

local function BuildMesh(quads)
	local built = Mesh()

	mesh.Begin(built, MATERIAL_QUADS, #quads)
		for _, quad in ipairs(quads) do
			local normal = quad[5]
			local colors = quad[6]
			local axisU, axisV

			-- texture along the two axes the quad is not facing
			if (math.abs(normal.z) > 0.5) then
				axisU, axisV = 1, 2
			elseif (math.abs(normal.x) > 0.5) then
				axisU, axisV = 2, 3
			else
				axisU, axisV = 1, 3
			end

			for i = 1, 4 do
				local corner = quad[i]
				local color = istable(colors[1]) and colors[i] or colors

				mesh.Position(Vector(corner[1], corner[2], corner[3]))
				mesh.Normal(normal)
				mesh.TexCoord(0, corner[axisU] / TEXTURE, corner[axisV] / TEXTURE)
				mesh.Color(color[1], color[2], color[3], 255)
				mesh.AdvanceVertex()
			end
		end
	mesh.End()

	return built
end

local function Shade(color, factor)
	return {math.min(color.r * factor, 255), math.min(color.g * factor, 255), math.min(color.b * factor, 255)}
end

-- A box of the frame material: its top and four sides (the bottom is never seen).
local function Box(quads, x0, y0, x1, y1, z0, z1, color)
	local top, side, low = Shade(color, 1), Shade(color, 0.8), Shade(color, 0.55)

	Quad(quads, {x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}, {x0, y1, z1}, UP, top)
	Quad(quads, {x0, y0, z0}, {x1, y0, z0}, {x1, y0, z1}, {x0, y0, z1}, Vector(0, -1, 0), {low, low, side, side})
	Quad(quads, {x0, y1, z0}, {x1, y1, z0}, {x1, y1, z1}, {x0, y1, z1}, Vector(0, 1, 0), {low, low, side, side})
	Quad(quads, {x0, y0, z0}, {x0, y1, z0}, {x0, y1, z1}, {x0, y0, z1}, Vector(-1, 0, 0), {low, low, side, side})
	Quad(quads, {x1, y0, z0}, {x1, y1, z0}, {x1, y1, z1}, {x1, y0, z1}, Vector(1, 0, 0), {low, low, side, side})
end

-- The lining (floor, the lines between cells and the inside of the walls) and the frame (rim, outside, the
-- pocket's divider) of one grid's tray, as two meshes in the case's own space.
local function BuildTray(grid, cell)
	local style = worldcase.styles[grid.style] or worldcase.styles.lined
	local lining, frame = {}, {}
	local x0, x1, y0, y1 = grid.innerLeft, grid.innerRight, grid.innerNear, grid.innerFar
	local lc, fc = style.liningColor, style.frameColor

	-- the floor in nine pieces, darker toward the walls where little light reaches
	local band = math.min(cell * 0.45, 1.2)
	local xs = {x0, x0 + band, x1 - band, x1}
	local ys = {y0, y0 + band, y1 - band, y1}
	local edge, inner = Shade(lc, 0.62), Shade(lc, 1)

	for i = 1, 3 do
		for j = 1, 3 do
			local function C(a, b)
				return ((a == 1 or a == 4) or (b == 1 or b == 4)) and edge or inner
			end

			Quad(lining, {xs[i], ys[j], 0}, {xs[i + 1], ys[j], 0}, {xs[i + 1], ys[j + 1], 0}, {xs[i], ys[j + 1], 0}, UP,
				{C(i, j), C(i + 1, j), C(i + 1, j + 1), C(i, j + 1)})
		end
	end

	-- the lines between cells: a faint darker seam
	local seam = Shade(lc, 0.7)
	local half = SEAM * 0.5

	for c = 1, grid.w - 1 do
		local x = grid.cellsLeft + c * cell

		Quad(lining, {x - half, grid.cellsNear, 0.02}, {x + half, grid.cellsNear, 0.02}, {x + half, grid.cellsFar, 0.02},
			{x - half, grid.cellsFar, 0.02}, UP, seam)
	end

	for r = 1, grid.h - 1 do
		local y = grid.cellsFar - r * cell

		Quad(lining, {grid.cellsLeft, y - half, 0.02}, {grid.cellsRight, y - half, 0.02},
			{grid.cellsRight, y + half, 0.02}, {grid.cellsLeft, y + half, 0.02}, UP, seam)
	end

	-- the inside of the walls, dark at the foot
	local foot, lip = Shade(lc, 0.45), Shade(lc, 0.78)

	Quad(lining, {x0, y1, 0}, {x1, y1, 0}, {x1, y1, WALL}, {x0, y1, WALL}, Vector(0, -1, 0), {foot, foot, lip, lip})
	Quad(lining, {x0, y0, 0}, {x1, y0, 0}, {x1, y0, WALL}, {x0, y0, WALL}, Vector(0, 1, 0), {foot, foot, lip, lip})
	Quad(lining, {x0, y0, 0}, {x0, y1, 0}, {x0, y1, WALL}, {x0, y0, WALL}, Vector(1, 0, 0), {foot, foot, lip, lip})
	Quad(lining, {x1, y0, 0}, {x1, y1, 0}, {x1, y1, WALL}, {x1, y0, WALL}, Vector(-1, 0, 0), {foot, foot, lip, lip})

	-- the rim, the outside and the underside
	local ox0, ox1, oy0, oy1 = grid.left, grid.right, grid.near, grid.far
	local top, outer, low = Shade(fc, 1), Shade(fc, 0.78), Shade(fc, 0.5)

	Quad(frame, {ox0, oy1, WALL}, {ox1, oy1, WALL}, {x1, y1, WALL}, {x0, y1, WALL}, UP, top)
	Quad(frame, {ox0, oy0, WALL}, {ox1, oy0, WALL}, {x1, y0, WALL}, {x0, y0, WALL}, UP, top)
	Quad(frame, {ox0, oy0, WALL}, {x0, y0, WALL}, {x0, y1, WALL}, {ox0, oy1, WALL}, UP, top)
	Quad(frame, {ox1, oy0, WALL}, {x1, y0, WALL}, {x1, y1, WALL}, {ox1, oy1, WALL}, UP, top)

	Quad(frame, {ox0, oy0, -BELOW}, {ox1, oy0, -BELOW}, {ox1, oy0, WALL}, {ox0, oy0, WALL}, Vector(0, -1, 0),
		{low, low, outer, outer})
	Quad(frame, {ox0, oy1, -BELOW}, {ox1, oy1, -BELOW}, {ox1, oy1, WALL}, {ox0, oy1, WALL}, Vector(0, 1, 0),
		{low, low, outer, outer})
	Quad(frame, {ox0, oy0, -BELOW}, {ox0, oy1, -BELOW}, {ox0, oy1, WALL}, {ox0, oy0, WALL}, Vector(-1, 0, 0),
		{low, low, outer, outer})
	Quad(frame, {ox1, oy0, -BELOW}, {ox1, oy1, -BELOW}, {ox1, oy1, WALL}, {ox1, oy0, WALL}, Vector(1, 0, 0),
		{low, low, outer, outer})
	Quad(frame, {ox0, oy0, -BELOW}, {ox1, oy0, -BELOW}, {ox1, oy1, -BELOW}, {ox0, oy1, -BELOW}, Vector(0, 0, -1), low)

	if (grid.pocket) then
		Box(frame, grid.dividerLeft, y0, grid.dividerLeft + DIVIDER, y1, 0, DIVIDER_HEIGHT, fc)
	end

	return BuildMesh(lining), BuildMesh(frame), CaseMaterial(style.lining), CaseMaterial(style.frame)
end

--- Sets the case's grids (left to right) and lays them out: the cell size, each tray's place and its meshes.
-- Objects in a grid that is gone are dropped.
function CASE:SetGrids(grids)
	self:FreeMeshes()

	local cells, fixed, rows = 0, 0, 1

	for _, grid in ipairs(grids) do
		cells = cells + grid.w + (grid.pocket and POCKET or 0)
		fixed = fixed + RIM * 2 + (grid.pocket and DIVIDER or 0)
		rows = math.max(rows, grid.h)
	end

	fixed = fixed + GAP * (#grids - 1)

	local width = #grids > 1 and WIDTH_PAIR or WIDTH
	local cell = math.Clamp(math.min((width - fixed) / cells, (DEPTH - RIM * 2) / rows), CELL_MIN, CELL_MAX)
	local total = cells * cell + fixed
	local x = -total * 0.5

	self.cell = cell
	self.grids = {}
	self.gridByID = {}
	self.bounds = {left = x, right = -x, near = 0, far = 0}

	for index, source in ipairs(grids) do
		local grid = table.Copy(source)
		local depth = grid.h * cell
		local pocketWidth = grid.pocket and POCKET * cell or 0
		-- a pocket is on the outer side: the left of the first of two trays, the right otherwise
		local bPocketLeft = grid.pocket and index == 1 and #grids > 1

		grid.left = x
		grid.right = x + RIM * 2 + grid.w * cell + (grid.pocket and pocketWidth + DIVIDER or 0)
		grid.innerLeft, grid.innerRight = grid.left + RIM, grid.right - RIM
		grid.far, grid.near = depth * 0.5 + RIM, -depth * 0.5 - RIM
		grid.innerFar, grid.innerNear = depth * 0.5, -depth * 0.5
		grid.cellsLeft = bPocketLeft and grid.innerLeft + pocketWidth + DIVIDER or grid.innerLeft
		grid.cellsRight = grid.cellsLeft + grid.w * cell
		grid.cellsFar, grid.cellsNear = grid.innerFar, grid.innerNear

		if (grid.pocket) then
			grid.pocketLeft = bPocketLeft and grid.innerLeft or grid.cellsRight + DIVIDER
			grid.pocketRight = grid.pocketLeft + pocketWidth
			grid.dividerLeft = bPocketLeft and grid.cellsLeft - DIVIDER or grid.cellsRight
		end

		grid.lining, grid.frame, grid.liningMaterial, grid.frameMaterial = BuildTray(grid, cell)

		self.bounds.near = math.min(self.bounds.near, grid.near)
		self.bounds.far = math.max(self.bounds.far, grid.far)
		self.grids[index] = grid
		self.gridByID[grid.id] = grid

		x = grid.right + GAP
	end

	-- objects are posed for the cell size; those whose grid went are dropped
	local kept = {}

	for _, object in ipairs(self.objects) do
		if (self.gridByID[object.grid]) then
			object.pose = nil
			kept[#kept + 1] = object
		else
			self:RemoveObject(object)

			if (self.byKey) then
				self.byKey[object.key] = nil
			end

			if (self.carry and self.carry.object == object) then
				self.carry = nil
			end
		end
	end

	self.objects = kept
	self:Occupy()
end

function CASE:FreeMeshes()
	for _, grid in ipairs(self.grids or {}) do
		if (grid.lining) then grid.lining:Destroy() end
		if (grid.frame) then grid.frame:Destroy() end

		grid.lining, grid.frame = nil, nil
	end
end

-- What each cell holds, for the aim: grid.cells[x][y] = object, grid.pocketObject.
function CASE:Occupy()
	for _, grid in ipairs(self.grids) do
		grid.cells = {}
		grid.pocketObject = nil
	end

	for _, object in ipairs(self.objects) do
		local grid = self.gridByID[object.grid]

		if (object.pocket) then
			grid.pocketObject = object
		else
			for x = object.x, object.x + object.w - 1 do
				grid.cells[x] = grid.cells[x] or {}

				for y = object.y, object.y + object.h - 1 do
					grid.cells[x][y] = object
				end
			end
		end
	end
end

-- The middle of an object's cells (or its pocket's near half), in the case's own space.
function CASE:Footprint(object, grid, x, y)
	grid = grid or self.gridByID[object.grid]

	-- a loose thing in a pocket lies in its near part, about a cell in size
	if (object.pocket) then
		local depth = grid.innerFar - grid.innerNear

		return (grid.pocketLeft + grid.pocketRight) * 0.5, grid.innerNear + depth * 0.3,
			math.min(grid.pocketRight - grid.pocketLeft, self.cell), math.min(depth * 0.5, self.cell)
	end

	local cell = self.cell

	x, y = x or object.x, y or object.y

	return grid.cellsLeft + (x - 1 + object.w * 0.5) * cell, grid.cellsFar - (y - 1 + object.h * 0.5) * cell,
		object.w * cell, object.h * cell
end

local function Determinant(m)
	return m[1][1] * (m[2][2] * m[3][3] - m[2][3] * m[3][2]) - m[1][2] * (m[2][1] * m[3][3] - m[2][3] * m[3][1]) +
		m[1][3] * (m[2][1] * m[3][2] - m[2][2] * m[3][1])
end

--- The matrix that lays a model in its cells, in the case's space with the cells' middle at the origin: its
-- thinnest axis up (its own up when that is nearly as thin, so round and squat things stay on their base), its
-- longest along the longer side of the cells, scaled to fit them and its bounds' centre over their middle, resting
-- on the lining. Returns the matrix and how high it stands.
function worldcase.Pose(mins, maxs, sizeX, sizeY, maxHeight)
	local size = {
		math.max(maxs.x - mins.x, 0.01), math.max(maxs.y - mins.y, 0.01), math.max(maxs.z - mins.z, 0.01)
	}
	local centre = {(mins.x + maxs.x) * 0.5, (mins.y + maxs.y) * 0.5, (mins.z + maxs.z) * 0.5}
	local order = {1, 2, 3}

	table.sort(order, function(a, b)
		if (size[a] != size[b]) then
			return size[a] > size[b]
		end

		return a < b
	end)

	local up = order[3]

	if (size[3] <= size[up] * UPRIGHT) then
		up = 3
	end

	local rest = {}

	for _, axis in ipairs(order) do
		if (axis != up) then
			rest[#rest + 1] = axis
		end
	end

	-- model axis -> the case's axis (1 across, 2 away, 3 up)
	local long, short = rest[1], rest[2]
	local bAcross = sizeX >= sizeY
	local map = {[long] = bAcross and 1 or 2, [short] = bAcross and 2 or 1, [up] = 3}
	local rotation = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}}

	for axis = 1, 3 do
		rotation[map[axis]][axis] = 1
	end

	-- a mirror image is turned into a rotation by laying the short side the other way
	if (Determinant(rotation) < 0) then
		rotation[map[short]][short] = -1
	end

	local along = {}

	for axis = 1, 3 do
		along[map[axis]] = size[axis]
	end

	local scale = math.min(sizeX * FILL / along[1], sizeY * FILL / along[2], maxHeight / along[3], MAX_SCALE)
	local rows = {}

	for i = 1, 3 do
		local r = rotation[i]
		local moved = (r[1] * centre[1] + r[2] * centre[2] + r[3] * centre[3]) * scale

		rows[i] = {r[1] * scale, r[2] * scale, r[3] * scale, (i == 3 and along[3] * scale * 0.5 or 0) - moved}
	end

	rows[4] = {0, 0, 0, 1}

	return Matrix(rows), along[3] * scale
end

-- Makes an object's model, or nothing (it is drawn as a plain block) when the model is missing or broken.
local function CreateModel(object)
	local model = object.model

	-- the file, not util.IsValidModel: on the client that is false for any model not loaded yet
	if (!isstring(model) or !model:lower():find("^models/.+%.mdl$") or !file.Exists(model, "GAME")) then
		return
	end

	local entity = ClientsideModel(model, RENDERGROUP_OPAQUE)

	if (!IsValid(entity)) then
		return
	end

	entity:SetNoDraw(true)
	entity:SetSkin(tonumber(object.skin) or 0)

	if (isstring(object.material) and object.material != "") then
		entity:SetMaterial(object.material)
	end

	if (istable(object.bodygroups)) then
		for name, value in pairs(object.bodygroups) do
			local index = isnumber(name) and name or entity:FindBodygroupByName(tostring(name))

			if (index and index >= 0) then
				entity:SetBodygroup(index, tonumber(value) or 0)
			end
		end
	end

	worldcase.models[entity] = true

	return entity
end

local function Look(object)
	return tostring(object.model) .. "|" .. tostring(object.skin) .. "|" .. tostring(object.material) .. "|" ..
		(istable(object.bodygroups) and util.TableToJSON(object.bodygroups) or "")
end

function CASE:RemoveObject(object)
	if (IsValid(object.entity)) then
		worldcase.models[object.entity] = nil
		object.entity:Remove()
	end

	object.entity = nil
end

--- Replaces the objects. One whose key stays keeps its model (a new one is made only when its look changed), and
-- keeps showing where it was put while the server has not answered yet.
function CASE:SetObjects(list)
	local byKey, objects = {}, {}

	for _, given in ipairs(list) do
		local grid = self.gridByID[given.grid]

		if (grid and given.key != nil and !byKey[given.key]) then
			local object = self.byKey[given.key]
			local look = Look(given)

			if (object and object.look != look) then
				self:RemoveObject(object)
				object = nil
			end

			if (!object) then
				object = {look = look, lift = 0}
				object.entity = CreateModel(given)
			end

			-- where it was put has arrived, or it went: it is shown where it is
			if (object.pending and (object.grid != given.grid or object.x != given.x or object.y != given.y)) then
				object.pending = nil
			end

			if (object.w != (given.w or 1) or object.h != (given.h or 1) or object.grid != given.grid or
				object.pocket != given.pocket) then
				object.pose = nil
			end

			for key, value in pairs(given) do
				object[key] = value
			end

			object.w, object.h = given.w or 1, given.h or 1
			byKey[given.key] = object
			objects[#objects + 1] = object
		end
	end

	for key, object in pairs(self.byKey) do
		if (!byKey[key]) then
			self:RemoveObject(object)

			if (self.carry and self.carry.object == object) then
				self.carry = nil
			end
		end
	end

	self.byKey = byKey
	self.objects = objects
	self:Occupy()
end

function CASE:GetObject(key)
	return self.byKey[key]
end

function CASE:GetObjects()
	return self.objects
end

local boundsCache = {}

-- The bounds a model is laid out by: its render bounds, or its collision hull where those are far larger than the hull
-- (some models declare bounds many times what they draw: the charcoal lump's are 140 units across). Found once per
-- model.
local function ModelBounds(entity)
	local model = entity:GetModel()
	local cached = boundsCache[model]

	if (cached) then
		return cached[1], cached[2]
	end

	local mins, maxs = entity:GetModelRenderBounds()

	if (!mins) then
		return
	end

	if (entity:PhysicsInit(SOLID_VPHYSICS)) then
		local physics = entity:GetPhysicsObject()

		if (IsValid(physics)) then
			local low, high = physics:GetAABB()
			local hull, drawn = high - low, maxs - mins

			if (hull.x > 0.1 and hull.y > 0.1 and hull.z > 0.1 and
				(drawn.x > hull.x * 3 or drawn.y > hull.y * 3 or drawn.z > hull.z * 3)) then
				mins, maxs = low, high
			end
		end

		entity:PhysicsDestroy()
	end

	boundsCache[model] = {mins, maxs}

	return mins, maxs
end

-- Poses an object for its cells, once.
function CASE:PoseObject(object)
	if (object.pose) then
		return
	end

	local _, _, sizeX, sizeY = self:Footprint(object)
	local entity = object.entity
	local mins, maxs

	if (IsValid(entity)) then
		mins, maxs = ModelBounds(entity)
	end

	if (!mins or (maxs - mins):LengthSqr() < 0.01) then
		-- a plain block in its cells
		object.block = true
		object.height = math.min(self.cell * 0.4, 1.2)
		object.pose = Matrix()

		return
	end

	object.block = nil
	object.pose, object.height = worldcase.Pose(mins, maxs, sizeX, sizeY, math.max(self.cell * 1.1, 2.6))
end

-- The case's axes, centre and the world placement for this frame: held at the waist or toward the anchor.
function CASE:Update(client)
	local eye, view = ix.worldui.GetView(client)
	local yaw

	if (self.bHeld) then
		yaw = self.heldYaw or view.y

		local difference = math.AngleDifference(view.y, yaw)

		-- held still while something is carried over it (so the aim can leave it to drop the thing) or an item's
		-- options are open beside it (so the aim can reach them)
		if (self.carry or (self.following and self.following.panel:IsOpen())) then
			difference = 0
		end

		-- beside the body in third person, it is turned toward only once the view is well past it
		local follow = client:ShouldDrawLocalPlayer() and THIRD_FOLLOW or HELD_FOLLOW

		if (difference > follow) then
			yaw = yaw + difference - follow
		elseif (difference < -follow) then
			yaw = yaw + difference + follow
		end
	else
		if (IsValid(self.anchor)) then
			self.anchorCenter = self.anchor:WorldSpaceCenter()
		end

		yaw = self.anchorCenter and (self.anchorCenter - client:EyePos()):Angle().y or view.y
	end

	self.heldYaw = math.NormalizeAngle(yaw)

	local held = Angle(0, self.heldYaw, 0)
	local forward, right = held:Forward(), held:Right()
	local ahead = self.bHeld and (#self.grids > 1 and PAIR_AHEAD or HELD_AHEAD) or ANCHOR_AHEAD
	local center

	local scale = 1

	self.bThirdPerson = client:ShouldDrawLocalPlayer()

	-- seen from the camera behind, it is larger, as though nearer
	if (self.bThirdPerson) then
		scale = THIRD_SCALE
		center = client:EyePos() + forward * (ahead - HELD_AHEAD + THIRD_AHEAD) + right * THIRD_SIDE - UP * THIRD_BELOW
	else
		center = client:EyePos() + forward * ahead - UP * HELD_BELOW
	end

	-- coming up into the hands
	local rise = math.Clamp((RealTime() - self.openedAt) / RISE, 0, 1)

	center = center - UP * (1 - rise) ^ 2 * 8

	local tilt = math.rad(TILT)

	self.center = center
	self.scale = scale
	self.ax = right
	self.ay = forward * math.cos(tilt) + UP * math.sin(tilt)
	self.az = UP * math.cos(tilt) - forward * math.sin(tilt)
	self.viewOrigin, self.viewAngles = eye, view

	local ax, ay, az = self.ax * scale, self.ay * scale, self.az * scale

	self.matrix:SetUnpacked(
		ax.x, ay.x, az.x, center.x,
		ax.y, ay.y, az.y, center.y,
		ax.z, ay.z, az.z, center.z,
		0, 0, 0, 1)
	self.toEntity:SetUnpacked(
		1, 0, 0, -center.x,
		0, 1, 0, -center.y,
		0, 0, 1, -center.z,
		0, 0, 0, 1)
end

--- A point in the case's own space, in the world.
function CASE:ToWorld(x, y, z)
	return self.center + (self.ax * x + self.ay * y + self.az * z) * self.scale
end

-- Where the aim crosses the case at the height it is read, in the case's own space, or nil.
function CASE:AimPoint()
	local origin, angles = self.viewOrigin, self.viewAngles

	if (!origin) then
		return
	end

	local direction = angles:Forward()
	local offset = (origin - self.center) / self.scale
	local ox, oy, oz = offset:Dot(self.ax), offset:Dot(self.ay), offset:Dot(self.az)
	local dx, dy, dz = direction:Dot(self.ax), direction:Dot(self.ay), direction:Dot(self.az)

	if (dz > -0.0001) then
		return
	end

	local distance = (HIT - oz) / dz

	if (distance <= 0) then
		return
	end

	return ox + dx * distance, oy + dy * distance
end

-- The place under a point of the case's space (see the top of the file).
function CASE:PlaceAt(x, y)
	if (!x) then
		return {off = true}
	end

	local cell = self.cell

	for _, grid in ipairs(self.grids) do
		if (x >= grid.cellsLeft and x < grid.cellsRight and y <= grid.cellsFar and y > grid.cellsNear) then
			local cx = math.floor((x - grid.cellsLeft) / cell) + 1
			local cy = math.floor((grid.cellsFar - y) / cell) + 1

			return {grid = grid.id, cx = cx, cy = cy, over = grid.cells[cx] and grid.cells[cx][cy]}
		end

		if (grid.pocket and x >= grid.pocketLeft and x < grid.pocketRight and y <= grid.innerFar and
			y > grid.innerNear) then
			return {grid = grid.id, pocket = true, over = grid.pocketObject}
		end
	end

	local bounds = self.bounds
	local margin = OFF * cell

	if (x < bounds.left - margin or x > bounds.right + margin or y < bounds.near - margin or y > bounds.far + margin) then
		return {off = true}
	end

	return {edge = true, bOnCase = x >= bounds.left and x <= bounds.right and y >= bounds.near and y <= bounds.far}
end

-- A short text naming a place, to tell whether it changed.
local function PlaceKey(place)
	if (!place) then
		return ""
	end

	return tostring(place.grid) .. "|" .. tostring(place.x) .. "|" .. tostring(place.y) .. "|" ..
		tostring(place.over and place.over.key) .. "|" .. tostring(place.off) .. "|" .. tostring(place.pocket) .. "|" ..
		tostring(place.edge)
end

function CASE:UpdateAim()
	local x, y = self:AimPoint()
	local place = self:PlaceAt(x, y)

	self.aimX, self.aimY = x, y
	self.place = place
	self.bAimOnCase = place.grid != nil or (place.edge and place.bOnCase) or false
	self.aimed = !self.carry and place.over or nil

	local carry = self.carry

	if (!carry) then
		return
	end

	local target

	if (place.grid and place.cx) then
		target = {grid = place.grid, x = place.cx - carry.dx, y = place.cy - carry.dy, cx = place.cx, cy = place.cy}

		if (place.over and place.over != carry.object) then
			target.over = place.over
		end
	elseif (place.off) then
		target = {off = true}
	else
		target = {edge = true, grid = place.grid, pocket = place.pocket}
	end

	local key = PlaceKey(target)

	if (key != carry.key) then
		carry.key = key
		carry.place = target

		if (self.info.Evaluate) then
			carry.result, carry.hint = self.info.Evaluate(self, carry.object, target)
		else
			carry.result, carry.hint = nil, nil
		end
	end
end

--- The object under the aim (nil while carrying), and the place under the aim.
function CASE:GetAimed()
	return self.aimed, self.place
end

--- The carried object, the place it would go and what letting go there would do (Evaluate), or nil.
function CASE:GetCarry()
	local carry = self.carry

	if (carry) then
		return carry.object, carry.place, carry.result, carry.hint
	end
end

--- Whether the aim is on the case (a cell, a pocket or its frame).
function CASE:IsAimedAt()
	return !self.bClosed and self.bAimOnCase == true
end

--- A world point to aim at: an object (its middle), {grid = id, x = column, y = row} (that cell's middle),
-- {grid = id, pocket = true} or {off = true} (a little way off the case's right side).
function CASE:GetAimPos(target)
	if (!self.center) then
		return
	end

	if (target.key != nil and self.byKey[target.key] == target) then
		local x, y = self:Footprint(target)

		return self:ToWorld(x, y, HIT)
	elseif (target.off) then
		return self:ToWorld(self.bounds.right + (OFF + 1.2) * self.cell, 0, HIT)
	end

	local grid = self.gridByID[target.grid]

	if (!grid) then
		return
	end

	if (target.pocket) then
		return self:ToWorld((grid.pocketLeft + grid.pocketRight) * 0.5, grid.innerNear + (grid.innerFar - grid.innerNear) * 0.3,
			HIT)
	end

	return self:ToWorld(grid.cellsLeft + (target.x - 0.5) * self.cell, grid.cellsFar - (target.y - 0.5) * self.cell, HIT)
end

--- Makes an ix.worldui panel at a `position` follow an object of the case while both are open (or stay at `place`
-- of the case, a place as GetAimPos takes, when given: where a thing was let go).
function CASE:FollowObject(panel, object, place)
	self.following = panel and {panel = panel, object = object, place = place} or nil
end

-- Whether the button a press came from is still held (a tool's virtual press until it lets go).
local function IsDown(state)
	if (state.bVirtual) then
		return state.bDown == true
	end

	return state.button != nil and input.IsButtonDown(state.button)
end

local function ButtonFor(code, bind)
	if (isnumber(code) and code > 0) then
		return code
	end

	local binding = input.LookupBinding(bind)
	code = binding and input.GetKeyCode(binding)

	return (code and code > 0) and code or nil
end

--- A press of Use ("use"), attack ("attack") or right click ("attack2") on the case, from a bind (with its button,
-- watched until it is let go) or, `bVirtual`, from a tool that lets go with case:Release(kind).
function CASE:Press(kind, code, bVirtual)
	if (self.bClosed) then
		return
	end

	if (kind == "use") then
		if (self.use) then
			return
		end

		-- an item's options beside the case: Use chooses its aimed row, or puts it away
		local panel = ix.worldui.GetOpen()

		if (panel) then
			if (!panel:Select() and !panel:IsAimedAt()) then
				panel:Close()
			end

			return
		end

		local object = self.aimed

		if (!object) then
			-- Use with the aim off the case puts it away
			if (!self.bAimOnCase) then
				self:Close(reasons.closed)
			end

			return
		end

		self.use = {object = object, start = RealTime(), button = ButtonFor(code, "+use"), bVirtual = bVirtual,
			bDown = true}
	elseif (kind == "attack") then
		local object, place = self.aimed, self.place

		if (self.carry or !object or !place.cx and !place.pocket) then
			return
		end

		if (self.info.CanCarry and self.info.CanCarry(self, object) == false) then
			return
		end

		self.carry = {
			object = object,
			dx = place.cx and place.cx - object.x or 0,
			dy = place.cy and place.cy - object.y or 0,
			button = ButtonFor(code, "+attack"),
			bVirtual = bVirtual,
			bDown = true
		}

		object.pending = nil
		self.aimed = nil
		self:UpdateAim()
		surface.PlaySound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 3) .. ".wav")
	elseif (kind == "attack2") then
		if (self.carry) then
			self.carry = nil
			return
		end

		if (!(self.info.OnBack and self.info.OnBack(self) == true)) then
			self:Close(reasons.closed)
		end
	end
end

--- Lets go of a virtual press (case:Press with bVirtual).
function CASE:Release(kind)
	local state = kind == "use" and self.use or (kind == "attack" and self.carry)

	if (state and state.bVirtual) then
		state.bDown = false
		self:UpdateButtons()
	end
end

-- Use held or let go, a carried object let go.
function CASE:UpdateButtons()
	-- the game window lost the keyboard and mouse (alt-tab): a button is no longer known to be held, so nothing is
	-- done with it; what was carried goes back where it was, and a held Use does nothing
	if (!system.HasFocus()) then
		if ((self.carry and !self.carry.bVirtual) or (self.use and !self.use.bVirtual)) then
			if (self.carry and !self.carry.bVirtual) then
				self.carry = nil
			end

			if (self.use and !self.use.bVirtual) then
				self.use = nil
			end

			self:UpdateAim()
		end

		return
	end

	local use = self.use

	if (use) then
		if (!IsDown(use)) then
			self.use = nil

			if (use.bOpened) then
				-- let go on a row of the options: that row; anywhere else: put them away. Not when a row was already
				-- chosen while it was held.
				local panel = use.panel

				if (panel and panel:IsOpen() and (panel.selections or 0) == use.selections and !panel:Select()) then
					panel:Close()
				end
			elseif (self.aimed == use.object and self.info.OnTap) then
				self.info.OnTap(self, use.object)
			end
		elseif (!use.bOpened and RealTime() - use.start >= self:GetHoldTime()) then
			use.bOpened = true

			if (self.aimed == use.object and self.info.OnHold) then
				use.panel = self.info.OnHold(self, use.object)
				use.selections = use.panel and use.panel.selections or 0
			end
		end
	end

	local carry = self.carry

	if (carry and !IsDown(carry)) then
		self.carry = nil

		local object, place, result = carry.object, carry.place, carry.result

		-- shown where it was put until the server answers (SetObjects), or it would jump back and forth; not when
		-- OnRelease says nothing was asked
		if (result and self.info.OnRelease and self.info.OnRelease(self, object, place, result) != false) then
			object.pending = {place = place, result = result, expires = RealTime() + 1}
			surface.PlaySound("physics/cardboard/cardboard_box_impact_soft" .. math.random(4, 7) .. ".wav")
		end

		self:UpdateAim()
	end
end

function CASE:GetHoldTime()
	local interaction = ix.plugin.list.interaction

	return interaction and interaction.holdTime or 0.35
end

function CASE:Close(reason)
	if (self.bClosed) then
		return
	end

	self.bClosed = true
	self.closeReason = reason or (reasons and reasons.closed) or "closed"
	self.carry, self.use, self.aimed = nil, nil, nil

	for _, object in ipairs(self.objects) do
		self:RemoveObject(object)
	end

	self:FreeMeshes()

	if (worldcase.open == self) then
		worldcase.open = nil
	end

	local following = self.following

	if (following and following.panel:IsOpen()) then
		following.panel:Close()
	end

	if (self.info.OnClose) then
		self.info.OnClose(self, self.closeReason)
	end
end

-- The reason the case should close now, or nil.
function CASE:ShouldClose(client)
	if (!self.bHeld and !IsValid(self.anchor)) then
		return reasons.anchor
	end

	if (!client:Alive()) then
		return reasons.dead
	end

	if (IsValid(Entity(client:GetLocalVar("ragdoll", 0))) or client:IsRestricted()) then
		return reasons.incapacitated
	end

	local character = client:GetCharacter()

	if (!character or character:GetID() != self.characterID or
		(IsValid(ix.gui.characterMenu) and !ix.gui.characterMenu:IsClosing()) or
		(IsValid(ix.gui.menu) and !ix.gui.menu.bClosing) or vgui.CursorVisible() or gui.IsGameUIVisible()) then
		return reasons.interrupted
	end

	if (!self.bHeld) then
		local eye = client:EyePos()

		if (eye:DistToSqr(self.anchor:NearestPoint(eye)) > self.reach * self.reach) then
			return reasons.reach
		end
	end

	if (RealTime() - self.openedAt > GRACE and self.center and !self.carry) then
		local aim = self.viewAngles:Forward()
		local toCase = (self.center - self.viewOrigin):GetNormalized()
		local bAway = aim:Dot(toCase) < self.lookAway

		if (bAway and !self.bHeld and self.anchorCenter) then
			bAway = aim:Dot((self.anchorCenter - self.viewOrigin):GetNormalized()) < self.lookAway
		end

		if (bAway) then
			return reasons.lookedAway
		end
	end
end

-- Eases a carried or aimed object toward where it is shown this frame (numbers only: no allocation).
function CASE:UpdateObject(object, step)
	self:PoseObject(object)

	local grid = self.gridByID[object.grid]
	local x, y = self:Footprint(object, grid)
	local z = 0
	local carry = self.carry
	local pending = object.pending

	if (pending and RealTime() > pending.expires) then
		object.pending, pending = nil, nil
	end

	object.hidden = nil

	if (carry and carry.object == object) then
		local place = carry.place

		if (place and place.grid and place.x) then
			x, y = self:Footprint(object, self.gridByID[place.grid], place.x, place.y)
		elseif (self.aimX) then
			x, y = self.aimX, self.aimY
		end

		z = CARRY_LIFT
	elseif (pending) then
		local place = pending.place

		-- a move shows it where it was put, a drop hides it; a combine leaves it where it was until the server says
		-- what is left of it (all of it merged, part of it, or nothing)
		if (pending.result == "move" and place.grid and place.x) then
			x, y = self:Footprint(object, self.gridByID[place.grid], place.x, place.y)
		elseif (pending.result == "drop") then
			object.hidden = true
		end
	end

	local target = (self.aimed == object or (carry and carry.place and carry.place.over == object)) and 1 or 0

	object.lift = object.lift + (target - object.lift) * math.min(step * 14, 1)
	z = z + object.lift * LIFT

	if (!object.vx or object.snap) then
		object.vx, object.vy, object.vz, object.snap = x, y, z, nil
	else
		local t = math.min(step * 18, 1)

		object.vx = object.vx + (x - object.vx) * t
		object.vy = object.vy + (y - object.vy) * t
		object.vz = object.vz + (z - object.vz) * t
	end
end

-- The world's light where the case is: the tray's colour (gamma) and the models' ambient cube (linear), with a floor.
function CASE:UpdateLight()
	local center = self.center
	local top = render.ComputeLighting(center, UP) + render.ComputeDynamicLighting(center, UP)
	local toEye = (self.viewOrigin - center):GetNormalized()
	local front = render.ComputeLighting(center, toEye) + render.ComputeDynamicLighting(center, toEye)
	local light = top * 0.55 + front * 0.45

	local function Gamma(value)
		return math.Clamp(math.max(value, 0) ^ (1 / 2.2), TRAY_FLOOR, 1)
	end

	self.color:SetUnpacked(Gamma(light.x), Gamma(light.y), Gamma(light.z))
	self.lightTop = top
	self.lightFront = front
end

local cube = {BOX_TOP, BOX_BOTTOM, BOX_FRONT, BOX_BACK, BOX_LEFT, BOX_RIGHT}

local function ModelLight(light, factor)
	return math.max(light.x * factor, MODEL_FLOOR * factor), math.max(light.y * factor, MODEL_FLOOR * factor),
		math.max(light.z * factor, MODEL_FLOOR * factor)
end

function CASE:Draw()
	if (!self.center) then
		return
	end

	local matrix = self.matrix

	-- in first person it is drawn over the world, as the hands would be, so a wall close in front never cuts into
	-- it; seen from behind, the character's own body stands in front of it as it would
	if (!self.bThirdPerson) then
		render.ClearDepth()
	end

	-- the trays
	cam.PushModelMatrix(matrix)
		for _, grid in ipairs(self.grids) do
			if (grid.lining) then
				grid.liningMaterial:SetVector("$color", self.color)
				grid.frameMaterial:SetVector("$color", self.color)

				render.SetMaterial(grid.liningMaterial)
				grid.lining:Draw()
				render.SetMaterial(grid.frameMaterial)
				grid.frame:Draw()
			end
		end

		self:DrawMarks()
	cam.PopModelMatrix()

	-- the things in them, lit as the world is there
	render.SuppressEngineLighting(true)

	local top, front = self.lightTop, self.lightFront
	local side = (top + front) * 0.5

	render.SetModelLighting(BOX_TOP, ModelLight(top, 1))
	render.SetModelLighting(BOX_BOTTOM, ModelLight(side, 0.35))

	for i = 3, 6 do
		render.SetModelLighting(cube[i], ModelLight(side, 0.8))
	end

	local carried = self.carry and self.carry.object

	for _, object in ipairs(self.objects) do
		-- placed by the next Think when it has only just arrived
		if (!object.hidden and object.vx) then
			local bCarried = object == carried
			local bRefused = bCarried and !self.carry.result

			if (bRefused) then
				render.SetColorModulation(1, 0.42, 0.36)
			elseif (bCarried and self.carry.result == "drop") then
				render.SetColorModulation(0.7, 0.7, 0.7)
			end

			self:DrawObject(object)

			if (bCarried) then
				render.SetColorModulation(1, 1, 1)
			end
		end
	end

	render.SuppressEngineLighting(false)
end

-- One object, moved into place with its model's own matrix (the model stays at the case's centre).
function CASE:DrawObject(object)
	local entity = object.entity

	self:PoseObject(object)

	self.vector:SetUnpacked(object.vx, object.vy, object.vz)
	self.offset:Identity()
	self.offset:SetTranslation(self.vector)

	if (object.block or !IsValid(entity)) then
		local _, _, sizeX, sizeY = self:Footprint(object)
		local halfX, halfY = sizeX * FILL * 0.5, sizeY * FILL * 0.5
		local height = object.height or 1

		cam.PushModelMatrix(self.matrix)
			cam.PushModelMatrix(self.offset, true)
				blockMaterial:SetVector("$color", self.color)
				render.SetMaterial(blockMaterial)
				render.DrawBox(vector_origin, angle_zero, Vector(-halfX, -halfY, 0), Vector(halfX, halfY, height),
					Color(128, 124, 116))
			cam.PopModelMatrix()
		cam.PopModelMatrix()

		return
	end

	local full = self.full

	full:Set(self.toEntity)
	full:Mul(self.matrix)
	full:Mul(self.offset)
	full:Mul(object.pose)

	entity:SetPos(self.center)
	entity:SetAngles(angle_zero)
	entity:EnableMatrix("RenderMultiply", full)
	entity:SetupBones()
	entity:DrawModel()
end

local function DrawQuad(x0, y0, x1, y1, z, color)
	render.DrawQuad(Vector(x0, y0, z), Vector(x1, y0, z), Vector(x1, y1, z), Vector(x0, y1, z), color)
end

-- The aimed empty cell, faintly, and where a carried thing would go: its cells, pale where it fits and red where
-- it does not.
function CASE:DrawMarks()
	local place = self.place
	local cell = self.cell

	render.SetColorMaterial()

	local carry = self.carry

	if (carry) then
		local target = carry.place

		if (target and target.grid and target.x) then
			local grid = self.gridByID[target.grid]
			local object = carry.object
			local x0 = math.max(grid.cellsLeft + (target.x - 1) * cell, grid.cellsLeft)
			local x1 = math.min(grid.cellsLeft + (target.x - 1 + object.w) * cell, grid.cellsRight)
			local y1 = math.min(grid.cellsFar - (target.y - 1) * cell, grid.cellsFar)
			local y0 = math.max(grid.cellsFar - (target.y - 1 + object.h) * cell, grid.cellsNear)

			if (target.over) then
				x0, y0, x1, y1 = self:FootprintRect(target.over)
			end

			if (x1 > x0 and y1 > y0) then
				DrawQuad(x0, y0, x1, y1, 0.04, carry.result and COLOR_FITS or COLOR_REFUSED)
			end
		end

		return
	end

	if (place and place.grid and place.cx and !place.over) then
		local grid = self.gridByID[place.grid]
		local x0 = grid.cellsLeft + (place.cx - 1) * cell
		local y1 = grid.cellsFar - (place.cy - 1) * cell

		DrawQuad(x0, y1 - cell, x0 + cell, y1, 0.04, COLOR_AIM)
	elseif (self.aimed and !self.aimed.hidden) then
		-- the cells of the thing aimed at, faintly, so its label is plainly its own
		local x0, y0, x1, y1 = self:FootprintRect(self.aimed)

		DrawQuad(x0, y0, x1, y1, 0.04, COLOR_AIM_THING)
	end
end

-- An object's cells as a rectangle of the case's space: left, near, right, far.
function CASE:FootprintRect(object)
	local x, y, sizeX, sizeY = self:Footprint(object)

	return x - sizeX * 0.5, y - sizeY * 0.5, x + sizeX * 0.5, y + sizeY * 0.5
end

-- The aimed (or carried) object's name and amount, on a small label just above it, square to the view.
function CASE:DrawLabel()
	local object = self.carry and self.carry.object or self.aimed

	if (!object or object.hidden or !object.vx or !object.label) then
		return
	end

	local detail = object.detail

	if (self.carry and self.carry.object == object) then
		detail = self.carry.hint or detail
	end

	local top = object.vz + (object.height or 1) + 0.6
	local _, _, _, sizeY = self:Footprint(object)
	-- at the far edge of its cells, so the label never covers the thing itself
	local position = self:ToWorld(object.vx, object.vy + sizeY * 0.5, top)
	local view = self.viewAngles
	local distance = math.max(position:Distance(self.viewOrigin), 1)
	local scale = distance * ANGLE_PER_UNIT / resolution * 0.85
	local r = resolution
	local up = view:Up()

	-- just above the thing as seen
	position = position + up * (8 * r * scale)

	local angles = view:Right():AngleEx(-view:Forward())

	surface.SetFont("ixWorldUIRow")
	local labelWidth, labelHeight = surface.GetTextSize(object.label)
	local detailWidth, detailHeight = 0, 0

	if (detail) then
		surface.SetFont("ixWorldUIDetail")
		detailWidth, detailHeight = surface.GetTextSize(detail)
	end

	local padding = 10 * r
	local width = math.max(labelWidth, detailWidth) + padding * 2
	local height = labelHeight + (detail and detailHeight + 2 * r or 0) + padding

	cam.Start3D2D(position, angles, scale)
		cam.IgnoreZ(true)
			draw.RoundedBox(5 * r, -width * 0.5, -height, width, height, COLOR_LABEL_BACK)
			draw.SimpleText(object.label, "ixWorldUIRow", 0, -height + padding * 0.5, COLOR_LABEL, TEXT_ALIGN_CENTER,
				TEXT_ALIGN_TOP)

			if (detail) then
				draw.SimpleText(detail, "ixWorldUIDetail", 0, -height + padding * 0.5 + labelHeight + 2 * r,
					COLOR_LABEL_DETAIL, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			end
		cam.IgnoreZ(false)
	cam.End3D2D()
end

hook.Add("Think", "ixWorldCase", function()
	local case = worldcase.open

	if (!case or case.bClosed) then
		return
	end

	local client = LocalPlayer()

	if (!IsValid(client)) then
		return
	end

	local reason = case:ShouldClose(client)

	if (reason) then
		case:Close(reason)
		return
	end

	resolution = math.Clamp(ScrH() / 1080, 0.6, 2.5)

	case:Update(client)
	case:UpdateAim()
	case:UpdateButtons()

	if (case.bClosed) then
		return
	end

	local step = RealFrameTime()

	for _, object in ipairs(case.objects) do
		case:UpdateObject(object, step)
	end

	-- an item's options stay beside it as the case moves
	local following = case.following

	if (following) then
		if (!following.panel:IsOpen() or !case.byKey[following.object.key]) then
			if (following.panel:IsOpen()) then
				following.panel:Close()
			end

			case.following = nil
		elseif (following.place) then
			following.panel.position = case:GetAimPos(following.place) or following.panel.position
		else
			following.panel.position = case:ToWorld(following.object.vx, following.object.vy, following.object.vz +
				(following.object.height or 1))
		end
	end
end)

hook.Add("PostDrawTranslucentRenderables", "ixWorldCase", function(bDepth, bSkybox)
	local case = worldcase.open

	if (bDepth or bSkybox or !case or case.bClosed or render.GetRenderTarget() != nil) then
		return
	end

	case:UpdateLight()
	case:Draw()
	case:DrawLabel()
end)

-- The weapon never fires and neither hands nor weapon are drawn while the case is in the hands.
hook.Add("CreateMove", "ixWorldCase", function(command)
	if (worldcase.GetOpen()) then
		command:RemoveKey(IN_ATTACK)
		command:RemoveKey(IN_ATTACK2)
	end
end)

hook.Add("PreDrawViewModel", "ixWorldCase", function()
	if (worldcase.GetOpen()) then
		return true
	end
end)

hook.Add("PreDrawPlayerHands", "ixWorldCase", function()
	if (worldcase.GetOpen()) then
		return true
	end
end)
