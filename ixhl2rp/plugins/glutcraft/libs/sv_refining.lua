local PLUGIN = PLUGIN

/************************************************************************************
* Smelter NetVars:
* input - The amount of input
* coal - The amount of coal
* output - The amount of output
* timeToSmelt - The amount of time until the smelting is done 
*
* PLUGIN.refine.*:
* carbon, output, impurities, iron, copper, coal, maxInput, smeltTime
************************************************************************************/

PLUGIN.refine.smelter.IDCounter = PLUGIN.refine.smelter.IDCounter or 0
PLUGIN.refine.smelter.list = PLUGIN.refine.smelter.list or {}
PLUGIN.refine.smelter.class = PLUGIN.refine.smelter.class or {}
PLUGIN.refine.values = PLUGIN.refine.values or {}
PLUGIN.refine.smelter.maxValues = PLUGIN.refine.smelter.maxValues or {}


function PLUGIN.refine.smelter.initSmelter(smelter)
    local ID = PLUGIN.refine.smelter.IDCounter + 1
    PLUGIN.refine.smelter.IDCounter = ID
    smelter:SetNetVar("ID", ID)
    PLUGIN.refine.smelter.list[ID] = smelter
    PLUGIN.refine.smelter.class[ID] = smelter.uniqueID
end


function PLUGIN.refine.addResource(smelter, item, entityItem)
    function isValid()
        for resource, amt in pairs(smelter:GetInternalValues()) do
            if item.uniqueID == resource then
            end
        end
        return false
    end

    if isValid() then
        if smelter:GetNetVar(key) >= PLUGIN.refine.smelter.maxInput then
            return false
        elseif smelter:GetNetVar(key) + item:GetData("quantity", 1) > PLUGIN.refine.smelter.maxInput then
            local amtToSmelt = PLUGIN.refine.smelter.maxInput - smelter:GetNetVar(key)
            if !pcall(function ()
                item:SetData("quantity", item:GetData("quantity", 1) - amtToSmelt, ix.inventory.Get(item.invID):GetReceivers())
            end) then
                item:SetData("quantity", item:GetData("quantity", 1) - amtToSmelt) -- if the item is not in an inventory (most probable)
            end
            smelter:SetNetVar(key, PLUGIN.refine.smelter.maxInput, ents.FindByClass("player"))
        else
            smelter:SetNetVar(key, smelter:GetNetVar(key) + item:GetData("quantity", 1), ents.FindByClass("player"))
            entityItem:Remove()
        end
    end
end

function generativeSmelt(smelter)
    local timeSmelted = math.floor( (RealTime() - smelter.GetNetVar("LastSmeltTime")) / PLUGIN.refine.smelter.smeltTime ) -- there is a less costly way to do this
    -- add a constant based on coal.
    smelter.SetNetVar("input", smelter.GetNetVar("input") - smelted)
    smelter.SetNetVar("output", smelter.GetNetVar("output") + smelted)
    smelter.SetNetVar("LastSmeltTime", RealTime())
end