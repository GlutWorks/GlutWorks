local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Interactive Smelter"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true
inputs = {"coal", "metal_scrap", "iron1_junk", "iron2_junk", "iron3_junk", "iron4_junk", "iron5_junk", "iron6_junk", "iron7_junk"}
internalValues = {
	"carbon",		-- Value that is supposed to be 'tuned' to the right value. Going to cast or wrought iron decreases quality
	"output",		-- The amount of output
	"impurities",	-- the amount of impurities. Taking out slag reduces this amount
	"iron",
	"copper"
}

local model = "models/props_forest/furnace01.mdl"

smeltWin = {}

function GetInputs()
	return inputs
end
function GetInternalValues()
	return internalValues
end


if (SERVER) then
	util.AddNetworkString( "glutAddResource" )
	util.AddNetworkString( "glutSmelt" )
	util.AddNetworkString( "glutUse" )
	util.AddNetworkString( "glutCraftRedraw" )

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

		for _, resource in pairs(inputs) do
			self:SetNetVar(resource, 0, ents.FindByClass("player"))
		end
		for _, resource in pairs(internalValues) do
			self:SetNetVar(resource, 0, ents.FindByClass("player"))
		end
		self:SetNetVar("TimeToSmelt", 0, ents.FindByClass("player"))
	end

	function ENT:PhysicsCollide( data, obj ) 								-- <- function to add resources to smelter
		
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
		for _, name in pairs(inputs) do
			enterResourceAmt[name] = smeltWin.Menu:Add("DTextEntry", frame)
		end
	
		local resourceTable = smeltWin.Menu:Add("DListView")
			resourceTable:Dock(FILL)
			resourceTable:SetMultiSelect(false)
			resourceTable:AddColumn("Resource")
			resourceTable:AddColumn("Amount")
			resourceTable:AddColumn("Add Amount")

		for _, name in pairs(inputs) do
			resourceTable:AddLine(name, smelter:GetNetVar(name), enterResourceAmt[name])
		end
	
		local addBut = smeltWin.Menu:Add("DButton")
		addBut:SetText("Add Resource")
		addBut:Dock(BOTTOM)
		addBut.DoClick = function()
			for _, name in pairs(inputs) do
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
end