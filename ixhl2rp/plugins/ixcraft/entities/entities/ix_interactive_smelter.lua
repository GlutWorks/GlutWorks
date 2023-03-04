local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.PrintName = "Interactive Smelter"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true


/****************************************************
*		SERVER  					PLAYER
* 
*	
*	
*
*
*
*
****************************************************/

resources = {
	"metal_scrap", 
	"iron1_junk", 
	"iron2_junk", 
	"iron3_junk", 
	"iron4_junk", 
	"iron5_junk", 
	"iron6_junk", 
	"iron7_junk"
}

smeltWin = {}

if (SERVER) then
	util.AddNetworkString( "glutAddResource" )
	util.AddNetworkString( "glutUse" )
	net.Receive( "glutAddResource", function(_, _)
		local player, smelter, name, amt = net.ReadUInt(8), net.ReadEntity(), net.ReadString(), tonumber(net.ReadInt(8))
		addResource(Player(player), smelter, name, amt)
	end )

	function ENT:Use(client)
		if (client:GetPos():Distance(self:GetPos()) <= 128) then
			net.Start("glutUse")
				net.WriteEntity(self)
			net.Send(client)
		end
	end
	
	function addResource(player, smelter, name, amt)
		print("serverside function addResource called with")
		print(smelter)

		if amt < 0 then amt = 0 end -- intentional redundency
			
		local totalAmt = 0
		for _, item in pairs(player:GetCharacter():GetInventory():GetItems()) do
			print(item.uniqueID.." vs "..name)
			if item.uniqueID == name then
				print("found "..name)
				if (item:GetData("quantity", 1)) then
					totalAmt = totalAmt + item:GetData("quantity", 1)
				else							-- this is 
					print("f")					-- useless atm			
					totalAmt = totalAmt + 1		-- but preserved for 
				end								-- safety		
				print(totalAmt)
			end
		end
		
		if totalAmt < amt then
			player:Notify("You don't have enough "..name.." to smelt!")
			return
		end

		print("previous resource: "..smelter:GetNetVar(name))
		smelter:SetNetVar(name, smelter:GetNetVar(name) + amt)
		print("new resource: "..smelter:GetNetVar(name))
		for _, item in pairs(player:GetCharacter():GetInventory():GetItems()) do
			print(item.uniqueID)
			if item.uniqueID == name then
				if item:GetData("quantity", 1) > amt then
					item:SetData("quantity", item:GetData("quantity", 1) - amt)
					break
				else
					amt = amt - item:GetData("quantity", 1)
					item:Remove()
				end
			end
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
		self:SetModel("models/props_forest/furnace01.mdl")
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)

		print(ents.FindByClass("player"))
		for _, resource in pairs(resources) do
			print("iSmelter:SetNetVar("..resource..", 0, ")
			print("Sending to players:")
			for _, player in pairs(ents.FindByClass("player")) do
				print("\t"..player:UserID())
			end
			self:SetNetVar(resource, 0, ents.FindByClass("player"))
		end

	end

elseif (CLIENT) then

	net.Receive( "glutUse", function(_, _)
		print("Clientside use function called; opening window.")
		smeltWin.OpenWindow(net.ReadEntity())
	end )

	function smeltWin.OpenWindow(smelter)
		print(smelter)
	
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
	
		local startBut = smeltWin.Menu:Add("DButton")
		startBut:SetText("Start Smelting")
		startBut:Dock(BOTTOM)
		startBut.DoClick = function()
			for _, name in pairs(resources) do
				local amt = tonumber(enterResourceAmt[name]:GetText())
				if amt == nil then
					continue
				elseif amt <= 0 then 
					continue
				end
				print(name..": "..amt)
				net.Start("glutAddResource")
					net.WriteUInt(LocalPlayer():UserID(), 8)
					net.WriteEntity(smelter)
					net.WriteString(name)
					net.WriteInt(amt, 8)
				net.SendToServer()
			end
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
    end
end
