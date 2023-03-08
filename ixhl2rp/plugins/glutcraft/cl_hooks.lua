local PLUGIN = PLUGIN
net.Receive("glutServerSendResource", function ()
    print("glutServerSendResource")
    local smelterID = net.ReadUInt(8)
    local table = net.ReadTable()
    PLUGIN.refine.values[smelterID] = table
end)
