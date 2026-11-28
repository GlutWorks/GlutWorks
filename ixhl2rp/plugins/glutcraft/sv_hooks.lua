local PLUGIN = PLUGIN

function PLUGIN:SaveData()
	ix.station.Save()
end

function PLUGIN:LoadData()
	ix.station.Load()
end
