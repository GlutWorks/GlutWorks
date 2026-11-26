
local PLUGIN = PLUGIN

PLUGIN.name = "Random Items"
PLUGIN.description = "Adds a random assortment of items and entites."
PLUGIN.author = "Oebelysk"

if (SERVER) then
	function PLUGIN:SaveChildDispensers()
		local data = {}

		for _, v in ipairs(ents.FindByClass("ix_childdispenser")) do
			-- removal takes effect at the end of the frame, until then the entity can still be found
			if (!v:IsMarkedForDeletion()) then
				data[#data + 1] = {v:GetPos(), v:GetAngles(), v:GetEnabled()}
			end
		end

		self:SetData(data)
	end

	function PLUGIN:LoadData()
		self.bCleaningUp = false

		for _, v in ipairs(self:GetData()) do
			local dispenser = ents.Create("ix_childdispenser")

			dispenser:SetPos(v[1])
			dispenser:SetAngles(v[2])
			dispenser:Spawn()
			dispenser:SetEnabled(v[3])
		end
	end

	function PLUGIN:SaveData()
		self:SaveChildDispensers()
	end

	-- a map cleanup saves and then removes every dispenser; those removals must not overwrite the save
	function PLUGIN:PreCleanupMap()
		self.bCleaningUp = true
	end
end
