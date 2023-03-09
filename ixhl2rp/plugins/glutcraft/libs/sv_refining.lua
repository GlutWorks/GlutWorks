local PLUGIN = PLUGIN.refine

PLUGIN.IDCounter = PLUGIN.IDCounter or 0
PLUGIN.list = PLUGIN.list or {}
PLUGIN.class = PLUGIN.class or {}
PLUGIN.values = PLUGIN.values or {}
PLUGIN.staticValues = {
    ["interactive_smelter"] = {
        ["maxValues"] = {
            ["fuel"] = 20,
            ["input"] = 20
        },
        ["smeltTime"] = 120,
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
    smelter.index = ID
    PLUGIN.IDCounter = ID
    smelter:SetNetVar("ID", ID)
    PLUGIN.lastSmeltTime[ID] = RealTime()
    PLUGIN.list[ID] = smelter
    PLUGIN.class[ID] = smelter.uniqueID
    if (smelter.uniqueID == "interactive_smelter") then
        PLUGIN.values[ID] = {
            ["internal"] = {        -- To be migrated to serverside
                ["input"] = {
                    ["amount"] = 0.0,		-- The amount of output
                    ["iron"] = 0.0,       -- percent iron
                    ["copper"] = 0.0,
                    ["impurities"] = 0.0,	-- Value (0-100%) of impurities. Taking out slag reduces this amount
                    ["carbon"] = 0.0,		-- Value of carbon (0-100%) (50 optimal) that is supposed to be 'tuned' to the right value. Going to cast or wrought iron decreases quality.
                    ["slag"] = 0.0
                },
                ["output"] = {
                    ["amount"] = 0.0,		-- The amount of output
                    ["iron"] = 0.0,       -- percent iron
                    ["copper"] = 0.0,
                    ["impurities"] = 0.0,	-- Value (0-100%) of impurities. Taking out slag reduces this amount
                    ["carbon"] = 0.0,		-- Value of carbon (0-100%) (50 optimal) that is supposed to be 'tuned' to the right value. Going to cast or wrought iron decreases quality.
                    ["slag"] = 0.0
                }
            },
            ["fuel"] = {
                ["coal"] = 0.0,            
            },
            ["input"] = {
                ["smeltable_junk"] = 0.0
            },
            ["output"] = {
                ["iron"] = 0.0,
                ["copper"] = 0.0,
                ["slag"] = 0.0
            },
            ["lastSmeltTime"] = 0.0
        }
    end
    PLUGIN.updateClientTable(ID)
end

function PLUGIN.genSmeltCheck(ID)
    local values = PLUGIN.values[ID]
    local lowestVal = 1
    if (RealTime() - values["lastSmeltTime"] < PLUGIN.staticValues[PLUGIN.class[ID]]["smeltTime"] / 128) then 
        return false 
    end
    for category, amt in pairs(values["fuel"]) do
        if amt < lowestVal then 
            lowestVal = amt 
        end
    end
    if values["internal"]["input"]["amount"] < lowestVal then
        lowestVal = values["internal"]["input"]["amount"]
    end
    if (lowestVal <= 0.1) then
        values["lastSmeltTime"] = RealTime()
        return false
    else
        return true
    end
end

function PLUGIN.physAddResource(ID, item, entityItem)
    if (!PLUGIN.list[ID].open) then 
        return false 
    end
    local values = PLUGIN.values[ID]
    local currAmt
    local type
    local max
    local itemAmt = item:GetData("quantity", 1)
    for _, Type in pairs({"input", "fuel"}) do
        for category, amt in pairs(values[Type]) do
            if item.type == category then
                currAmt = amt
                type = Type
                max = PLUGIN.staticValues[PLUGIN.class[ID]]["maxValues"][Type]
                break
            end
        end
    end

    if (type == "input") then
        if values["internal"]["input"]["amount"] >= PLUGIN.staticValues[PLUGIN.class[ID]]["maxValues"]["input"] then 
            return false 
        end
    else
        if values["fuel"][item.type] >= PLUGIN.staticValues[PLUGIN.class[ID]]["maxValues"]["fuel"] then 
            return false 
        end
    end
    if (!currAmt) then return false end
    PLUGIN.genSmeltCheck(ID)
    if currAmt + itemAmt > max then
        local amtToAdd = max - currAmt
        if !pcall(function ()                                                   -- if item is in inv, kept for safety
            item:SetData("quantity", itemAmt - amtToAdd, ix.inventory.Get(item.invID):GetReceivers())
        end) then
            item:SetData("quantity", itemAmt - amtToAdd)  -- if the item is not in an inventory (most probable)
        end
        values[type][item.type] = max
    else
        values[type][item.type] = currAmt + itemAmt
        if !pcall(function ()                                                   
            entityItem:Remove()
        end) then                                                               
            item:Remove()                                                       -- if item is in inv, kept for safety
        end
    end
    PLUGIN.onAddInput(ID)
    PLUGIN.updateClientTable(ID)
end

function PLUGIN.onAddInput(smelterID)
    local values = PLUGIN.values[smelterID]
    for resource, amt in pairs(values["input"]) do
        if amt > 0 then
            local interInput = values["internal"]["input"]
            local modifier
            local rdm = math.random(70,90) / 100
            if (interInput["amount"] <= 0) then
                modifier = 1
            else
                modifier = amt / (interInput["amount"] + amt)
            end
            interInput["iron"] = interInput["iron"] * (1 - modifier) + (modifier * rdm)
            interInput["impurities"] = interInput["impurities"] * (1-modifier) + math.random(20,80) * modifier
            interInput["carbon"] = math.random(20,80)
            interInput["slag"] = interInput["slag"] * (1 - modifier) + modifier * (1 - rdm)
            interInput["amount"] = interInput["amount"] + amt
        end
        values["input"][resource] = 0
    end
    PLUGIN.generativeSmelt(smelterID)
end

function PLUGIN.generativeSmelt(smelterID)
    local values = PLUGIN.values[smelterID]
    local staticValues = PLUGIN.staticValues[PLUGIN.class[smelterID]]
    local smelted = (RealTime() - values["lastSmeltTime"]) / staticValues["smeltTime"]
    local input = values["internal"]["input"]
    local output = values["internal"]["output"]
    if (RealTime() - values["lastSmeltTime"] < staticValues["smeltTime"] / 128) then return end
    --- check the amount smelted
    if(input["amount"] < smelted) then 
        smelted = input["amount"]
        if (input["amount"] <= 0.1) then return end
    end
    for fuelType, efficiency in pairs(staticValues["fuelEfficiency"]) do
        local fuelCapacity = values["fuel"][fuelType] * staticValues["fuelEfficiency"][fuelType]
        if (fuelCapacity <= 0.1) then return end
        if smelted > fuelCapacity then
            smelted = fuelCapacity
        end
    end
    if (smelted <= 0) then return end

    values["lastSmeltTime"] = RealTime()
    for fuelType, efficiency in pairs(staticValues["fuelEfficiency"]) do
        fuelLost = smelted / staticValues["fuelEfficiency"][fuelType]
        values["fuel"][fuelType] = values["fuel"][fuelType] - fuelLost
    end
    local modifier = smelted / (output["amount"] + smelted)
    for var, amt in pairs(input) do
        if (var == "amount") then
            output[var] = output[var] + amt
        else
            output[var] = output[var] * (1 - modifier) + modifier * amt
        end
    end
    input["amount"] = input["amount"] - smelted
    PLUGIN.updateClientTable(smelterID)
end

function PLUGIN.outputResource ()
    
end