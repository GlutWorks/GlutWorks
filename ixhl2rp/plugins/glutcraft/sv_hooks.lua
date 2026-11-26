local PLUGIN = PLUGIN

function PLUGIN:SaveData()
	ix.station.Save()
end

function PLUGIN:LoadData()
	ix.station.Load()
end

-- Helix allows entity menu choices only within 96 units of the entity's origin, which for the
-- larger stations is inside the model. A station checks the player's state and the distance to
-- its own surface itself (ix_station.lua OnOptionSelected), so that check is the limit for them.
function PLUGIN:CanPlayerInteractEntity(client, entity, option, data)
	if (entity.IsStation) then
		return true
	end
end
