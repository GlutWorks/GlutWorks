local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Interactive Smelter"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true

local model = "models/props_forest/furnace01.mdl"

smeltWin = {}

if (SERVER) then
	function ENT:GetID()
		return self:GetNetVar("ID", 0)
	end
	function ENT:GetInternalValues()
		return PLUGIN.refine.values[self.uniqueID]["internal"]
	end
	function ENT:GetInOutValues()
		return PLUGIN.refine.values[self.uniqueID]["inOut"]
	end

	function ENT:Use(client)
		if (client:GetPos():Distance(self:GetPos()) <= 128) then
			net.Start("glutUse")
				net.WriteEntity(self)
			net.Send(client)
		end
	end

	function ENT:SpawnFunction(client, trace)
		local iSmelter = ents.Create("ix_"..ENT.uniqueID)

		iSmelter:SetPos(trace.HitPos)
		iSmelter:SetAngles(trace.HitNormal:Angle())
		iSmelter:Spawn()
		iSmelter:Activate()
		iSmelter:SetEnabled(true)
		hook.Run("OnItemSpawned", iSmelter)

		return iSmelter
	end

	function ENT:Initialize()
		self:SetModel(model)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		local phys = self:GetPhysicsObject()
		if (phys:IsValid()) then
			phys:Wake()
		end

		PLUGIN.refine.smelter.GetNewID(self)
		self:SetNetVar("input", 0, ents.FindByClass("player"))
		for _, resource in ipairs(PLUGIN.refine.internalValues) do
			self:SetNetVar(resource, 0, ents.FindByClass("player"))
		end
		for _, resource in ipairs(PLUGIN.refine.otherValues) do
			self:SetNetVar(resource, 0, ents.FindByClass("player"))
		end
		self:SetNetVar("TimeToSmelt", 0, ents.FindByClass("player"))
	end

	function ENT:PhysicsCollide( data, obj ) 								-- <- function to add resources to smelter
		if !pcall(function ()
			PLUGIN.refine.addResource(self, data.HitEntity:GetItemTable(), data.HitEntity)
		end) then return end
	end
elseif (CLIENT) then
	function ENT:Draw()
        self:DrawModel()
        local angle = self:GetAngles()
        angle:RotateAroundAxis(angle:Forward(), 90)
        angle:RotateAroundAxis(angle:Right(), 270)
        cam.Start3D2D( self:GetPos() + self:GetUp() * 30 + self:GetForward() * 17, angle , 0.1 )
			local text = ""
			for _, resource in ipairs(PLUGIN.refine.internalValues) do
				text = text..resource..": "..self:GetNetVar(resource).." | " -- 1
			end
			for _, resource in ipairs(PLUGIN.refine.otherValues) do
				text = text..resource..": "..self:GetNetVar(resource).." | " -- 1
			end
			surface.SetFont( "Default" )
			local tW, tH = surface.GetTextSize( text )
			local pad = 10

			surface.SetDrawColor( 0, 0, 0, 255 )
			surface.DrawRect( -tW / 2 - pad, -pad, tW + pad * 2, tH + pad * 2 )

			draw.SimpleText( text, "Default", -tW / 2, 0, color_white )
		cam.End3D2D()
			cam.Start3D2D( self:GetPos() + self:GetUp() * 60 + self:GetForward() * 17, angle , 0.1 )
			local text = "Time to smelt: "..self:GetNetVar("TimeToSmelt") -- 2 surface.DrawRect
			surface.SetFont( "Default" )
			local tW, tH = surface.GetTextSize( text )
			local pad = 10

			surface.SetDrawColor( 0, 0, 0, 255 )
			surface.DrawRect( -tW / 2 - pad, -pad, tW + pad * 2, tH + pad * 2 )

			draw.SimpleText( text, "Default", -tW / 2, 0, color_white )
		cam.End3D2D()
	end
end