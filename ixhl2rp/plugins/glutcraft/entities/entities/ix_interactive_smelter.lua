local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Interactive Smelter"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true


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

end