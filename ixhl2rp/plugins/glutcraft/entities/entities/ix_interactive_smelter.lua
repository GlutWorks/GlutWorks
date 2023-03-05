local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.PrintName = "Interactive Smelter"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true

/****************************************************
*	Many of these functions should be migrated to
* 	a dedicated server function file.
*	
*	
*
*
*
*
****************************************************/

local resources = {"metal_scrap", "iron1_junk", "iron2_junk", "iron3_junk", "iron4_junk", "iron5_junk", "iron6_junk", "iron7_junk"}
local model = "models/props_forest/furnace01.mdl"

smeltWin = {}

if (SERVER) then
	util.AddNetworkString( "glutAddResource" )
	util.AddNetworkString( "glutSmelt" )
	util.AddNetworkString( "glutUse" )

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

		return iSmelter
	end

	function ENT:Initialize()
		self:SetModel(model)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)

		for _, resource in pairs(resources) do
			self:SetNetVar(resource, 0, ents.FindByClass("player"))
		end
		self:SetNetVar("TimeToSmelt", 0, ents.FindByClass("player"))
	end

elseif (CLIENT) then

	net.Receive( "glutUse", function(_, _)
		smeltWin.OpenWindow(net.ReadEntity())
	end )

	function smeltWin.OpenWindow(smelter)
	
		if IsValid(smeltWin.Menu) then
			smeltWin.Menu:Remove()
		end
		local scrw, scrh = ScrW(), ScrH()
		smeltWin.Menu = vgui.Create("DFrame")
			smeltWin.Menu:SetSize(scrw * 0.5, scrh * 0.5)
			smeltWin.Menu:Center()
			smeltWin.Menu:SetTitle("Smelter")
			smeltWin.Menu:SetDraggable(true)
			smeltWin.Menu:MakePopup(true)
			smeltWin.Menu:ShowCloseButton(true)

		enterResourceAmt = {}
		for _, name in pairs(resources) do
			enterResourceAmt[name] = smeltWin.Menu:Add("DTextEntry", frame)
		end
	
		local resourceTable = smeltWin.Menu:Add("DListView")
			resourceTable:Dock(FILL)
			resourceTable:SetMultiSelect(false)
			resourceTable:AddColumn("Resource")
			resourceTable:AddColumn("Amount")
			resourceTable:AddColumn("Add Amount")

		for _, name in pairs(resources) do
			resourceTable:AddLine(name, smelter:GetNetVar(name), enterResourceAmt[name])
		end
	
		local addBut = smeltWin.Menu:Add("DButton")
		addBut:SetText("Add Resource")
		addBut:Dock(BOTTOM)
		addBut.DoClick = function()
			for _, name in pairs(resources) do
				local amt = tonumber(enterResourceAmt[name]:GetText())
				if amt == nil then
					continue
				elseif amt <= 0 then 
					continue
				end
				net.Start("glutAddResource")
					net.WriteUInt(LocalPlayer():UserID(), 8)
					net.WriteEntity(smelter)
					net.WriteString(name)
					net.WriteInt(amt, 8)
				net.SendToServer()
			end
		end

		local smeltBut = smeltWin.Menu:Add("DButton")
		smeltBut:SetText("Smelt")
		smeltBut:Dock(BOTTOM)
		smeltBut.DoClick = function()
			net.Start("glutSmelt")
				net.WriteEntity(smelter)
			net.SendToServer()
		end
	end

    function ENT:Draw()
        self:DrawModel()
        local angle = self:GetAngles()
        angle:RotateAroundAxis(angle:Forward(), 90)
        angle:RotateAroundAxis(angle:Right(), 270)
        cam.Start3D2D( self:GetPos() + self:GetUp() * 30 + self:GetForward() * 17, angle , 0.1 )
			local text = ""
			for _, resource in pairs(resources) do
				text = text..resource..": "..self:GetNetVar(resource).." | "
			end
			surface.SetFont( "Default" )
			local tW, tH = surface.GetTextSize( text )
			local pad = 10

			surface.SetDrawColor( 0, 0, 0, 255 )
			surface.DrawRect( -tW / 2 - pad, -pad, tW + pad * 2, tH + pad * 2 )

			draw.SimpleText( text, "Default", -tW / 2, 0, color_white )
		cam.End3D2D()
        cam.Start3D2D( self:GetPos() + self:GetUp() * 60 + self:GetForward() * 17, angle , 0.1 )
			local text = "Time to smelt: "..self:GetNetVar("TimeToSmelt")
			surface.SetFont( "Default" )
			local tW, tH = surface.GetTextSize( text )
			local pad = 10

			surface.SetDrawColor( 0, 0, 0, 255 )
			surface.DrawRect( -tW / 2 - pad, -pad, tW + pad * 2, tH + pad * 2 )

			draw.SimpleText( text, "Default", -tW / 2, 0, color_white )
		cam.End3D2D()
    end
end
