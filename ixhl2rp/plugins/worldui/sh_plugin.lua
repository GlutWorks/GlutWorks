local PLUGIN = PLUGIN

PLUGIN.name = "World UI"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Panels and cases that exist in the world, handled by aiming at them."
PLUGIN.readme = [[
`ix.worldui` (libs/cl_worldui.lua) draws a short list of rows of text on a surface in the world, anchored
to an entity or a position and facing the player. The row the player aims at is highlighted; there is no
cursor and the player keeps moving and looking freely. `ix.worldcase` (libs/cl_worldcase.lua) holds an
open case in front of the player: grids of cells drawn as a lined tray with real models lying in them,
handled by aiming, Use and carrying with the attack button. See the top of each file for the API.
]]

if (CLIENT) then
	-- the open panel's wheel, left and right click, and an open case's Use and attack (see the end of
	-- libs/cl_worldui.lua)
	function PLUGIN:PlayerBindPress(client, bind, bPressed, code)
		return ix.worldui.PlayerBindPress(client, bind, bPressed, code)
	end

	function PLUGIN:InitializedPlugins()
		ix.worldui.GuardBinds(self)
	end

	ix.worldui.GuardBinds(PLUGIN)
end
