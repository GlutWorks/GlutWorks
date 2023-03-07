-- test 
net.Receive("glutServerSendResource", function (_, _)
    PLUGIN.refine.values[net.ReadUInt(8)] = net.ReadTable()
end)
