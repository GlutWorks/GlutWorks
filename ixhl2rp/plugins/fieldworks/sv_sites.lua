local PLUGIN = PLUGIN
local crateHeight = Vector(0, 0, 20.25)
local inset = Vector(0.15, 0.15, 0.15)
local siteClass = "ix_fieldsite"

-- Survey yaw is always a quarter turn, so two opposite corners also bound the rotated box.
local function Footprint(origin, yaw)
	local angle = Angle(0, yaw, 0)
	local a = LocalToWorld(Vector(-21, -21, 0), angle_zero, origin, angle)
	local b = LocalToWorld(Vector(225, 101, 101), angle_zero, origin, angle)
	return Vector(math.min(a.x, b.x), math.min(a.y, b.y), origin.z),
		Vector(math.max(a.x, b.x), math.max(a.y, b.y), origin.z + 101)
end

local function Blocked(pos, mins, maxs, ignore)
	local trace = util.TraceHull({
		start = pos, endpos = pos, mins = mins, maxs = maxs, filter = ignore, mask = MASK_PLAYERSOLID
	})
	return trace.Hit or trace.StartSolid
end

local function SpawnPiece(site, piece)
	local entity = ents.Create("ix_fieldpiece")
	if (!IsValid(entity)) then return end

	entity:SetPos(site:LocalToWorld(piece.pos - crateHeight))
	entity:SetAngles(site:LocalToWorldAngles(piece.ang or angle_zero))
	entity:SetModel(piece.model)
	entity:SetMaterial(piece.material)
	entity.fieldSite = site
	entity.sectionFlag = piece.flag
	entity.rockHits = !piece.item and 3 or nil
	entity:Spawn()
	if (entity:IsMarkedForDeletion()) then return end
	site:DeleteOnRemove(entity)
	return entity
end

local function SpawnSite(origin, yaw, sections)
	local site = ents.Create(siteClass)
	if (!IsValid(site)) then return end

	site.surveyed = true
	site:SetPos(origin + crateHeight)
	site:SetAngles(Angle(0, yaw, 0))
	site:Spawn()
	site:SetSections(sections)
	for _, piece in pairs(PLUGIN.pieces) do
		if (piece.flag and site:HasSection(piece.flag) and !IsValid(SpawnPiece(site, piece))) then
			site:Remove()
			return
		end
	end
	return site
end

function PLUGIN:Survey(origin, yaw, quarry)
	local mins, maxs = Footprint(origin, yaw)
	local height = Vector(0, 0, 2)
	-- Include empty reservations so two future buildings cannot claim the same bay.
	for _, other in ipairs(ents.FindByClass(siteClass)) do
		local low, high = Footprint(other:GetPos() - crateHeight, other:GetAngles().y)
		if (mins.x < high.x and maxs.x > low.x and mins.y < high.y and maxs.y > low.y
			and mins.z < high.z and maxs.z > low.z) then
			return nil, "Another survey already covers this ground."
		end
	end

	if (Blocked(origin, mins - origin + height, maxs - origin)) then
		return nil, "The workshop needs a clear bay ahead of the crate."
	end
	for _, x in ipairs({mins.x, (mins.x + maxs.x) / 2, maxs.x}) do
		for _, y in ipairs({mins.y, (mins.y + maxs.y) / 2, maxs.y}) do
			local point = Vector(x, y, origin.z)
			local floor = util.TraceLine({start = point + height, endpos = point - height, mask = MASK_PLAYERSOLID})
			if (!floor.HitWorld or floor.StartSolid or floor.HitNormal.z < 0.99) then
				return nil, "The whole workshop needs level ground."
			end
		end
	end

	local site = SpawnSite(origin, yaw, quarry and bit.bor(16, 32) or 0)
	if (!IsValid(site)) then return nil, "The site could not be marked." end
	self:SaveData()
	return site
end

function PLUGIN:Build(site, client, key)
	local piece = self.pieces[key]
	local inventory = client:GetCharacter():GetInventory()
	if (ix.stack.Count(inventory, piece.item) < piece.cost) then
		client:Notify("You need " .. piece.cost .. " kg of " .. ix.item.list[piece.item].name:lower() .. ".")
		return
	end

	local entity
	if (key == "bench") then
		local ground = site:LocalToWorld(piece.pos - crateHeight)
		entity = ix.station.Spawn("workbench", ground, site:GetAngles(), client:GetCharacter():GetID())
		if (IsValid(entity)) then
			entity:SetPos(ground - Vector(0, 0, entity:OBBMins().z))
		end
	else
		entity = SpawnPiece(site, piece)
	end
	if (!IsValid(entity)) then
		client:Notify("The section could not be assembled.")
		return
	end

	-- Something may have entered the slot since the survey, including the person building.
	local mins, maxs = entity:GetRotatedAABB(entity:OBBMins(), entity:OBBMaxs())
	if (Blocked(entity:GetPos(), mins + inset, maxs - inset, entity)) then
		entity:Remove()
		client:Notify("Clear the space for this section first.")
		return
	end
	if (!ix.stack.Take(inventory, piece.item, piece.cost)) then
		entity:Remove()
		return
	end

	entity:EmitSound("physics/wood/wood_box_impact_hard3.wav")
	if (key == "bench") then
		ix.station.Save()
	else
		site:SetSections(bit.bor(site:GetSections(), piece.flag))
		self:SaveData()
	end
end

function PLUGIN:SaveData()
	local records = table.Copy(self.unloaded or {})
	for _, site in ipairs(ents.FindByClass(siteClass)) do
		if (site.surveyed and !site:IsMarkedForDeletion()) then
			records[#records + 1] = {origin = site:GetPos() - crateHeight, yaw = site:GetAngles().y, sections = site:GetSections()}
		end
	end
	self:SetData(records)
end

function PLUGIN:LoadData()
	self.unloaded = {}
	for _, record in ipairs(self:GetData({})) do
		if (isvector(record.origin) and isnumber(record.yaw) and isnumber(record.sections)) then
			if (!IsValid(SpawnSite(record.origin, record.yaw, record.sections))) then
				self.unloaded[#self.unloaded + 1] = record
			end
		end
	end
end
