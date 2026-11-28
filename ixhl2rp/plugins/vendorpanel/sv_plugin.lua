local PLUGIN = PLUGIN

util.AddNetworkString("ixVendorPanelMoney")

-- Helix sends a vendor's money as an unsigned 16-bit number (0 for a vendor that keeps no money at all, and wrong
-- from 65,536 up), so this says whether the vendor keeps money and how much, in 32 bits: to a player right after
-- the vendor opens for them, and to everyone trading with it whenever its money changes.
function PLUGIN:SendVendorMoney(receivers, vendor)
	net.Start("ixVendorPanelMoney")
		net.WriteEntity(vendor)
		net.WriteBool(vendor.money != nil)
		net.WriteUInt(math.Clamp(math.floor(tonumber(vendor.money) or 0), 0, 4294967295), 32)
	net.Send(receivers)
end

-- Wraps the vendor entity's Use, which opens the trade, and SetMoney, through which every change to its money
-- goes (helix/plugins/vendor/entities/entities/ix_vendor.lua).
function PLUGIN:WrapVendor()
	local stored = scripted_ents.GetStored("ix_vendor")
	local ENT = stored and stored.t

	if (!ENT) then
		return
	end

	if (!ENT.ixVendorPanelUse) then
		ENT.ixVendorPanelUse = ENT.Use

		function ENT:Use(activator, ...)
			local result = self:ixVendorPanelUse(activator, ...)

			if (IsValid(activator) and activator:IsPlayer() and activator.ixVendor == self) then
				PLUGIN:SendVendorMoney(activator, self)
			end

			return result
		end
	end

	if (!ENT.ixVendorPanelSetMoney) then
		ENT.ixVendorPanelSetMoney = ENT.SetMoney

		function ENT:SetMoney(value, ...)
			local result = self:ixVendorPanelSetMoney(value, ...)

			if (istable(self.receivers) and #self.receivers > 0) then
				PLUGIN:SendVendorMoney(self.receivers, self)
			end

			return result
		end
	end
end

function PLUGIN:InitializedPlugins()
	self:WrapVendor()
end

PLUGIN:WrapVendor()
