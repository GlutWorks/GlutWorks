local PLUGIN = PLUGIN

PLUGIN.name = "World UI"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "A panel that exists in the world, beside the thing it is about, chosen by aiming at it."
PLUGIN.readme = [[
`ix.worldui` (libs/cl_worldui.lua) draws a short list of rows on a surface in the world, anchored to an
entity or a position and facing the player. The row the player aims at is highlighted; there is no
cursor and the player keeps moving and looking freely. See the top of that file for the API.
]]

if (CLIENT) then
	-- the open panel's wheel, left and right click (see the end of libs/cl_worldui.lua)
	function PLUGIN:PlayerBindPress(client, bind, bPressed)
		return ix.worldui.PlayerBindPress(client, bind, bPressed)
	end

	function PLUGIN:InitializedPlugins()
		ix.worldui.GuardBinds(self)
	end

	ix.worldui.GuardBinds(PLUGIN)
end
