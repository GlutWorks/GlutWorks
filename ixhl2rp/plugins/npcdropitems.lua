local PLUGIN = PLUGIN;

PLUGIN.name = "NPC Drop"
PLUGIN.author = "Mixed"
PLUGIN.description = "Makes NPC Drop items when they die."

function PLUGIN:OnNPCKilled(entity)
    local class = entity:GetClass()
    local rand = math.random(1, 100)

    if (class == "npc_headcrab") then
    	if rand >= 70 then
        	ix.item.Spawn("meat_chunk", entity:GetPos() + Vector(0, 0, 8))
        end
    end
end
