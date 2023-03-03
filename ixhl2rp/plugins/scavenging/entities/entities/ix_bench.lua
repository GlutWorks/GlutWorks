
local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.PrintName = "Scavengable Bench"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.m_bApplyingDamage = false
ENT.damage = 0

function ENT:OnTakeDamage( dmginfo )
	if ( self.m_bApplyingDamage ) then return end
	if ( dmginfo:GetInflictor() == self ) then
		-- change 'self' to types that should not damage the entity in this way
		-- and add functionality perhaps for other types of damage 
	else
		self.m_bApplyingDamage = true
		self.damage = self.damage + dmginfo:GetDamage()
		self.m_bApplyingDamage = false
		print(self.damage)
		if (self.damage > 100) then
			ix.item.Spawn("wooden_scrap", self:GetPos(), nil, angle_zero, {quantity = 5})
			ix.item.Spawn("metal_scrap", self:GetPos(), nil, angle_zero, {quantity = 1})
			self:Remove()
		end
	end
end

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Display")
	self:NetworkVar("Bool", 1, "Enabled")
end

if (SERVER) then
	function ENT:SpawnFunction(client, trace)
		local scavBench = ents.Create("ix_"..ENT.uniqueID)

		scavBench:SetPos(trace.HitPos)
		scavBench:SetAngles(trace.HitNormal:Angle())
		scavBench:Spawn()
		scavBench:Activate()
		scavBench:SetEnabled(true)

		return scavBench
	end

	function ENT:Initialize()
		self:SetModel("models/props_trainstation/BenchOutdoor01a.mdl")
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
	end

else
	function ENT:Draw()
		self:DrawModel()
	end
end
