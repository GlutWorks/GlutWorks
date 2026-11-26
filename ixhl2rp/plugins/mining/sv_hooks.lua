local PLUGIN = PLUGIN

-- Every ore node in the world is kept across restarts, including mined-out ones and when they grow back.
function PLUGIN:SaveNodes()
	local data = {}

	for _, entity in ents.Iterator() do
		if (entity.IsOreNode and entity.oreItem and !entity:IsMarkedForDeletion()) then
			data[#data + 1] = {
				class = entity:GetClass(),
				pos = entity:GetPos(),
				ang = entity:GetAngles(),
				stage = entity:GetStage(),
				health = entity.nodeHealth,
				respawnAt = entity.respawnAt
			}
		end
	end

	self:SetData(data)
end

function PLUGIN:QueueSave()
	if (!ix.shuttingDown) then
		timer.Create("ixMiningSave", 1, 1, function()
			self:SaveNodes()
		end)
	end
end

function PLUGIN:SaveData()
	self:SaveNodes()
end

function PLUGIN:LoadData()
	for _, v in ipairs(self:GetData()) do
		if (istable(v) and isstring(v.class) and v.class != "ix_orenode" and isvector(v.pos)
			and scripted_ents.IsBasedOn(v.class, "ix_orenode")) then
			local entity = ents.Create(v.class)
			entity:SetPos(v.pos)
			entity:SetAngles(isangle(v.ang) and v.ang or angle_zero)
			entity:Spawn()

			local stage = math.Clamp(math.floor(tonumber(v.stage) or 1), 1, #entity.stages)

			if (stage != 1) then
				entity:SetStage(stage)
				entity:ApplyStage()
			end

			entity.nodeHealth = math.Clamp(tonumber(v.health) or entity.stageHealth, 1, entity.stageHealth)

			if (tonumber(v.respawnAt)) then
				entity:Deplete(tonumber(v.respawnAt))
			end
		end
	end
end
