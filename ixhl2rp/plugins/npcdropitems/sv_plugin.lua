local PLUGIN = PLUGIN

--- Rolls the drop table for an NPC class. Returns the item IDs to drop.
function PLUGIN:RollDrops(class)
	local result = {}

	for _, v in ipairs(self.drops[class] or {}) do
		if (math.random() < v[2]) then
			result[#result + 1] = v[1]
		end
	end

	return result
end

function PLUGIN:SpawnDrop(uniqueID, position)
	if (!ix.item.list[uniqueID]) then
		return
	end

	if (ix.stack and ix.stack.IsStackable(ix.item.list[uniqueID])) then
		ix.stack.Spawn(uniqueID, position, 1)
	else
		ix.item.Spawn(uniqueID, position)
	end
end

function PLUGIN:OnNPCKilled(npc)
	local position = npc:GetPos() + Vector(0, 0, 16)

	for _, uniqueID in ipairs(self:RollDrops(npc:GetClass())) do
		self:SpawnDrop(uniqueID, position)
	end
end
