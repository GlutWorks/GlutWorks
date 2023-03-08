local PLUGIN = PLUGIN

net.Receive( "glutClientSyncResources", function(_, ply)
    net.Start( "glutServerSyncResources")
        net.WriteTable(PLUGIN.refine.values)
    net.Send(ply)
end )

hook.Add("Tick", "updatefunction123", function ()
    for ID, _ in pairs(PLUGIN.refine.list) do
        PLUGIN.refine.generativeSmelt(ID)
    end
end)