local PLUGIN = PLUGIN

PLUGIN.name = "Logging off"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Where you leave from matters: somewhere safe you leave cleanly; anywhere else your body sleeps where you stood."
PLUGIN.readme = [[
Quitting is never blocked; what it does depends on where you are (the owner, 2026-11-28).

- `ix.logoff.GetSafety(client[, pos])` says how safe it is to leave from a place: "safe", "ordinary" or
  "dangerous". Dangerous beats safe wherever both apply.
- Helix areas of two more types say so for a place: `safe` and `dangerous`, drawn with Helix's own
  area editor (`/AreaEdit`).
- Any plugin can say so too, through the `GetLogOffSafety(client, pos)` hook (returning "safe" or
  "dangerous"): `arriving` says the station is safe. Later: your own flat, a door you hold the key to, a
  faction's own places.
- Switching characters needs a safe place (`arriving`'s departures).
- Leaving anywhere else leaves your body asleep where you stood (`sv_sleep.lua`): for `logoffSleepTime`
  (5 minutes) somewhere ordinary; the whole time you're away somewhere dangerous, or anywhere when your
  body must stay: you're wanted (the `ShouldSleepWhileAway` hook) or you've hurt or been hurt by another
  player within `logoffFightMemory` (5 minutes). A body that must stay can't leave cleanly even from a safe
  place, nor take the train out.
- A sleeping body can be searched (its character's own inventory, through a search as long as a corpse's)
  and hurt: it has the health its player left with, and at none it dies, becomes a corpse like any other,
  and its character dies as they come back (the death screen and respawn, with no second body).
- Coming back to a body still there, you wake where it lies (wherever it was dragged), as hurt as it is,
  and are told if someone went through your pockets.
- Not yet: bodies don't outlast a server restart (you come back where you stood); a sleeping body shows its
  model, skin and bodygroups but not what's worn over them.
]]

ix.config.Add("logoffSleepTime", 300, "How long a body left asleep somewhere ordinary stays (seconds).", nil, {
	data = {min = 0, max = 3600},
	category = "Logging off"
})

ix.config.Add("logoffFightMemory", 300, "For how long after hurting another player, or being hurt by one, a body left asleep stays the whole time away (seconds).", nil, {
	data = {min = 0, max = 3600},
	category = "Logging off"
})

ix.logoff = ix.logoff or {}

ix.logoff.SAFE = "safe"
ix.logoff.ORDINARY = "ordinary"
ix.logoff.DANGEROUS = "dangerous"

function PLUGIN:SetupAreaProperties()
	ix.area.AddType("safe", "Safe (leave cleanly, switch characters)")
	ix.area.AddType("dangerous", "Dangerous (leaving always leaves you asleep)")
end

--- How safe it is for a player to leave from where they are (or from `pos`): ix.logoff.SAFE, ORDINARY or
-- DANGEROUS. Areas of type `safe` or `dangerous` and the GetLogOffSafety hook decide; dangerous wins. Staff
-- watching in noclip are where they were before it (the place Spawn Saver keeps).
function ix.logoff.GetSafety(client, pos)
	pos = pos or ((client.ixObsData and client.ixObsData[1] or client:GetPos()) + client:OBBCenter())

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

-- the body left asleep by leaving anywhere else
ix.util.Include("sv_sleep.lua")
ix.util.Include("cl_sleep.lua")
