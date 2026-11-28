-- A piece of the arriving train's set (plugins/arriving/sh_layout.lua): a box in the carriage's own measures
-- (its origin is the carriage's, its box offset from it), or a prop that furnishes it. The server gives it
-- collision; the client draws the box as a tiled mesh, lit by the set's own lights (cl_plugin.lua). A door
-- slides by its `slide` when opened.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Train piece"
ENT.Spawnable = false
ENT.bNoPersist = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.bInteractive = false
ENT.PhysgunDisabled = true

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Kind")
	self:NetworkVar("String", 1, "PieceModel")
	self:NetworkVar("Vector", 0, "BoxMins")
	self:NetworkVar("Vector", 1, "BoxMaxs")
	self:NetworkVar("Bool", 0, "Opened")
end

local DOOR_TIME = 0.8

-- Collision, the same on both sides (the client's lets movement be predicted against it): a prop's own, or
-- the box. A box made by PhysicsInitBox is only traced (and so walked on) with custom collisions on.
function ENT:InitCollision()
	if (self:GetPieceModel() != "") then
		self:PhysicsInit(SOLID_VPHYSICS)
	else
		self:PhysicsInitBox(self:GetBoxMins(), self:GetBoxMaxs())
		self:SetSolid(SOLID_VPHYSICS)
		self:EnableCustomCollisions(true)
	end

	self:SetMoveType(MOVETYPE_NONE)

	local physics = self:GetPhysicsObject()

	if (IsValid(physics)) then
		physics:EnableMotion(false)
	end

	self.bCollides = true
end

if (SERVER) then
	function ENT:Initialize()
		local model = self:GetPieceModel()

		self:SetModel(model != "" and model or "models/hunter/blocks/cube025x025x025.mdl")
		self:InitCollision()
		self:SetUseType(SIMPLE_USE)
		self:DrawShadow(false)

		self.home = self:GetPos()
		self.amount = 0
	end

	function ENT:SetOpen(bOpen)
		self:SetOpened(bOpen)

		if (self:GetKind() == "door") then
			self:EmitSound(bOpen and "doors/door_metal_thin_open1.wav" or "doors/door_metal_thin_close2.wav", 60, 115, 0.6)
			self:NextThink(CurTime())
		end
	end

	function ENT:Think()
		if (self:GetKind() != "door" or !self.slide) then
			return
		end

		local target = self:GetOpened() and 1 or 0

		if (self.amount != target) then
			self.amount = math.Approach(self.amount, target, FrameTime() / DOOR_TIME)

			local slide = Vector(self.slide)

			slide:Rotate(self:GetAngles())
			self:SetPos(self.home + slide * math.ease.InOutSine(self.amount))

			-- a frozen physics object stays where it was unless it's moved too
			local physics = self:GetPhysicsObject()

			if (IsValid(physics)) then
				physics:SetPos(self:GetPos())
			end
		end

		self:NextThink(CurTime())

		return true
	end

	function ENT:Use(activator)
		if (self:GetKind() != "door" or self:GetOpened() or !IsValid(activator) or !activator:IsPlayer()) then
			return
		end

		local PLUGIN = ix.plugin.list.arriving
		local character = activator:GetCharacter()

		if (PLUGIN and PLUGIN:GetState(character) == PLUGIN.states.cabin) then
			activator:Notify("The door won't open. There's a mirror on the wall.")
		else
			activator:Notify("It won't open.")
		end

		self:EmitSound("doors/handle_pushbar_locked1.wav", 55, 100, 0.5)
	end
else
	-- What each kind of box looks like: its material and how many units one repeat of the texture covers.
	local looks = {
		floor = {texture = "wood/woodfloor007a", tile = 128},
		ceiling = {texture = "plaster/plasterceiling008a", tile = 128},
		wall = {texture = "wood/woodwall016a", tile = 128},
		door = {texture = "wood/woodwall016a", tile = 128},
		step = {texture = "tile/tilefloor012a", tile = 128},
		platform = {texture = "tile/tilewall009b", tile = 160},
		glass = {texture = "color/white", tile = 96, translucent = true, tint = "[0.25 0.28 0.3]", alpha = 0.06},
		dark = {color = Color(9, 11, 17)}
	}

	local materials = {}

	local function Material(kind)
		if (materials[kind]) then
			return materials[kind]
		end

		local look = looks[kind] or looks.wall
		local material

		if (look.color) then
			material = CreateMaterial("ixArrivingDark", "UnlitGeneric", {
				["$basetexture"] = "color/white",
				["$color"] = string.format("[%f %f %f]", look.color.r / 255, look.color.g / 255, look.color.b / 255)
			})
		else
			material = CreateMaterial("ixArriving_" .. kind, "VertexLitGeneric", {
				["$basetexture"] = look.texture,
				["$translucent"] = look.translucent and 1 or nil,
				["$alpha"] = look.alpha,
				["$color2"] = look.tint
			})
		end

		materials[kind] = material

		return material
	end

	-- The six faces of a box: the corner it starts at, the two edges it spans (texture u then v), its normal.
	local function Faces(mins, maxs)
		local size = maxs - mins

		return {
			{Vector(mins.x, mins.y, maxs.z), Vector(size.x, 0, 0), Vector(0, size.y, 0), Vector(0, 0, 1)}, -- top
			{Vector(mins.x, maxs.y, mins.z), Vector(size.x, 0, 0), Vector(0, -size.y, 0), Vector(0, 0, -1)}, -- bottom
			{Vector(mins.x, mins.y, maxs.z), Vector(size.x, 0, 0), Vector(0, 0, -size.z), Vector(0, -1, 0)}, -- -y
			{Vector(maxs.x, maxs.y, maxs.z), Vector(-size.x, 0, 0), Vector(0, 0, -size.z), Vector(0, 1, 0)}, -- +y
			{Vector(mins.x, maxs.y, maxs.z), Vector(0, -size.y, 0), Vector(0, 0, -size.z), Vector(-1, 0, 0)}, -- -x
			{Vector(maxs.x, mins.y, maxs.z), Vector(0, size.y, 0), Vector(0, 0, -size.z), Vector(1, 0, 0)} -- +x
		}
	end

	local CELL = 24

	-- The box as a mesh of small quads (for the lights to fall across it), its texture tiled in world units.
	-- A pane (`bPane`) is only its two broad faces: its thin edges would catch the light as bright lines.
	local function BuildMesh(mins, maxs, tile, bPane)
		local quads = {}
		local size = maxs - mins
		local thin = math.min(size.x, size.y, size.z)

		for _, face in ipairs(Faces(mins, maxs)) do
			local corner, edgeU, edgeV, normal = face[1], face[2], face[3], face[4]
			local lengthU, lengthV = edgeU:Length(), edgeV:Length()
			local across = math.abs(normal.x) * size.x + math.abs(normal.y) * size.y + math.abs(normal.z) * size.z

			if (lengthU > 0 and lengthV > 0 and (!bPane or across == thin)) then
				local stepsU, stepsV = math.max(1, math.ceil(lengthU / CELL)), math.max(1, math.ceil(lengthV / CELL))
				local dirU, dirV = edgeU / lengthU, edgeV / lengthV
				-- the texture keeps to the world: a wall's top is the texture's top
				local offsetU = corner:Dot(dirU) / tile
				local offsetV = (corner:Dot(dirV) + 120) / tile

				for i = 0, stepsU - 1 do
					for j = 0, stepsV - 1 do
						local u0, u1 = lengthU * i / stepsU, lengthU * (i + 1) / stepsU
						local v0, v1 = lengthV * j / stepsV, lengthV * (j + 1) / stepsV

						quads[#quads + 1] = {
							corner + dirU * u0 + dirV * v0, corner + dirU * u1 + dirV * v0,
							corner + dirU * u1 + dirV * v1, corner + dirU * u0 + dirV * v1,
							u0 / tile + offsetU, u1 / tile + offsetU, v0 / tile + offsetV, v1 / tile + offsetV, normal
						}
					end
				end
			end
		end

		local built = Mesh()

		mesh.Begin(built, MATERIAL_QUADS, #quads)

		for _, quad in ipairs(quads) do
			local u0, u1, v0, v1, normal = quad[5], quad[6], quad[7], quad[8], quad[9]
			local uv = {{u0, v0}, {u1, v0}, {u1, v1}, {u0, v1}}

			for k = 1, 4 do
				mesh.Position(quad[k])
				mesh.Normal(normal)
				mesh.TexCoord(0, uv[k][1], uv[k][2])
				mesh.Color(255, 255, 255, 255)
				mesh.AdvanceVertex()
			end
		end

		mesh.End()

		return built
	end

	function ENT:EnsureMesh()
		local mins, maxs = self:GetBoxMins(), self:GetBoxMaxs()

		if (self.mesh and self.builtFor == tostring(mins) .. tostring(maxs)) then
			return self.mesh
		end

		if (self.mesh) then
			self.mesh:Destroy()
		end

		local look = looks[self:GetKind()] or looks.wall

		self.mesh = BuildMesh(mins, maxs, look.tile or 128, self:GetKind() == "glass")
		self.builtFor = tostring(mins) .. tostring(maxs)
		self:SetRenderBounds(mins, maxs)

		return self.mesh
	end

	function ENT:Initialize()
		self:SetupClient()
	end

	function ENT:SetupClient()
		if (self.bCollides) then
			return true
		end

		local kind = self:GetKind()

		if (kind == "" or (kind != "prop" and self:GetBoxMins() == self:GetBoxMaxs())) then
			return false
		end

		if (kind != "dark") then
			self:InitCollision()
		else
			self.bCollides = true
		end

		if (kind != "prop") then
			self:SetRenderBounds(self:GetBoxMins(), self:GetBoxMaxs())
		end

		return true
	end

	function ENT:Think()
		if (!self:SetupClient()) then
			self:SetNextClientThink(CurTime() + 0.2)
			return true
		end

		-- a shut door is outlined like anything usable (tapping Use tries it); a sliding door's collision
		-- follows it
		if (self:GetKind() == "door") then
			self.bInteractive = !self:GetOpened()
			self.interactionTap = true

			local physics = self:GetPhysicsObject()

			if (IsValid(physics) and physics:GetPos() != self:GetPos()) then
				physics:SetPos(self:GetPos())
				physics:SetAngles(self:GetAngles())
			end
		end
	end

	function ENT:OnPopulateEntityInfo(container)
		if (self:GetKind() != "door") then
			return
		end

		local name = container:AddRow("name")
		name:SetImportant()
		name:SetText("Sliding door")
		name:SizeToContents()

		local description = container:AddRow("description")
		description:SetText(self:GetOpened() and "It stands open." or "It's shut, and doesn't give.")
		description:SizeToContents()
	end

	function ENT:OnRemove()
		if (self.mesh) then
			self.mesh:Destroy()
			self.mesh = nil
		end
	end

	function ENT:DrawBox(kind)
		local built = self:EnsureMesh()

		if (!built) then
			return
		end

		render.SetMaterial(Material(kind or self:GetKind()))
		cam.PushModelMatrix(self:GetWorldTransformMatrix())
			built:Draw()
		cam.PopModelMatrix()
	end

	-- The piece's box in the world, as an axis-aligned box (the set only turns in quarter turns), for
	-- choosing the lights that reach it.
	function ENT:WorldBox()
		if (self:GetKind() == "prop") then
			local center = self:WorldSpaceCenter()

			return center, center
		end

		local a, b = self:LocalToWorld(self:GetBoxMins()), self:LocalToWorld(self:GetBoxMaxs())

		return Vector(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)),
			Vector(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
	end

	function ENT:DrawLit(kind)
		local PLUGIN = ix.plugin.list.arriving

		if (PLUGIN) then PLUGIN:BeginSetLighting(self:WorldBox()) end

		if (kind == "prop") then
			self:DrawModel()
		else
			self:DrawBox(kind)
		end

		if (PLUGIN) then PLUGIN:EndSetLighting() end
	end

	function ENT:Draw()
		local kind = self:GetKind()

		if (kind == "glass") then
			return
		elseif (kind == "dark") then
			self:DrawBox()
		elseif (kind == "platform" or kind == "step") then
			-- the platform is there only while the train stands at it; riding, it's the night outside
			if (GetNetVar("arrivingTrain") == "standing") then
				self:DrawLit(kind)
			end
		else
			self:DrawLit(kind)
		end
	end

	function ENT:DrawTranslucent()
		if (self:GetKind() == "glass") then
			self:DrawLit("glass")
		end
	end
end
