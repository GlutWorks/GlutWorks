local PLUGIN = PLUGIN
local counter = counter or 0
local rate = rate or 20

net.Receive( "glutClientSyncResources", function(_, ply)
    net.Start( "glutServerSyncResources")
        net.WriteTable(PLUGIN.refine.values)
    net.Send(ply)
end )

hook.Add("Tick", "updateFunction", function ()
    counter = counter + 1
    if (counter < rate ) then return end
    counter = 0
    rate = FrameTime() * 40
    
    for ID, _ in pairs(PLUGIN.refine.list) do
        if (PLUGIN.refine.genSmeltCheck(ID)) then
            PLUGIN.refine.generativeSmelt(ID)
        end
    end

    if (PLUGIN.refine.buttons) then
        for id, button in pairs (PLUGIN.refine.buttons["left"]) do
            local iSmelter = PLUGIN.refine.list[PLUGIN.refine.buttonEntity[id]]
            if (button:IsValid() && iSmelter:IsValid()) then
                button:SetPos(iSmelter:GetPos() + iSmelter:GetForward() * 7 + iSmelter:GetUp() * 40 + iSmelter:GetRight() * 10)
                button:SetAngles(iSmelter:GetAngles())
            end
        end
        for id, button in pairs (PLUGIN.refine.buttons["right"]) do
            local iSmelter = PLUGIN.refine.list[PLUGIN.refine.buttonEntity[id]]
            if (button:IsValid() && iSmelter:IsValid()) then
                button:SetPos(iSmelter:GetPos() + iSmelter:GetForward() * 7 + iSmelter:GetUp() * 40 + iSmelter:GetRight() * -10)
                button:SetAngles(iSmelter:GetAngles())
            end
        end
    end
end)