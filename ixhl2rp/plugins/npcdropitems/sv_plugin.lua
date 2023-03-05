local PLUGIN = PLUGIN

function PLUGIN:OnNPCKilled(npc)
     if npc:GetClass() == "npc_headcrab_black" then 
         if (math.random(1,4) == 4) then
            ix.item.Spawn("poison_headcrab_gland", npc:GetPos())
         end
     end

     if npc:GetClass() == "npc_antlion" then 
        if (math.random(1,4) == 4) then
           ix.item.Spawn("antlion_meat_chunk", npc:GetPos())
        end
    end

    if npc:GetClass() == "npc_headcrab" then 
        if (math.random(1,3) == 3) then
           ix.item.Spawn("headcrab_meat_chunk", npc:GetPos())
        end
    end
end