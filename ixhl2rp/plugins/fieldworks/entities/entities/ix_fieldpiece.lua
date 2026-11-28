local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.PrintName = "Workshop section"
ENT.bNoPersist = true
ENT.PhysgunDisabled = true
ENT.DoNotDuplicate = true
ENT.bInteractive = false

if (SERVER) then
	function ENT:Initialize()
		-- The survey supplies the model and owns the section's lifetime.
		if (!IsValid(self.fieldSite) or !self:PhysicsInit(SOLID_VPHYSICS)) then
			self:Remove()
			return
		end
		self:SetMoveType(MOVETYPE_NONE)
		self:GetPhysicsObject():EnableMotion(false)
	end

	function ENT:OnTakeDamage(damage)
		local site = self.fieldSite
		if (!IsValid(site) or !self.rockHits or self:IsMarkedForDeletion()) then return end

		local attacker = damage:GetAttacker()
		if (!damage:IsDamageType(DMG_CLUB) or !IsValid(attacker) or !attacker:IsPlayer() or
			!ix.plugin.list.interaction:CanUseEntity(attacker, self)) then return end

		self.rockHits = self.rockHits - 1
		self:EmitSound("physics/concrete/concrete_break2.wav", 70, 110 - self.rockHits * 10)
		if (self.rockHits <= 0) then
			site:SetSections(bit.band(site:GetSections(), bit.bnot(self.sectionFlag)))
			self:Remove()
			PLUGIN:SaveData()
		end
	end
end
