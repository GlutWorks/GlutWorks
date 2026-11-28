local PLUGIN = PLUGIN

PLUGIN.name = "Fieldworks"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Excavate and build a workshop on a surveyed plot."

-- Offsets are measured from the ground under the supply crate. The open end is at x = 28.
local longPanel = "models/hunter/plates/plate2x4.mdl"
local timber = "models/props_wasteland/wood_fence01a"
local stone = "models/hunter/blocks/cube2x2x2.mdl"

PLUGIN.pieces = {
	left = {label = "Raise left wall", item = "wooden_scrap", cost = 2, flag = 1,
		model = longPanel, material = timber, pos = Vector(124, -2, 48), ang = Angle(90, 90, 0)},
	right = {label = "Raise right wall", item = "wooden_scrap", cost = 2, flag = 2,
		model = longPanel, material = timber, pos = Vector(124, 98, 48), ang = Angle(90, 90, 0)},
	back = {label = "Raise back wall", item = "wooden_scrap", cost = 1, flag = 4,
		model = "models/hunter/plates/plate2x2.mdl", material = timber, pos = Vector(222, 48, 48), ang = Angle(90, 0, 0)},
	roof = {label = "Fit sheet roof", item = "metal_scrap", cost = 2, flag = 8,
		model = longPanel, material = "metal/metalroof005a", pos = Vector(124, 48, 98), ang = Angle(0, 90, 0)},
	frontRock = {flag = 16, model = stone, material = "nature/rockwall010b", pos = Vector(76, 48, 48)},
	rearRock = {flag = 32, model = stone, material = "nature/rockwall010b", pos = Vector(172, 48, 48)},
	bench = {label = "Assemble workbench", item = "metal_scrap", cost = 4, pos = Vector(180, 48, 0)}
}

ix.command.Add("SurveySite", {
	adminOnly = true,
	arguments = ix.type.string,
	description = "Mark a flat workshop site extending away from you. Choose open or quarry.",
	OnRun = function(self, client, kind)
		kind = kind:lower()
		if (kind != "open" and kind != "quarry") then
			return "Choose open or quarry."
		end

		local trace = client:GetEyeTraceNoCursor()
		if (!trace.HitWorld or trace.HitSky or trace.HitNormal.z < 0.99 or
			trace.HitPos:DistToSqr(client:GetShootPos()) > 256 * 256) then
			return "Aim at level ground within reach of the survey."
		end

		local yaw = math.Round(client:EyeAngles().y / 90) * 90
		local site, reason = PLUGIN:Survey(trace.HitPos, yaw, kind == "quarry")
		if (!IsValid(site)) then return reason end

		return "The supply crate marks the entrance. Use it to build."
	end
})

ix.util.Include("sv_sites.lua")
