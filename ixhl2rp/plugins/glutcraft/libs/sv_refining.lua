local PLUGIN = PLUGIN

PLUGIN.refine.inputs = {
    ["iron1_junk"] = {["carbon"] = , ["impurities"] = , ["iron"] = , ["copper"] = }, 
    ["iron2_junk"] = {["carbon"] = , ["impurities"] = , ["iron"] = , ["copper"] = }, 
    ["iron3_junk"] = {["carbon"] = , ["impurities"] = , ["iron"] = , ["copper"] = }, 
    ["iron4_junk"] = {["carbon"] = , ["impurities"] = , ["iron"] = , ["copper"] = }, 
    ["iron5_junk"] = {["carbon"] = , ["impurities"] = , ["iron"] = , ["copper"] = }, 
    ["iron6_junk"] = {["carbon"] = , ["impurities"] = , ["iron"] = , ["copper"] = }, 
    ["iron7_junk"] = {["carbon"] = , ["impurities"] = , ["iron"] = , ["copper"] = }
}
PLUGIN.refine.other = {
    ["coal"] = {}, 
    ["metal_scrap"] = {}, 
}
PLUGIN.refine.internalValues = {
	"carbon",		-- Value of carbon (0-1) (0.5 optimal) that is supposed to be 'tuned' to the right value. Going to cast or wrought iron decreases quality.
	"output",		-- The amount of output
	"impurities",	-- Value (0-1) of impurities. Taking out slag reduces this amount
	"iron",         -- percent iron
	"copper"
}

function PLUGIN.refine.addResource(item, smelter)
    for _, resource in pairs(PLUGIN.refine.inputs) do
        if (item.category == "Junk") then
            smelter:SetNetVar(resource, smelter:GetNetVar(resource) + 1)
            item:Remove()
            return true
        end
    end