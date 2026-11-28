local PLUGIN = PLUGIN
util.AddNetworkString("ixFieldPlaced")

function PLUGIN:SpawnPart(kind, foot, turn, owner)
	local entity = ents.Create("ix_fieldpiece")
	if (!IsValid(entity)) then return end
	entity:SetKind(kind)
	entity:SetFoot(foot)
	entity:SetTurn(turn)
	entity:SetBuilder(owner)
	entity:Spawn()
	if (!entity:IsMarkedForDeletion()) then return entity end
end

-- Clients send the contact they saw (possibly pinned) and their chosen rotation. Retrace it from
-- the eyes and solve again. No entity position, support, collision result or cost is authoritative on the client.
function PLUGIN:PlaceItem(item, data)
	local client = item.player
	if (!self:CanWork(client) or !client:GetCharacter():GetInventory():GetItemByID(item.id) or !istable(data)) then return false end
	local kind = data.kind
	local part = self.parts[kind]
	if (item.uniqueID == "workbench" and kind != "workbench") then return false end
	if (item.uniqueID != "workbench" and (item.uniqueID != "carpentry_tools" or !part)) then return false end
	if (!isnumber(data.x) or !isnumber(data.y) or !isnumber(data.z) or !isnumber(data.step)
		or data.step != math.floor(data.step) or math.abs(data.step) > 1024) then return false end
	local eyes = client:GetShootPos()
	local contact = Vector(data.x, data.y, data.z)
	if (eyes:DistToSqr(contact) > 164 * 164) then client:Notify("Move closer to the piece.") return false end
	local trace = util.TraceLine({start = eyes, endpos = contact + (contact - eyes):GetNormalized() * 3,
		filter = client, mask = MASK_SOLID})
	if (!trace.Hit or trace.StartSolid or trace.HitPos:DistToSqr(contact) > 16 or trace.Entity:EntIndex() != data.target) then
		client:Notify("The placement point is out of sight. Aim again.")
		return false
	end
	local pose, reason = self:Layout(client, kind, trace, data.step)
	if (!pose or reason) then client:Notify(reason) return false end

	if (kind == "workbench") then
		local station = ix.station.Spawn(kind, pose.pos, pose.ang, client:GetCharacter():GetID())
		if (!IsValid(station)) then client:Notify("The workbench could not be placed.") return false end
		ix.station.Save()
		net.Start("ixFieldPlaced")
			net.WriteUInt(item.id, 32)
		net.Send(client)
		return true -- the Helix item action consumes exactly this kit
	end

	local inventory = client:GetCharacter():GetInventory()
	if (!ix.stack.Take(inventory, part.item, part.cost)) then
		client:Notify("You need " .. part.cost .. " kg of " .. ix.item.list[part.item].name:lower() .. ".")
		return false
	end
	local entity
	if (kind == "boards" or kind == "metal") then
		if (pose.wall:Fit(kind)) then entity = pose.wall else pose.wall:Fit("frame") end
	else
		entity = self:SpawnPart(kind, pose.foot, pose.turn, client:GetCharacter():GetID())
	end
	if (!IsValid(entity)) then
		ix.stack.GiveOrDrop(client, part.item, part.cost)
		client:Notify("The piece could not be fitted.")
		return false
	end
	entity:EmitSound("physics/wood/wood_box_impact_hard3.wav")
	self:SaveData()
	return false -- the tools stay in hand for the next piece
end

function PLUGIN:SaveData()
	local records = table.Copy(self.unloaded or {})
	for _, entity in ipairs(ents.FindByClass("ix_fieldpiece")) do
		if (!entity:IsMarkedForDeletion() and self.parts[entity:GetKind()]) then
			records[#records + 1] = {kind = entity:GetKind(), foot = entity:GetFoot(), turn = entity:GetTurn(), owner = entity:GetBuilder()}
		end
	end
	self:SetData(records)
end

function PLUGIN:LoadData()
	self.unloaded = {}
	local function restore(record)
		if (!self.parts[record.kind] or !IsValid(self:SpawnPart(record.kind, record.foot, record.turn, record.owner or 0))) then
			self.unloaded[#self.unloaded + 1] = record
		end
	end
	for _, record in ipairs(self:GetData({})) do
		if (record.kind and isvector(record.foot) and isnumber(record.turn)) then
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
