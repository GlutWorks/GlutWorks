local pad = ix.datapad

-- Which body region each bone of a model belongs to: the region a bullet striking that bone
-- counts for (its hitbox's hitgroup, through ix.body.HitGroupToRegion). A bone with no hitbox, or
-- one in the generic hitgroup (which says nothing of where it is: the Overwatch soldier's
-- pelvis), goes by its name where that names a part of the body, else by its parent. No hitgroup
-- names the feet (only a fall reaches them), so a foot or toe bone counts for them by its name. A
-- side is -1 for the character's left, 1 for the right and nil for the middle, from the hitgroup
-- or else the bone's name.
local maps = {}

local SIDES = {
	[HITGROUP_LEFTARM] = -1, [HITGROUP_LEFTLEG] = -1,
	[HITGROUP_RIGHTARM] = 1, [HITGROUP_RIGHTLEG] = 1
}

-- Checked in order, against the lowercased bone name.
local NAMES = {
	{"head", "head"}, {"neck", "head"}, {"pelvis", "waist"},
	{"spine2", "chest"}, {"spine3", "chest"}, {"spine4", "chest"}, {"clavicle", "chest"}, {"spine", "waist"},
	{"upperarm", "arms"}, {"forearm", "arms"}, {"hand", "arms"}, {"finger", "arms"}, {"wrist", "arms"},
	{"thigh", "legs"}, {"calf", "legs"}, {"knee", "legs"}
}

local function nameRegion(lower)
	for _, rule in ipairs(NAMES) do
		if (lower:find(rule[1], 1, true)) then return rule[2] end
	end
end

local function nameSide(name)
	if (name:find("_L_", 1, true) or name:find("Left", 1, true)) then return -1 end
	if (name:find("_R_", 1, true) or name:find("Right", 1, true)) then return 1 end
end

-- nil until the model has bones to read, so a model still loading is asked again later. (A
-- clientside model reads every bone as __INVALIDBONE__ until its bones are first set up.)
local INVALID = "__INVALIDBONE__"
function pad.BoneMap(ent)
	local model = IsValid(ent) and ent:GetModel()
	if (!isstring(model) or model == "") then return end
	model = model:lower()
	if (maps[model]) then return maps[model] end
	local count = ent:GetBoneCount()
	if (!count or count <= 0) then return end
	for i = 0, count - 1 do
		if (ent:GetBoneName(i) == INVALID) then return end
	end
	local map = {model = model, count = count, region = {}, side = {}, name = {}, index = {}, parent = {}, child = {}, hitbox = {}}
	local set = ent:GetHitboxSet() or 0
	for i = 0, (ent:GetHitBoxCount(set) or 0) - 1 do
		local bone, group = ent:GetHitBoxBone(i, set), ent:GetHitBoxHitGroup(i, set)
		-- (The server places only the bones its hitboxes need: a finger's stays at the origin.)
		if (bone) then map.hitbox[bone] = true end
		if (bone and group and group != HITGROUP_GENERIC and !map.region[bone]) then
			map.region[bone] = ix.body.HitGroupToRegion(group)
			map.side[bone] = SIDES[group]
		end
	end
	for i = 0, count - 1 do
		local name = ent:GetBoneName(i) or ""
		local parent = ent:GetBoneParent(i)
		map.name[i], map.index[name] = name, i
		map.parent[i] = parent and parent >= 0 and parent or nil
		if (map.parent[i]) then
			map.child[map.parent[i]] = map.child[map.parent[i]] or {}
			table.insert(map.child[map.parent[i]], i)
		end
		local lower = name:lower()
		if (lower:find("foot", 1, true) or lower:find("toe", 1, true)) then
			map.region[i] = "feet"
		elseif (!map.region[i]) then
			map.region[i] = nameRegion(lower)
		end
		if (map.side[i] == nil) then map.side[i] = nameSide(name) end
	end
	local function resolve(i, depth)
		if (map.region[i]) then return map.region[i] end
		local parent = map.parent[i]
		local region = parent and depth < count and resolve(parent, depth + 1) or "chest"
		map.region[i] = region
		return region
	end
	for i = 0, count - 1 do resolve(i, 0) end
	maps[model] = map
	return map
end
