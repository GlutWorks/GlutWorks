local PLUGIN = PLUGIN
util.AddNetworkString("ixFieldPlaced")

local function acknowledge(client, item)
	net.Start("ixFieldPlaced")
		net.WriteUInt(item.id, 32)
	net.Send(client)
end

function PLUGIN:Identify(entity, id)
	self.lastID = math.max(self.lastID or 0, id or 0)
	if (!id) then self.lastID = self.lastID + 1 end
	entity.fieldID = id or self.lastID
	return entity
end

function PLUGIN:SpawnStock(kind, pose, owner, id, support)
	local entity = ents.Create("ix_build_stock")
	if (!IsValid(entity)) then return end
	entity:SetStock(kind)
	entity:SetSize(pose.size)
	entity:SetPos(pose.pos)
	entity:SetAngles(pose.ang)
	entity:SetBuilder(owner)
	entity:Spawn()
	if (entity:IsMarkedForDeletion()) then return end
	entity.supportID = support
	return self:Identify(entity, id)
end

function PLUGIN:SupportsCut(parent)
	for _, piece in ipairs(ents.FindByClass("ix_build_stock")) do
		if (piece.supportID == parent.fieldID and !piece:IsMarkedForDeletion()) then return true end
	end
	-- Benches have their own save format. Check the floor under their placement point.
	for _, bench in ipairs(ents.FindByClass("ix_station_workbench")) do
		if (!bench:IsMarkedForDeletion()) then
			local foot = bench:GetPos() + Vector(0, 0, bench:OBBMins().z)
			local trace = util.TraceLine({start = foot + vector_up * 2, endpos = foot - vector_up * 2, filter = bench})
			if (trace.Entity == parent) then return true end
		end
	end
end

function PLUGIN:SpawnPart(kind, foot, turn, owner, id)
	local entity = ents.Create("ix_fieldpiece")
	if (!IsValid(entity)) then return end
	entity:SetKind(kind)
	entity:SetFoot(foot)
	entity:SetTurn(turn)
	entity:SetBuilder(owner)
	entity:Spawn()
	if (!entity:IsMarkedForDeletion()) then return self:Identify(entity, id) end
end

local function readPoint(data)
	if (!istable(data)) then return end
	for _, key in ipairs({"x", "y", "z"}) do
		if (!isnumber(data[key]) or !(math.abs(data[key]) <= 32768)) then return end
	end
	return Vector(data.x, data.y, data.z)
end

local function visible(client, point)
	local eyes = client:GetShootPos()
	if (eyes:DistToSqr(point) > (PLUGIN.cutReach + 64) ^ 2) then return false end
	local trace = util.TraceLine({start = eyes, endpos = point, filter = client, mask = MASK_SOLID})
	return !trace.StartSolid and (!trace.Hit or trace.HitPos:DistToSqr(point) <= 9)
end

