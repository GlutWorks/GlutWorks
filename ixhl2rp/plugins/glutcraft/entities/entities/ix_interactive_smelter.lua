local PLUGIN = PLUGIN.refine

ENT.Type = "anim"
ENT.PrintName = "Interactive Smelter"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.uniqueID = "interactive_smelter"
ENT.index = 0
ENT.open = false

local model = "models/props_forest/furnace01.mdl"

smeltWin = {}

function ENT:GetID()
	return self:GetNetVar("ID", 0)
end

if (SERVER) then
	function ENT:GetInternalValues()
		return PLUGIN.values[self.uniqueID]["internal"]
	end
	function ENT:GetInOutValues()
		return PLUGIN.values[self.uniqueID]["inOut"]
	end

	function ENT:SpawnFunction(client, trace)
		local iSmelter = ents.Create("ix_interactive_smelter")
		iSmelter:SetPos(trace.HitPos)
		iSmelter:SetAngles(trace.HitNormal:Angle())
		iSmelter:Spawn()
		iSmelter:Activate()
		hook.Run("OnItemSpawned", iSmelter)

		local buttonLeft = ents.Create("ix_button")
		buttonLeft:SetPos(trace.HitPos + iSmelter:GetForward() * 25 + iSmelter:GetUp() * 40 + iSmelter:GetRight() * 10)
		buttonLeft:SetAngles(trace.HitNormal:Angle())
		buttonLeft:Spawn()
		buttonLeft:Activate()
		local buttonListLen
		if (PLUGIN.buttons["left"]) then
			buttonListLen = #PLUGIN.buttons["left"] + 1
		else
			buttonListLen = 0
		end
		PLUGIN.buttons["left"][buttonListLen] = buttonLeft
		PLUGIN.buttonEntity[buttonListLen] = iSmelter.index
		buttonLeft.index = buttonListLen
		buttonLeft:SetSide("left")

		
		local buttonRight = ents.Create("ix_button")
		buttonRight:SetPos(trace.HitPos + iSmelter:GetForward() * 25 + iSmelter:GetUp() * 40 + iSmelter:GetRight() * -10)
		buttonRight:SetAngles(trace.HitNormal:Angle())
		buttonRight:Spawn()
		buttonRight:Activate()
		PLUGIN.buttons["right"][buttonListLen] = buttonRight
		PLUGIN.buttonEntity[buttonListLen] = iSmelter.index
		buttonRight.index = buttonListLen
		buttonRight:SetSide("right")

		return iSmelter
	end

	function ENT:Initialize()
		self:SetModel(model)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:StartMotionController()
		PLUGIN.initSmelter(self)
	end

	function ENT:PhysicsCollide( data, obj ) 								-- <- function to add resources to smelter
		if !pcall(function ()
			PLUGIN.physAddResource(self:GetID(), data.HitEntity:GetItemTable(), data.HitEntity)
		end) then return end
	end
elseif (CLIENT) then
	function ENT:Draw()
        self:DrawModel()
        local angle = self:GetAngles()
        angle:RotateAroundAxis(angle:Forward(), 90)
        angle:RotateAroundAxis(angle:Right(), 270)
        cam.Start3D2D( self:GetPos() + self:GetUp() * 30 + self:GetForward() * 17, angle , 0.1 )
			local text = table.ToString(PLUGIN.values[self:GetID()], "", true)
			surface.SetFont( "Default" )
			local tW, tH = surface.GetTextSize( text )
			tW = tW * 3
			local pad = 10

			surface.SetDrawColor( 0, 0, 0, 255 )
			surface.DrawRect( -tW / 2 - pad, -pad, tW + pad * 2, tH + pad * 2 )

			draw.DrawText( text, "Default", -tW / 2, 0, color_white )
		cam.End3D2D()
	end
end
