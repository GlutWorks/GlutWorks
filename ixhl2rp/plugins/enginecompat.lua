
local PLUGIN = PLUGIN

PLUGIN.name = "Engine Compatibility"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Keeps the pinned Helix working on current Garry's Mod builds."

if (CLIENT) then
	-- Current Garry's Mod builds raise an error when surface.DrawPoly gets fewer than three vertices, where
	-- older ones drew nothing. Every arc Helix builds (the hold-to-pick-up indicator) ends in quads whose
	-- far corners are nil, so each frame of a pick-up errored. The length operator is no use on a table
	-- with holes, hence the explicit test.
	function ix.util.DrawPrecachedArc(arc)
		for _, polygon in ipairs(arc) do
			if (polygon[1] and polygon[2] and polygon[3]) then
				surface.DrawPoly(polygon)
			end
		end
	end
end
