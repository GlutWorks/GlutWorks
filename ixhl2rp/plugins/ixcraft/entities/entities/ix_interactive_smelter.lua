local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.PrintName = "Interactive Smelter"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true

resouces = {
	["metal_scrap"] = 0,
	["iron1_junk"] = 0,
	["iron2_junk"] = 0,
	["iron3_junk"] = 0,
	["iron4_junk"] = 0,
	["iron5_junk"] = 0,
	["iron6_junk"] = 0,
	["iron7_junk"] = 0
}

smeltWin = {}

if (SERVER) then
	util.AddNetworkString( "glutAddResource" )
	net.Receive( "glutAddResource", function(_, player)
		addResouce(player, net.ReadString():sub(2,-1), tonumber(net.ReadInt(8)))
	end )

	function addResouce(player, name, amt)
		print("a"..amt)

		if amt < 0 then amt = 0 end -- intentional redundency
			
		local totalAmt = 0
		for _, item in pairs(player:GetCharacter():GetInventory():GetItems()) do
			print(item.uniqueID.." vs "..name.."|")
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

		resouces[name] = resouces[name] + amt
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

end


function smeltWin.OpenWindow()
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
	for name, _ in pairs(resouces) do
		enterResourceAmt[name] = smeltWin.Menu:Add("DTextEntry", frame)
	end

	local resourceList = smeltWin.Menu:Add("DListView")
	resourceList:Dock(FILL)
	resourceList:SetMultiSelect(false)
	resourceList:AddColumn("Resource")
	resourceList:AddColumn("Amount")
	resourceList:AddColumn("Add Amount")
	for name, amount in pairs(resouces) do
		resourceList:AddLine(name, amount, enterResourceAmt[name])
	end

	local startBut = smeltWin.Menu:Add("DButton")
	startBut:SetText("Start Smelting")
	startBut:Dock(BOTTOM)
	startBut.DoClick = function()
		for name, _ in pairs(resouces) do
			local amt = tonumber(enterResourceAmt[name]:GetText())
			if amt == nil then
				continue
			elseif amt <= 0 then 
				continue
			end
			print(name..": "..amt)
			net.Start("glutAddResource")
				net.WriteUInt(LocalPlayer():UserID(), 8)
				net.WriteString(name)
				net.WriteInt(amt, 8)
			net.SendToServer()
		end
	end
end

function ENT:Use(client)
	print ("Use")
	if (client:GetPos():Distance(self:GetPos()) <= 128) then
		print (client:UserID())
		client:SendLua("smeltWin.OpenWindow()")
	end
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
