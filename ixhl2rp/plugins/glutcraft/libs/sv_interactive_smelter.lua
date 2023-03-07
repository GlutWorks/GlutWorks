

function PLUGIN.refine.physAddResource(smelterID, item, entityItem)
    local amtToSmelt
    local currAmt
    local type
    for typePair, amt in pairs(PLUGIN.refine.values[smelterID]["in"]) do
        if item.category == category then
            if amt < PLUGIN.refine.maxValues[category] then
                currAmt = PLUGIN.refine.maxValues[category]
                amtToSmelt = amt
                type = typePair
                break
            else
                return false
            end
        end
    end
    if (!amtToSmelt) then return false end
    
    if currAmt + amtToSmelt > PLUGIN.refine.maxInput then
        local amtToSmelt = PLUGIN.refine.maxInput - smelter:GetNetVar(key)
        if !pcall(function ()                                                   -- if item is in inv, kept for safety
            item:SetData("quantity", item:GetData("quantity", 1) - amtToSmelt, ix.inventory.Get(item.invID):GetReceivers())
        end) then
            item:SetData("quantity", item:GetData("quantity", 1) - amtToSmelt)  -- if the item is not in an inventory (most probable)
        end
        PLUGIN.refine.values[smelterID]["in"][type] = PLUGIN.refine.maxInput
    else
        PLUGIN.refine.values[smelterID]["in"][type] = currAmt + amtToSmelt
        if !pcall(function ()                                                   
            entityItem:Remove()
        end) then                                                               
            item:Remove()                                                       -- if item is in inv, kept for safety
        end
    end
end