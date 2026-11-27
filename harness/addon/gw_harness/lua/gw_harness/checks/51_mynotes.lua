-- Notes (mynotes): the receivers cope with a player without a character and apply the cooldown.

local Lib = GWH.Lib
local OtherBot, Scoped, Receive = Lib.OtherBot, Lib.Scoped, Lib.Receive

GWH.Check("hygiene: notes receivers cope with no character and cooldown", function(fail)
	return Scoped(function(defer)
		local client = OtherBot()
		local plugin = ix.plugin.list.mynotes
		local id = client:GetNetVar("char")
		defer(function() client:SetNetVar("char", id) end)

		client.ixNextNotes = nil
		client:SetNetVar("char", nil)

		Receive(net.Receivers.ixeditmynotes, client, {"nobody"})
		if (plugin:SendNotes(client) != nil) then fail("notes were sent to a player without a character") end

		client:SetNetVar("char", id)

		if (plugin:UpdateNotes(client, "remember the milk") != true) then fail("saving notes failed") end
		if (!isnumber(plugin:UpdateNotes(client, "again"))) then fail("the cooldown was not applied") end

		Receive(net.Receivers.ixeditmynotes, client, {"during cooldown"})
	end)
end)
