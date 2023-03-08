local PLUGIN = PLUGIN.refine

/************************************************************************************
* Smelter NetVars:
* input - The amount of input
* coal - The amount of coal
* output - The amount of output
* timeToSmelt - The amount of time until the smelting is done 
*
* PLUGIN.*:
* carbon, output, impurities, iron, copper, coal, maxInput, smeltTime
************************************************************************************/

PLUGIN.IDCounter = PLUGIN.IDCounter or 0
PLUGIN.list = PLUGIN.list or {}
PLUGIN.class = PLUGIN.class or {}
PLUGIN.values = PLUGIN.values or {}
PLUGIN.staticValues = {
    ["interactive_smelter"] = {
        ["maxValues"] = {
            ["coal"] = 20,
            ["smeltable_junk"] = 20
        },
        ["smeltTime"] = 10,
        ["fuelEfficiency"] = { -- amount smelter per unit of fuel
            ["coal"] = 20
        }
    }
}

function PLUGIN.updateClientTable(smelterID)
    net.Start("glutServerSendResource")
        net.WriteUInt(smelterID, 8)
        net.WriteTable(PLUGIN.values[smelterID])
    net.Send(player.GetAll())
end

function PLUGIN.initSmelter(smelter)
    local ID = PLUGIN.IDCounter + 1
    PLUGIN.IDCounter = ID
    smelter:SetNetVar("ID", ID)
    PLUGIN.lastSmeltTime[ID] = RealTime()
    PLUGIN.list[ID] = smelter
    PLUGIN.class[ID] = smelter.uniqueID
    if (smelter.uniqueID == "interactive_smelter") then
        PLUGIN.values[ID] = {
            ["internal"] = {        -- To be migrated to serverside
                ["output"] = 0,		-- The amount of output
                ["iron"] = 0,       -- percent iron
                ["copper"] = 0,
                ["impurities"] = 0,	-- Value (0-100%) of impurities. Taking out slag reduces this amount
                ["carbon"] = 0,		-- Value of carbon (0-100%) (50 optimal) that is supposed to be 'tuned' to the right value. Going to cast or wrought iron decreases quality.
                ["slag"] = 0
            },
            ["fuel"] = {
                ["coal"] = 0,            
            },
            ["input"] = {
                ["smeltable_junk"] = 0
            },
            ["output"] = {
                ["iron"] = 0,
                ["copper"] = 0,
                ["slag"] = 0
            },
            ["lastSmeltTime"] = 0
        }
    end
    PLUGIN.updateClientTable(ID)
end

function PLUGIN.genSmeltCheck(ID)
    local values = PLUGIN.values[ID]
    local lowestVal = PLUGIN.staticValues[PLUGIN.class[ID]]["maxValues"][category]
    for _, Type in pairs({"input", "fuel"}) do
        for category, amt in pairs(values[Type]) do
            if amt < lowestVal then lowestVal = amt end
        end
    end
    if (lowestVal <= 0.1) then
        values["lastSmeltTime"] = RealTime()
        return false
    else
        return true
    end
end

function PLUGIN.physAddResource(ID, item, entityItem)
    local values = PLUGIN.values[ID]
    local currAmt
    local type
    local max
    
    for _, Type in pairs({"input", "fuel"}) do
        for category, amt in pairs(values[Type]) do
            if item.category == category then
                
                max = PLUGIN.staticValues[PLUGIN.class[ID]]["maxValues"][category]
                if amt < max then
                    currAmt = amt
                    type = Type
                    break
                else
                    return false
                end
            end
        end
    end

    if (!currAmt) then return false end
    PLUGIN.genSmeltCheck(ID)

    local values = PLUGIN.values[ID]
    local itemAmt = item:GetData("quantity", 1)
    if currAmt + itemAmt > max then
        local amtToAdd = max - currAmt
        if !pcall(function ()                                                   -- if item is in inv, kept for safety
            item:SetData("quantity", itemAmt - amtToAdd, ix.inventory.Get(item.invID):GetReceivers())
        end) then
            item:SetData("quantity", itemAmt - amtToAdd)  -- if the item is not in an inventory (most probable)
        end
        values[type][item.category] = max
    else
        values[type][item.category] = currAmt + itemAmt
        if !pcall(function ()                                                   
            entityItem:Remove()
        end) then                                                               
            item:Remove()                                                       -- if item is in inv, kept for safety
        end
    end
    PLUGIN.updateClientTable(ID)
    PLUGIN.generativeSmelt(ID)
end

function PLUGIN.generativeSmelt(smelterID)
    local values = PLUGIN.values[smelterID]
    local staticValues = PLUGIN.staticValues[PLUGIN.class[smelterID]]
    local smelted = math.floor( (RealTime() - values["lastSmeltTime"]) / staticValues["smeltTime"] )
    if (RealTime() - values["lastSmeltTime"] < staticValues["smeltTime"] / 8) then return end
    for fuelType, efficiency in pairs(staticValues["fuelEfficiency"]) do
        local temp = values["fuel"][fuelType] * staticValues["fuelEfficiency"][fuelType]
        if (temp <= 0) then return end
        if smelted > temp then
            smelted = temp
        end
    end
    if (smelted <= 0) then 
        values["lastSmeltTime"] = RealTime()
    end
    for v, amt in pairs(values["input"]) do
        if smelted > amt then
            smelted = amt
        end
    end

    values["lastSmeltTime"] = RealTime()
    for fuelType, efficiency in pairs(staticValues["fuelEfficiency"]) do
        fuelLost = smelted / staticValues["fuelEfficiency"][fuelType]
        values["fuel"][fuelType] = values["fuel"][fuelType] - fuelLost
    end
    -- add a constraint based on coal.
    for resource, amt in pairs(values["input"]) do
        if amt > 0 then
            local internal = values["internal"]
            rdm = math.random(70,90) / 100
            if (internal["output"] <= 0) then
                modifier = 1
            else
                modifier = amt / internal["output"]
            end
            internal["output"] = internal["output"] + smelted
            internal["iron"] = internal["iron"] * (1 - modifier) + (modifier * rdm)
            internal["impurities"] = internal["impurities"] * (1-modifier) + math.random(20,80) * modifier
            internal["carbon"] = math.random(20,80)
            internal["slag"] = internal["slag"] * (1 - modifier) + modifier * (1 - rdm)

            values["input"][resource] = values["input"][resource] - smelted
        end
    end
    -- for resource, _ in pairs(values["output"]) do
    --     if values["output"][resource] > 0 then
    --         values["output"][resource] = values["output"][resource] - smelted / 10
    --     end
    -- end
    PLUGIN.updateClientTable(smelterID)
end