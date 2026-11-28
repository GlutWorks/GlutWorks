local PLUGIN = PLUGIN

--[[
The carriage newcomers wake in, in its own measures: `u` along it from its back end, `v` across it
from the corridor's outer wall, `z` up from its floor. It is put in the world at a spot and a yaw
(`PLUGIN:ToWorld`), local +u turned to the yaw.

	v
	192 +-------------------------------------------------+
	    | cabin 1   M | cabin 2   M | ...    | vestibule  |   M: each cabin's mirror, on its back end wall
	 68 +---[door]----+---[door]----+--------+            |   cabins: windows in the far wall (v 188)
	    |                corridor                         |   corridor: windows in its outer wall (v 0)
	  0 +---------------------------------------[side door]   the side door opens onto the platform
	    0                                                 u

A newcomer wakes in their cabin facing its mirror, the cabin door shut till they have chosen who they
are there. Pieces are boxes (`ix_arriving_piece`); `kind` says what they are and so how they look.
]]

local layout = {}
PLUGIN.layout = layout

layout.cabins = 4 -- cabins in the carriage
layout.high = 120 -- the ceiling over the floor
layout.thick = 4 -- walls
layout.corridor = 64 -- the corridor's width (v 0..64)
layout.cabinFrom = 68 -- the cabins' inside starts past the corridor wall (v 68..188)
layout.cabinTo = 188
layout.cabinLong = 144 -- each cabin's inside along u; a partition of `thick` between them
layout.vestibule = 112 -- open space at the front end, the side door off it
layout.cabinDoor = {from = 22, to = 70, high = 92} -- along u from the cabin's start (the mirror end, clear of the bench); its height
layout.window = {from = 24, to = 120, low = 44, high = 98} -- a cabin's window, along u from its start
layout.corridorWindow = {from = 28, to = 116, low = 44, high = 98}
layout.sideDoor = {from = 24, to = 80, high = 100} -- along u from the vestibule's start
layout.backdrop = 72 -- how far outside the windows the dark is
layout.step = 56 -- how far the step outside the side door reaches

-- The u where cabin i's inside starts, and where the vestibule starts.
function layout.CabinStart(i)
	return (i - 1) * (layout.cabinLong + layout.thick)
end

function layout.VestibuleStart()
	return layout.cabins * (layout.cabinLong + layout.thick)
end

function layout.Long()
	return layout.VestibuleStart() + layout.vestibule
end

-- Where a newcomer wakes in cabin i (feet, local) and the way they face (local yaw): towards the mirror.
function layout.Bed(i)
	return Vector(layout.CabinStart(i) + 84, (layout.cabinFrom + layout.cabinTo) / 2, 1), 180
end

-- Cabin i's mirror: the middle of its glass and the way it faces (local yaw).
function layout.Mirror(i)
	return Vector(layout.CabinStart(i) + 1.5, (layout.cabinFrom + layout.cabinTo) / 2, 62), 0
end

-- Where someone aboard with no cabin stands: in the corridor.
function layout.Corridor(n)
	local span = layout.VestibuleStart()

	return Vector(span * (0.3 + 0.13 * ((n or 0) % 5)), layout.corridor / 2, 1), 0
end

-- Inside the vestibule, by the side door, and the step past it (local box: whoever stands on the step
-- has stepped off).
function layout.Vestibule()
	local start = layout.VestibuleStart()

	return Vector(start + layout.vestibule / 2, layout.corridor / 2, 1), 270
end

function layout.StepBox()
	local start = layout.VestibuleStart()
	local door = layout.sideDoor

	return Vector(start + door.from, -layout.step, -8), Vector(start + door.to, -layout.thick - 6, layout.high)
end

