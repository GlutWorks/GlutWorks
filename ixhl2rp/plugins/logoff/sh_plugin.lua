local PLUGIN = PLUGIN

PLUGIN.name = "Logging off"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Where you leave from matters: safe areas let you leave cleanly and switch characters; dangerous ones never do."
PLUGIN.readme = [[
Quitting is never blocked; what it does depends on where you are (the owner, 2026-11-28).

- `ix.logoff.GetSafety(client[, pos])` says how safe it is to leave from a place: "safe", "ordinary" or
  "dangerous". Dangerous beats safe wherever both apply.
- Helix areas of two more types say so for a place: `safe` and `dangerous`, drawn with Helix's own
  area editor (`/AreaEdit`).
- Any plugin can say so too, through the `GetLogOffSafety(client, pos)` hook (returning "safe" or
  "dangerous"): `arriving` says the station is safe. Later: your own flat, a door you hold the key to, a
  faction's own places.
- Switching characters needs a safe place (`arriving`'s departures). Leaving anywhere that isn't safe
  is for the sleeping body (to come).
]]

ix.logoff = ix.logoff or {}

ix.logoff.SAFE = "safe"
ix.logoff.ORDINARY = "ordinary"
ix.logoff.DANGEROUS = "dangerous"

function PLUGIN:SetupAreaProperties()
	ix.area.AddType("safe", "Safe (leave cleanly, switch characters)")
	ix.area.AddType("dangerous", "Dangerous (leaving always leaves you asleep)")
end

--- How safe it is for a player to leave from where they are (or from `pos`): ix.logoff.SAFE, ORDINARY or
-- DANGEROUS. Areas of type `safe` or `dangerous` and the GetLogOffSafety hook decide; dangerous wins.
function ix.logoff.GetSafety(client, pos)
	pos = pos or (client:GetPos() + client:OBBCenter())

	local bSafe = false

	for _, area in pairs(ix.area and ix.area.stored or {}) do
		if (pos:WithinAABox(area.startPosition, area.endPosition)) then
			if (area.type == ix.logoff.DANGEROUS) then
				return ix.logoff.DANGEROUS
			elseif (area.type == ix.logoff.SAFE) then
				bSafe = true
			end
		end
	end

	local said = hook.Run("GetLogOffSafety", client, pos)

	if (said == ix.logoff.DANGEROUS) then
		return ix.logoff.DANGEROUS
	elseif (bSafe or said == ix.logoff.SAFE) then
		return ix.logoff.SAFE
	end

	return ix.logoff.ORDINARY
end

--- Whether a player is somewhere they may leave cleanly from (and switch characters).
function ix.logoff.IsSafe(client, pos)
	return ix.logoff.GetSafety(client, pos) == ix.logoff.SAFE
end
