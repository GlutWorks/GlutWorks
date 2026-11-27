local PLUGIN = PLUGIN

PLUGIN.name = "Container Guard"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Stops a container without an inventory from deleting every world item when it is removed."

-- A container entity that never got an inventory reports ID 0, which is also the ID of the
-- world inventory. Helix's ix_container deletes its inventory's rows when it is removed, so
-- removing such a container (for example one spawned bare from the spawn menu) deletes the
-- database rows of every item lying in the world.
if (SERVER) then
	function PLUGIN:InitializedPlugins()
		local stored = scripted_ents.GetStored("ix_container")
		local container = stored and stored.t

		if (!container or !container.OnRemove or container.ixGuarded) then return end

		local onRemove = container.OnRemove

		function container:OnRemove()
			if ((self:GetID() or 0) == 0) then return end

			return onRemove(self)
		end

		container.ixGuarded = true
	end
end
