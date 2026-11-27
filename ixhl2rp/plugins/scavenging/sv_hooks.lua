local PLUGIN = PLUGIN

-- Every scavengeable prop in the world is kept across restarts, including scavenged ones.
function PLUGIN:SaveProps()
	local data = table.Copy(self.unloaded or {})

	for _, entity in ents.Iterator() do
		if (entity.IsScavengeable and entity:GetClass() != "ix_scavengeable" and !entity:IsMarkedForDeletion()) then
			data[#data + 1] = {
				class = entity:GetClass(),
				pos = entity:GetPos(),
				ang = entity:GetAngles(),
				damage = entity.damage,
				respawnAt = entity.respawnAt
			}
		end
	end

	self:SetData(data)
end

function PLUGIN:QueueSave()
	if (!ix.shuttingDown) then
		timer.Create("ixScavengingSave", 1, 1, function()
			self:SaveProps()
		end)
	end
end

function PLUGIN:SaveData()
	self:SaveProps()
end

function PLUGIN:LoadData()
	-- records whose class no longer exists are kept and saved again, rather than dropped
	self.unloaded = {}

	for _, v in ipairs(self:GetData()) do
		if (!istable(v) or !isstring(v.class) or v.class == "ix_scavengeable" or !isvector(v.pos)) then
			continue
		end

		local entity = scripted_ents.IsBasedOn(v.class, "ix_scavengeable") and ents.Create(v.class)

		if (!IsValid(entity)) then
			self.unloaded[#self.unloaded + 1] = v
		else
			entity:SetPos(v.pos)
			entity:SetAngles(isangle(v.ang) and v.ang or angle_zero)
			entity:Spawn()
			entity.damage = math.max(tonumber(v.damage) or 0, 0)

			if (tonumber(v.respawnAt)) then
				entity:Deplete(tonumber(v.respawnAt))
			end
		end
	end
end
