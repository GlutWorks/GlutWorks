net.Receive( "glutClientSyncResources", function(_, ply)
    net.Start( "glutServerSyncResources")
        net.WriteTable(PLUGIN.refine.values)
    net.Send(ply)
end )

