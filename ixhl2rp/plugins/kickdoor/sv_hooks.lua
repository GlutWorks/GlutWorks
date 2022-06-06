
local PLUGIN = PLUGIN

util.AddNetworkString("ixItemSpawnerChanges")

function PLUGIN:SendThirdpersonInfo()
    net.Start("ixItemSpawnerEdit")
        net.WriteTable(PLUGIN.spawner.positions)
    net.Send(client)
end