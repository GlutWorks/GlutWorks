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
PLUGIN.maxValues = PLUGIN.maxValues or {}
PLUGIN.lastSmeltTime = PLUGIN.lastSmeltTime or {}
PLUGIN.maxValues = PLUGIN.maxValues or {}

PLUGIN.maxValues = {
    ["interactive_smelter"] = {
        ["coal"] = 20,
        ["smeltable_junk"] = 20
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
            ["internal"] = {
                ["carbon"] = 0,		-- Value of carbon (0-1) (0.5 optimal) that is supposed to be 'tuned' to the right value. Going to cast or wrought iron decreases quality.
                ["output"] = 0,		-- The amount of output
                ["impurities"] = 0,	-- Value (0-1) of impurities. Taking out slag reduces this amount
                ["iron"] = 0,         -- percent iron
                ["copper"] = 0,
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

function PLUGIN.physAddResource(ID, item, entityItem)
    local values = PLUGIN.values[ID]
    local currAmt
    local type
    local max
    for _, Type in pairs({"input", "fuel"}) do
        for category, amt in pairs(values[Type]) do
            if item.category == category then
                max = PLUGIN.maxValues[PLUGIN.class[ID]][category]
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
end

function generativeSmelt(smelterID)
    local values = PLUGIN.values[smelterID]
    local timeSmelted = math.floor( (RealTime() - PLUGIN.lastSmeltTime) / PLUGIN.smeltTime[PLUGIN.class[smelterID]] )
    PLUGIN.lastSmeltTime[smelterID] = RealTime()
    -- add a constraint based on coal.
    for _, amt in pairs(values["input"]) do
        if amt > 0 then
            local internalTotal = 0
            for outputType, _ in pairs(values["output"]) do
                internalAmt = values["internal"][outputType]
                if (internalAmt) then
                    internalTotal = internalTotal + internalAmt 
                end
            end
            for outputType, outputAmt in pairs(values["output"]) do
                for outputType, _ in pairs(values["output"]) do
                    internalAmt = values["internal"][outputType]
                    if (internalAmt) then
                        addOutput = timeSmelted * internalAmt / internalTotal
                        values["output"][outputType] = values["output"][outputType] 
                            + addOutput
                        values["internal"][outputType] = values["internal"][outputType]
                            - addOutput
                    end
                end
            end
        end

    end
    PLUGIN.updateClientTable(smelterID)
end