-- Lamps: where each light hangs (local) and whose it is.
function layout.Lamps()
	local lamps = {}
	local middle = (layout.cabinFrom + layout.cabinTo) / 2

	for i = 1, layout.cabins do
		local start = layout.CabinStart(i)

		lamps[#lamps + 1] = {pos = Vector(start + layout.cabinLong / 2, middle, layout.high - 14), cabin = i}
		lamps[#lamps + 1] = {pos = Vector(start + layout.cabinLong / 2, layout.corridor / 2, layout.high - 10), corridor = true}
	end

	lamps[#lamps + 1] = {
		pos = Vector(layout.VestibuleStart() + layout.vestibule / 2, (layout.cabinTo) / 2, layout.high - 10),
		corridor = true
	}

	return lamps
end

-- Windows: each opening's middle (local) and which side of the carriage it is on (+1 the cabins' far wall,
-- -1 the corridor's outer wall).
function layout.Windows()
	local windows = {}

	for i = 1, layout.cabins do
		local start = layout.CabinStart(i)
		local w, c = layout.window, layout.corridorWindow

		windows[#windows + 1] = {
			pos = Vector(start + (w.from + w.to) / 2, layout.cabinTo + layout.thick / 2, (w.low + w.high) / 2),
			side = 1, cabin = i
		}
		windows[#windows + 1] = {
			pos = Vector(start + (c.from + c.to) / 2, -layout.thick / 2, (c.low + c.high) / 2),
			side = -1
		}
	end

	return windows
end

-- A wall along u between u0 and u1 at v0..v1, from z0 to z1, with holes ({from, to, low, high}, along u,
-- sorted, not overlapping): the boxes that make it.
local function WallAlongU(pieces, kind, u0, u1, v0, v1, z0, z1, holes)
	local u = u0

	for _, hole in ipairs(holes or {}) do
		if (hole.from > u) then
			pieces[#pieces + 1] = {kind = kind, mins = Vector(u, v0, z0), maxs = Vector(hole.from, v1, z1)}
		end

		if (hole.low > z0) then
			pieces[#pieces + 1] = {kind = kind, mins = Vector(hole.from, v0, z0), maxs = Vector(hole.to, v1, hole.low)}
		end

		if (hole.high < z1) then
			pieces[#pieces + 1] = {kind = kind, mins = Vector(hole.from, v0, hole.high), maxs = Vector(hole.to, v1, z1)}
		end

		u = hole.to
	end

	if (u1 > u) then
		pieces[#pieces + 1] = {kind = kind, mins = Vector(u, v0, z0), maxs = Vector(u1, v1, z1)}
	end
end

-- Every piece of the carriage: {kind, mins, maxs} in local measures, plus `cabin` for a cabin's door and
-- `door = "side"` for the side door. Kinds: floor, ceiling, wall, door,
-- glass, dark (the night outside the windows), platform (the wall past the side door), step.
function layout.Pieces()
	local pieces = {}
	local t, high = layout.thick, layout.high
	local long = layout.Long()
	local vestibule = layout.VestibuleStart()

	-- floor and ceiling in a section a cabin long each, and across in a strip over the corridor and one over
	-- the cabins, so each piece is lit by the few lamps nearest it and neighbours agree where they meet
	local sections = {-t}

	for i = 2, layout.cabins do
		sections[#sections + 1] = layout.CabinStart(i)
	end

	sections[#sections + 1] = vestibule
	sections[#sections + 1] = long + t

	for k = 1, #sections - 1 do
		local u0, u1 = sections[k], sections[k + 1]

		for _, across in ipairs({{-t, layout.corridor + t / 2}, {layout.corridor + t / 2, layout.cabinTo + t}}) do
			pieces[#pieces + 1] = {kind = "floor", mins = Vector(u0, across[1], -t), maxs = Vector(u1, across[2], 0)}
			pieces[#pieces + 1] = {kind = "ceiling", mins = Vector(u0, across[1], high), maxs = Vector(u1, across[2], high + t)}
		end
	end

	-- the two end walls
	pieces[#pieces + 1] = {kind = "wall", mins = Vector(-t, 0, 0), maxs = Vector(0, layout.cabinTo, high)}
	pieces[#pieces + 1] = {kind = "wall", mins = Vector(long, 0, 0), maxs = Vector(long + t, layout.cabinTo, high)}

	-- the corridor's outer wall: a window opposite each cabin, the side door in the vestibule
	local outerHoles = {}

	for i = 1, layout.cabins do
		local start, w = layout.CabinStart(i), layout.corridorWindow

		outerHoles[#outerHoles + 1] = {from = start + w.from, to = start + w.to, low = w.low, high = w.high}
	end

	outerHoles[#outerHoles + 1] = {
		from = vestibule + layout.sideDoor.from, to = vestibule + layout.sideDoor.to, low = 0, high = layout.sideDoor.high
	}

	WallAlongU(pieces, "wall", 0, long, -t, 0, 0, high, outerHoles)

	-- the cabins' far wall: a window in each cabin
	local farHoles = {}

	for i = 1, layout.cabins do
		local start, w = layout.CabinStart(i), layout.window

		farHoles[#farHoles + 1] = {from = start + w.from, to = start + w.to, low = w.low, high = w.high}
	end

	WallAlongU(pieces, "wall", 0, long, layout.cabinTo, layout.cabinTo + t, 0, high, farHoles)

	-- the corridor wall: a door into each cabin
	local doorHoles = {}

	for i = 1, layout.cabins do
		local start, d = layout.CabinStart(i), layout.cabinDoor

		doorHoles[#doorHoles + 1] = {from = start + d.from, to = start + d.to, low = 0, high = d.high}
	end

	WallAlongU(pieces, "wall", 0, vestibule, layout.corridor, layout.cabinFrom, 0, high, doorHoles)

	-- partitions between cabins, and the last cabin's wall onto the vestibule
	for i = 1, layout.cabins do
		local at = layout.CabinStart(i) + layout.cabinLong

		pieces[#pieces + 1] = {kind = "wall", mins = Vector(at, layout.cabinFrom, 0), maxs = Vector(at + t, layout.cabinTo, high)}
	end

	-- the doors: each cabin's slides along u over the wall towards the bench end, on the corridor side
	for i = 1, layout.cabins do
		local start, d = layout.CabinStart(i), layout.cabinDoor

		pieces[#pieces + 1] = {
			kind = "door", cabin = i, slide = Vector(d.to - d.from + 4, 0, 0),
			mins = Vector(start + d.from - 2, layout.corridor - 3, 0), maxs = Vector(start + d.to + 2, layout.corridor, d.high + 2)
		}
	end

	pieces[#pieces + 1] = {
		kind = "door", door = "side", slide = Vector(layout.sideDoor.to - layout.sideDoor.from + 4, 0, 0),
		mins = Vector(vestibule + layout.sideDoor.from - 2, 0, 0), maxs = Vector(vestibule + layout.sideDoor.to + 2, 3, layout.sideDoor.high + 2)
	}

	-- glass in every window
	for i = 1, layout.cabins do
		local start, w, c = layout.CabinStart(i), layout.window, layout.corridorWindow

		pieces[#pieces + 1] = {
			kind = "glass", mins = Vector(start + w.from, layout.cabinTo + 1, w.low), maxs = Vector(start + w.to, layout.cabinTo + 2, w.high)
		}
		pieces[#pieces + 1] = {
			kind = "glass", mins = Vector(start + c.from, -2, c.low), maxs = Vector(start + c.to, -1, c.high)
		}
	end

	-- the night outside: a dark box round the carriage, its wall on the side door's side the platform's
	-- while the train stands (ix_arriving_piece draws it dark while it rides)
	local back = layout.backdrop

	pieces[#pieces + 1] = {kind = "platform", mins = Vector(-back, -back - t, -back), maxs = Vector(long + back, -back, high + back)}
	pieces[#pieces + 1] = {
		kind = "dark", mins = Vector(-back, layout.cabinTo + back, -back), maxs = Vector(long + back, layout.cabinTo + back + t, high + back)
	}
	pieces[#pieces + 1] = {kind = "dark", mins = Vector(-back - t, -back, -back), maxs = Vector(-back, layout.cabinTo + back, high + back)}
	pieces[#pieces + 1] = {
		kind = "dark", mins = Vector(long + back, -back, -back), maxs = Vector(long + back + t, layout.cabinTo + back, high + back)
	}
	pieces[#pieces + 1] = {kind = "dark", mins = Vector(-back, -back, -back - t), maxs = Vector(long + back, layout.cabinTo + back, -back)}
	pieces[#pieces + 1] = {kind = "dark", mins = Vector(-back, -back, high + back), maxs = Vector(long + back, layout.cabinTo + back, high + back + t)}

	local stepMins, stepMaxs = layout.StepBox()

	-- the platform past the side door: a strip of floor from the carriage to the platform wall
	pieces[#pieces + 1] = {kind = "step", mins = Vector(stepMins.x - 48, -back, -t), maxs = Vector(stepMaxs.x + 48, -t, 0)}

	return pieces
end

-- Props that furnish each cabin: model, local position and local yaw.
function layout.Props()
	local props = {}
	local middle = (layout.cabinFrom + layout.cabinTo) / 2

	for i = 1, layout.cabins do
		local start = layout.CabinStart(i)
		local finish = start + layout.cabinLong

		props[#props + 1] = {model = "models/props_trainstation/traincar_seats001.mdl", pos = Vector(finish - 16, middle, 0), yaw = 180}
		props[#props + 1] = {model = "models/props_trainstation/traincar_rack001.mdl", pos = Vector(finish - 14, middle, 96), yaw = 180}
	end

	return props
end

-- A local position and yaw on a carriage placed at `origin` turned to `yaw`, in the world.
function PLUGIN:ToWorld(place, localPos, localYaw)
	local angle = Angle(0, place.yaw, 0)
	local pos = Vector(localPos)

	pos:Rotate(angle)

	return place.origin + pos, (place.yaw + (localYaw or 0)) % 360
end

-- A world position in a carriage's measures.
function PLUGIN:ToLocal(place, worldPos)
	local pos = worldPos - place.origin

	pos:Rotate(Angle(0, -place.yaw, 0))

	return pos
end