function PLUGIN:PlaceItem(item, data)
	local client = item.player
	if (!self:CanWork(client) or !client:GetCharacter():GetInventory():GetItemByID(item.id) or !istable(data)) then return false end
	local kind = data.kind
	local stock = self.stock[kind]
	local bench = item.uniqueID == "workbench" and kind == "workbench"
	if (!bench and (item.uniqueID != "carpentry_tools" or !stock)) then return false end
	local eyes, contact = client:GetShootPos(), readPoint(data)
	if (!contact or eyes:DistToSqr(contact) > self.cutReach ^ 2) then client:Notify("Move closer to the anchor.") return false end
	local trace = util.TraceLine({start = eyes, endpos = contact + (contact - eyes):GetNormalized() * 3, filter = client, mask = MASK_SOLID})
	if (!trace.Hit or trace.HitSky or trace.StartSolid or trace.HitPos:DistToSqr(contact) > 4 or trace.Entity:EntIndex() != data.target) then
		client:Notify("The anchor is out of sight. Mark it again.")
		return false
	end

	local owner = client:GetCharacter():GetID()
	if (bench) then
		if (!isnumber(data.step) or !(math.abs(data.step) <= 1024) or data.step != math.floor(data.step)) then return false end
		local pose, reason = self:BenchLayout(trace, data.step)
		if (!pose or reason) then client:Notify(reason) return false end
		local station = ix.station.Spawn(kind, pose.pos, pose.ang, owner)
		if (!IsValid(station)) then client:Notify("The workbench could not be placed.") return false end
		ix.station.Save()
		acknowledge(client, item)
		return true
	end

	if (!trace.HitWorld and !self:IsBuildPiece(trace.Entity)) then client:Notify("Start on the map or a built piece.") return false end
	if (data.mode != "surface" and data.mode != "upright" and data.mode != "level" and data.mode != "span") then return false end
	if (!isnumber(data.yaw) or !(math.abs(data.yaw) <= 360)) then return false end
	local b, c = readPoint(data.edge), readPoint(data.width)
	if (!b or !c or !visible(client, b) or !visible(client, c)) then client:Notify("Keep both marks within sight and reach.") return false end
	local a = self:Contact(trace, data.snap == true)
	local plane = self:PlaneNormal(data.mode, trace.HitNormal, data.yaw)
	local pose, reason = self:CutPose(kind, a, b, c, trace.HitNormal, plane)
	if (!pose) then client:Notify(reason) return false end
	if (self:CutBlocked(pose)) then client:Notify("The cut intersects something. Adjust a mark.") return false end

	local cost = self:StockCost(kind, pose.size)
	if (!isnumber(data.cost) or !(math.abs(cost - data.cost) < 0.001)) then
		client:Notify("The cut changed. Mark the anchor and width again for a new price.")
		return false
	end
	if (!ix.stack.Take(client:GetCharacter():GetInventory(), stock.item, cost)) then
		client:Notify("You need " .. cost .. " kg of " .. ix.item.list[stock.item].name:lower() .. ".")
		return false
	end
	local entity = self:SpawnStock(kind, pose, owner, nil, trace.Entity.fieldID)
	if (!IsValid(entity)) then
		ix.stack.GiveOrDrop(client, stock.item, cost)
		client:Notify("The material could not be fastened.")
		return false
	end
	entity:EmitSound("physics/wood/wood_box_impact_hard3.wav")
	self:SaveData()
	acknowledge(client, item)
	return false
end

function PLUGIN:SaveData()
	local records = table.Copy(self.unloaded or {})
	for _, entity in ipairs(ents.FindByClass("ix_fieldpiece")) do
		if (!entity:IsMarkedForDeletion() and self.parts[entity:GetKind()]) then
			records[#records + 1] = {id = entity.fieldID, kind = entity:GetKind(), foot = entity:GetFoot(), turn = entity:GetTurn(), owner = entity:GetBuilder()}
		end
	end
	for _, entity in ipairs(ents.FindByClass("ix_build_stock")) do
		if (!entity:IsMarkedForDeletion()) then
			records[#records + 1] = {id = entity.fieldID, support = entity.supportID, stock = entity:GetStock(),
				size = entity:GetSize(), pos = entity:GetPos(), ang = entity:GetAngles(), owner = entity:GetBuilder()}
		end
	end
	self:SetData(records)
end

function PLUGIN:LoadData()
	self.unloaded = {}
	local function restore(record)
		if (!self.parts[record.kind] or !IsValid(self:SpawnPart(record.kind, record.foot, record.turn, record.owner or 0, record.id))) then
			self.unloaded[#self.unloaded + 1] = record
		end
	end
	local records = self:GetData({})
	for _, record in ipairs(records) do self.lastID = math.max(self.lastID or 0, record.id or 0) end
	for _, record in ipairs(records) do
		if (record.stock) then
			if (!self.stock[record.stock] or !isvector(record.size) or !isvector(record.pos) or !isangle(record.ang)
				or !IsValid(self:SpawnStock(record.stock, record, record.owner or 0, record.id, record.support))) then
				self.unloaded[#self.unloaded + 1] = record
			end
		elseif (record.kind and isvector(record.foot) and isnumber(record.turn)) then
			restore(record)
		elseif (isvector(record.origin) and isnumber(record.sections) and isnumber(record.yaw)) then
			-- Keep completed shelter bays from the survey trial. Its benches have their own station saves.
			local function old(flag, kind, x, y, turn)
				if (bit.band(record.sections, flag) == 0) then return end
				local angle = Angle(0, record.yaw, 0)
				local foot = LocalToWorld(Vector(x, y, 0), angle_zero, record.origin, angle)
				restore({kind = kind, foot = foot, turn = (math.Round(record.yaw / 90) + turn) % 4})
			end
			for _, x in ipairs({76, 172}) do
				old(1, "boards", x, 0, 1)
				old(2, "boards", x, 96, 1)
				old(8, "roof", x, 48, 1)
			end
			old(4, "boards", 220, 48, 0)
		end
	end
end
