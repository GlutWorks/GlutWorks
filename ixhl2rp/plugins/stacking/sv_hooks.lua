local PLUGIN = PLUGIN

util.AddNetworkString("ixStackSplit")

-- The shortest time between two split answers from one player. Each answer names its stack, so two prompts open
-- at once both work; this only stops a client from flooding new instances.
PLUGIN.splitInterval = 0.25

-- Returns nothing, so other plugins still decide whether the trade happens.
function PLUGIN:CanPlayerTradeWithVendor(client, vendor, uniqueID, bSelling)
	if (ix.stack.IsStackable(uniqueID)) then
		ix.stack.PrepareVendorTrade(client, vendor, uniqueID, bSelling)
	end
end

function PLUGIN:CharacterVendorTraded()
	ix.stack.EndVendorTrade()
end

-- The answer to the Split prompt the client opens from the item menu: the stack's instance ID and the typed text.
net.Receive("ixStackSplit", function(length, client)
	if ((client.ixStackSplitNext or 0) > CurTime()) then
		return
	end

	client.ixStackSplitNext = CurTime() + PLUGIN.splitInterval

	local itemID = net.ReadUInt(32)
	local text = net.ReadString()
	local item = ix.item.instances[itemID]

	if (!item or !ix.stack.IsStackable(item)) then
		return client:NotifyLocalized("stackInvalid")
	end

	-- The same gate Helix applies to every item action (tied, ragdolled, dead, and other plugins' rules).
	if (hook.Run("CanPlayerInteractItem", client, "split", itemID, {}) == false) then
		return
	end

	if (#text > 32) then
		return client:NotifyLocalized("stackSplitInvalid")
	end

	local bSuccess, reason, argument = ix.stack.Split(client, item, text)

	if (!bSuccess) then
		client:NotifyLocalized(reason, argument)
	end
end)
