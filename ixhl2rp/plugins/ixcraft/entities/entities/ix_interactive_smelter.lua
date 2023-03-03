local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.PrintName = "Interactive Smelter"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Display")
	self:NetworkVar("Bool", 1, "Enabled")
end

function smelt()
    
end


if (SERVER) then
	function ENT:SpawnFunction(client, trace)
		local iSmelter = ents.Create("ix_"..ENT.uniqueID)

		iSmelter:SetPos(trace.HitPos)
		iSmelter:SetAngles(trace.HitNormal:Angle())
		iSmelter:Spawn()
		iSmelter:Activate()
		iSmelter:SetEnabled(true)

		return iSmelter
	end

	function ENT:Initialize()
		self:SetModel("models/props_forest/furnace01.mdl")
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
	end

else
    function ENT:Draw()
        self:DrawModel()
        
        local angle = self:GetAngles()
        angle:RotateAroundAxis(angle:Forward(), 90)
        angle:RotateAroundAxis(angle:Right(), 270)

        cam.Start3D2D( self:GetPos() + self:GetUp() * 30 + self:GetForward() * 17, angle , 0.1 )
            local text = "Testing"
            surface.SetFont( "Default" )
            local tW, tH = surface.GetTextSize( "--------------------F\nF" )
            local pad = 10

            surface.SetDrawColor( 0, 0, 0, 255 )
            surface.DrawRect( -tW / 2 - pad, -pad, tW + pad * 2, tH + pad * 2 )

            draw.SimpleText( "test", "Default", -tW / 2, 0, color_white )
        cam.End3D2D()
    end
end
