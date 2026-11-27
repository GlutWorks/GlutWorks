
local PLUGIN = PLUGIN

net.Receive("ixEditMyNotes", function(length, client)
	local text = net.ReadString()
	local status = PLUGIN:UpdateNotes(client, text)

	if (status == nil) then
		return
	end

	if (status == true) then
		status = 0
	end

	net.Start("ixCloseMyNotes")
		net.WriteUInt(status, 6)
	net.Send(client)
end)
