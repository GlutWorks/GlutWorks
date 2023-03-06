local PLUGIN = PLUGIN

net.Receive( "glutAddResource", function(_, _)
    addResource(Player(net.ReadUInt(8)), net.ReadEntity(), net.ReadString(), tonumber(net.ReadInt(8)))
end )
net.Receive( "glutSmelt", function(_, _)
    startSmelt(net.ReadEntity())
end )

