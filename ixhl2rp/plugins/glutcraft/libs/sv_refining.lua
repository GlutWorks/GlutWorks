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

PLUGIN.refine.IDCounter = PLUGIN.refine.IDCounter or 0
PLUGIN.refine.list = PLUGIN.refine.list or {}
PLUGIN.refine.class = PLUGIN.refine.class or {}
PLUGIN.refine.values = PLUGIN.refine.values or {}
PLUGIN.refine.maxValues = PLUGIN.refine.maxValues or {}
PLUGIN.refine.lastSmeltTime = PLUGIN.refine.lastSmeltTime or {}


function PLUGIN.refine.initSmelter(smelter)
    local ID = PLUGIN.refine.IDCounter + 1
    PLUGIN.refine.IDCounter = ID
    smelter:SetNetVar("ID", ID)
    PLUGIN.refine.lastSmeltTime[ID] = RealTime()
    PLUGIN.refine.list[ID] = smelter
    PLUGIN.refine.class[ID] = smelter.uniqueID

    if (smelter.uniqueID == "interactive_smelter") then
        PLUGIN.refine.values[ID] = {
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
            }
            ["input"] = {
                ["smeltable_junk"] = 0
            }
            ["output"] = {
                ["iron"] = 0,
                ["copper"] = 0,
                ["slag"] = 0
            }
            ["lastSmeltTime"] = 0
        }
    end
end



function generativeSmelt(smelterID)
    local timeSmelted = math.floor( (RealTime() - PLUGIN.refine.lastSmeltTime) / PLUGIN.refine.smeltTime[PLUGIN.refine.class[smelterID]] )
    PLUGIN.refine.lastSmeltTime[smelterID] = RealTime()
    -- add a constraint based on coal.
    for _, amt in pairs(PLUGIN.refine.values[smelterID]["input"]) do
        if amt > 0 then
            local internalTotal = 0
            for outputType, _ in pairs(PLUGIN.refine.values[smelterID]["output"]) do
                internalAmt = PLUGIN.refine.values[smelterID]["internal"][outputType]
                if (internalAmt) then
                    internalTotal = internalTotal + internalAmt 
                end
            end
            for outputType, outputAmt in pairs(PLUGIN.refine.values[smelterID]["output"]) do
                for outputType, _ in pairs(PLUGIN.refine.values[smelterID]["output"]) do
                    internalAmt = PLUGIN.refine.values[smelterID]["internal"][outputType]
                    if (internalAmt) then
                        PLUGIN.refine.values[smelterID]["output"][outputType] = PLUGIN.refine.values[smelterID]["output"][outputType] 
                            + timeSmelted * (internalAmt / internalTotal)
                    end
                PLUGIN.refine.values[smelterID]["input"][outputType] = PLUGIN.refine.values[smelterID]["input"][type] - smelted
            end
            PLUGIN.refine.values[smelterID]["internal"] = PLUGIN.refine.values[smelterID]["internal"] + smelted
        end
    end
end