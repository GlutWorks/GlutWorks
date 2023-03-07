net.Receive( "glutClientSyncResources", function(_, ply)
    net.Start( "glutServerSyncResources")
        net.WriteTable(PLUGIN.refine.values)
    net.Send(ply)
end )

function PLUGIN.refine.sendStationResources(smelterID)
    net.Start( "glutServerSendResource")
        net.WriteUInt(smelterID, 8)
        net.WriteTable(PLUGIN.refine.values[smelterID])
    net.Broadcast()
end