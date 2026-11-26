local PLUGIN = PLUGIN

-- Every scavengeable prop in the world is kept across restarts, including scavenged ones.
function PLUGIN:SaveProps()
	local data = {}

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
	for _, v in ipairs(self:GetData()) do
		if (istable(v) and isstring(v.class) and v.class != "ix_scavengeable" and isvector(v.pos)
			and scripted_ents.IsBasedOn(v.class, "ix_scavengeable")) then
			local entity = ents.Create(v.class)
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
