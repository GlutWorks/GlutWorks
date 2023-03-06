local PLUGIN = PLUGIN

net.Receive( "glutAddResource", function(_, _)
    addResource(Player(net.ReadUInt(8)), net.ReadEntity(), net.ReadString(), tonumber(net.ReadInt(8)))
end )
net.Receive( "glutSmelt", function(_, _)
    startSmelt(net.ReadEntity())
end )

function addResource(player, smelter, name, amt)
    if amt < 0 then amt = 0 end -- intentional redundency
        
    local totalAmt = 0
    for _, item in pairs(player:GetCharacter():GetInventory():GetItems()) do
        if item.uniqueID == name then
            if (item:GetData("quantity", 1)) then
                totalAmt = totalAmt + item:GetData("quantity", 1)
            else							-- this is not required
                totalAmt = totalAmt + 1		-- but preserved for 
            end								-- safety and resusability
        end
    end
    
    if totalAmt < amt then
        player:Notify("You don't have enough "..name.." to smelt!")
        return
    end
    
    smelter:SetNetVar(name, smelter:GetNetVar(name) + amt, ents.FindByClass("player"))
    for _, item in pairs(player:GetCharacter():GetInventory():GetItems()) do
        if item.uniqueID == name then
            if item:GetData("quantity", 1) > amt then
                item:SetData("quantity", item:GetData("quantity", 1) - amt)
                break
            else
                amt = amt - item:GetData("quantity", 1)
                item:Remove()
            end
        end
    end
    net.Start("glutCraftRedraw"); net.WriteEntity(smelter); net.Broadcast()
end

function startSmelt(smelter)
    for _, resource in pairs(smelter.GetResources()) do
        if resource == "metal_scrap" then continue end
        if smelter:GetNetVar(resource) > 0 then
            smelter:SetNetVar(resource, smelter:GetNetVar(resource) - 1, ents.FindByClass("player"))
            smelter:SetNetVar("TimeToSmelt", 10, ents.FindByClass("player"))

            smeltTimer = timer.Create("smeltTimer", 1, 10, function()
                print(smelter:GetNetVar("TimeToSmelt"))
                smelter:SetNetVar("TimeToSmelt", smelter:GetNetVar("TimeToSmelt") - 1, ents.FindByClass("player"))
                net.Start("glutCraftRedraw"); net.WriteEntity(smelter); net.Broadcast()
                if (smelter:GetNetVar("TimeToSmelt") == 0) then
                    smelter:SetNetVar("metal_scrap", smelter:GetNetVar("metal_scrap") + 1, ents.FindByClass("player"))
                    net.Start("glutCraftRedraw"); net.WriteEntity(smelter); net.Broadcast()
                    timer.Remove("smeltTimer")
                end
            end)
        end
    end
end
