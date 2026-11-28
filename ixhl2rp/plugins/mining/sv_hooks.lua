local PLUGIN = PLUGIN

-- Every ore node in the world is kept across restarts, including mined-out ones and when they grow back.
function PLUGIN:SaveNodes()
	local data = table.Copy(self.unloaded or {})

	for _, entity in ents.Iterator() do
		if (entity.IsOreNode and entity.oreItem and !entity:IsMarkedForDeletion()) then
			data[#data + 1] = {
				class = entity:GetClass(),
				pos = entity:GetPos(),
				ang = entity:GetAngles(),
				stage = entity:GetStage(),
				health = entity.nodeHealth,
				respawnAt = entity.respawnAt,
				-- the stored base value, not GetRichness(): lastHarvest carries the regrowth
				richness = entity.richness,
				lastHarvest = entity.lastHarvest
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
	-- records whose class no longer exists are kept and saved again, rather than dropped
	self.unloaded = {}

	for _, v in ipairs(self:GetData()) do
		if (!istable(v) or !isstring(v.class) or v.class == "ix_orenode" or !isvector(v.pos)) then
			continue
		end

		local entity = scripted_ents.IsBasedOn(v.class, "ix_orenode") and ents.Create(v.class)

		if (!IsValid(entity)) then
			self.unloaded[#self.unloaded + 1] = v
		else
			entity:SetPos(v.pos)
			entity:SetAngles(isangle(v.ang) and v.ang or angle_zero)
			entity:Spawn()

			local stage = math.Clamp(math.floor(tonumber(v.stage) or 1), 1, #entity.stages)

			if (stage != 1) then
				entity:SetStage(stage)
				entity:ApplyStage()
			end

			entity.nodeHealth = math.Clamp(tonumber(v.health) or entity.stageHealth, 1, entity.stageHealth)
			-- saves from before richness load full, as a fresh node
			entity.richness = math.Clamp(tonumber(v.richness) or 1, 0, 1)
			entity.lastHarvest = tonumber(v.lastHarvest) or os.time()

			if (tonumber(v.respawnAt)) then
				entity:Deplete(tonumber(v.respawnAt))
			end
		end
	end
end
