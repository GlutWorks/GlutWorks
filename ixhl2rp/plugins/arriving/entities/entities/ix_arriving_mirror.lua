-- A cabin's mirror on the arriving train (plugins/arriving). Use turns the view round to look at you from
-- the glass (cl_plugin.lua) and holds you still while you choose who you are (sv_plugin.lua, Choose).

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Mirror"
ENT.Spawnable = false
ENT.bNoPersist = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.bInteractive = true
ENT.interactionTap = true
ENT.PhysgunDisabled = true

-- The glass, across and up (units), and the frame round it.
ENT.glassWide, ENT.glassHigh, ENT.frame = 30, 52, 3

function ENT:Initialize()
	local half = Vector(1.5, self.glassWide / 2 + self.frame, self.glassHigh / 2 + self.frame)

	if (SERVER) then
		self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
		self:SetUseType(SIMPLE_USE)
		self:DrawShadow(false)
	else
		self:SetRenderBounds(-half - Vector(1, 0, 0), half)
	end

	-- the same box on both sides: the client's aim (and so Use) finds the glass, not the wall behind it
	self:PhysicsInitBox(-half, half)
	self:SetSolid(SOLID_VPHYSICS)
	self:EnableCustomCollisions(true)
	self:SetMoveType(MOVETYPE_NONE)

	local physics = self:GetPhysicsObject()

	if (IsValid(physics)) then
		physics:EnableMotion(false)
	end
end

if (SERVER) then
	function ENT:Use(activator)
		local PLUGIN = ix.plugin.list.arriving

		if (PLUGIN and IsValid(activator) and activator:IsPlayer()) then
			PLUGIN:LookIn(activator, self)
		end
	end
else
	function ENT:OnPopulateEntityInfo(container)
		local name = container:AddRow("name")
		name:SetImportant()
		name:SetText("Mirror")
		name:SizeToContents()

		local description = container:AddRow("description")
		description:SetText("A narrow mirror screwed to the wall. Use it to look at yourself.")
		description:SizeToContents()
	end

	local frameMaterial = CreateMaterial("ixArrivingMirrorFrame", "VertexLitGeneric", {["$basetexture"] = "metal/metalwall061f"})
	-- old silvered glass: grey-green, faintly bright (the map's own cubemap would show the sky outside)
	local glassMaterial = CreateMaterial("ixArrivingMirrorGlass", "VertexLitGeneric", {
		["$basetexture"] = "metal/milmirror001",
		["$color2"] = "[0.7 0.74 0.72]",
		["$selfillum"] = 1,
		["$selfillumtint"] = "[0.05 0.055 0.055]"
	})

	function ENT:Draw()
		local PLUGIN = ix.plugin.list.arriving
		local pos, ang = self:GetPos(), self:GetAngles()
		local forward = ang:Forward()
		local w, h, f = self.glassWide, self.glassHigh, self.frame

		if (PLUGIN) then PLUGIN:BeginSetLighting(pos + forward * 8) end

		render.SetMaterial(frameMaterial)
		render.DrawBox(pos, ang, Vector(-1.5, -w / 2 - f, -h / 2 - f), Vector(0.5, w / 2 + f, h / 2 + f), color_white)

		-- the texture's pane alone (a dark strip runs down its left): u 63 to 193 of 256
		local middle, side, up = pos + forward * 0.6, ang:Right() * (w / 2), ang:Up() * (h / 2)
		local u0, u1 = 63 / 256, 193 / 256

		render.SetMaterial(glassMaterial)
		mesh.Begin(MATERIAL_QUADS, 1)
			for _, corner in ipairs({
				{middle + side + up, u0, 0}, {middle - side + up, u1, 0},
				{middle - side - up, u1, 1}, {middle + side - up, u0, 1}
			}) do
				mesh.Position(corner[1])
				mesh.Normal(forward)
				mesh.TexCoord(0, corner[2], corner[3])
				mesh.Color(255, 255, 255, 255)
				mesh.AdvanceVertex()
			end
		mesh.End()

		if (PLUGIN) then PLUGIN:EndSetLighting() end
	end
end
