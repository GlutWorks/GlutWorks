hook.Add("Tick", "ixSmelterDraw", function()
    for _, ent in pairs(ents.FindByClass("ix_interactive_smelter")) do
        if (LocalPlayer():GetPos():Distance(ent:GetPos()) <= 128) then
            ent:Draw()
        end
    end
end)