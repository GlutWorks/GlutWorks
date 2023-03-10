local PLUGIN = PLUGIN.refine

ENT.Type = "anim"
ENT.PrintName = "Button"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.uniqueID = "button"
ENT.index = 0
ENT.side = ""

if (SERVER) then
	function ENT:SetSide(newSide)
		self.side = newSide
	end

	function ENT:SpawnFunction(client, trace)
		local button = ents.Create("ix_button")
		button:SetPos(trace.HitPos)
		button:SetAngles(trace.HitNormal:Angle())
		button:Spawn()
		button:Activate()
		return button
	end
	function ENT:Initialize()
		self:SetModel("models/props_lab/tpplug.mdl")
		self:SetUseType(SIMPLE_USE)
		self:SetSolid(SOLID_VPHYSICS)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:GetPhysicsObject():Wake()
		self:Activate() 
	end

	function ENT:Use()
		if (self.side == "left") then
			print("smelter open state is now:")
			print(!PLUGIN.list[PLUGIN.buttonEntity[self.index]].open)
			PLUGIN.list[PLUGIN.buttonEntity[self.index]].open = !PLUGIN.list[PLUGIN.buttonEntity[self.index]].open
		end
	end
end

if (CLIENT) then
	function ENT:Draw()
		self:DrawModel()
	end
end
