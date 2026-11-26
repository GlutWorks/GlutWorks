
-- Base for scavengeable props. A prop type sets its name, model and `yields` (item uniqueID =
-- quantity); see ix_barrel.lua. Taking `scavengeHealth` damage breaks it for its yields, after which
-- it disappears until the scavengeRespawnTime config has passed.
local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.PrintName = "Scavengeable Prop"
ENT.Category = "HL2 RP"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.IsScavengeable = true
-- saved by the scavenging plugin, so Helix's persistence plugin must not save a second copy
ENT.bNoPersist = true

-- no default `yields`: GMod merges a base's table into the child's, which would add its BaseClass key
ENT.model = "models/props_junk/wood_crate001a.mdl"
ENT.scavengeHealth = 100

if (SERVER) then
	function ENT:SpawnFunction(client, trace, className)
		local entity = ents.Create(className)
		entity:SetPos(trace.HitPos + trace.HitNormal * 16)
		entity:SetAngles(Angle(0, client:EyeAngles().y + 180, 0))
		entity:Spawn()
		entity:DropToFloor()
		PLUGIN:QueueSave()

		return entity
	end

	function ENT:Initialize()
		self.damage = 0
		self:SetModel(self.model)
		self:SetSolid(SOLID_VPHYSICS)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)

		-- frozen, so it stays where it was placed and is saved there
		local physObj = self:GetPhysicsObject()

		if (IsValid(physObj)) then
			physObj:EnableMotion(false)
		end
	end

	function ENT:IsDepleted()
		return self.respawnAt != nil
	end

	function ENT:OnTakeDamage(dmginfo)
		if (self:IsDepleted() or dmginfo:GetInflictor() == self) then
			return
		end

		self.damage = self.damage + dmginfo:GetDamage()

		if (self.damage >= self.scavengeHealth) then
			self:Scavenge()
		end
	end

	function ENT:Scavenge()
		local position = self:WorldSpaceCenter() + Vector(0, 0, 8)

		for uniqueID, quantity in SortedPairs(self.yields or {}) do
			if (isnumber(quantity)) then
				ix.stack.Spawn(uniqueID, position, quantity)
			end
		end

		self:EmitSound("physics/wood/wood_crate_break" .. math.random(1, 5) .. ".wav", 75)
		self:Deplete()
		PLUGIN:QueueSave()
	end

	--- Hides the prop until `respawnAt` (os.time), by default the configured delay from now.
	function ENT:Deplete(respawnAt)
		self.respawnAt = respawnAt or os.time() + ix.config.Get("scavengeRespawnTime", 1800)
		self:SetNoDraw(true)
		self:SetNotSolid(true)
		self:DrawShadow(false)
	end

	function ENT:Refill()
		self.respawnAt = nil
		self.damage = 0
		self:SetNoDraw(false)
		self:SetNotSolid(false)
		self:DrawShadow(true)
	end

	function ENT:Think()
		if (self:IsDepleted() and os.time() >= self.respawnAt) then
			local blocked = false

			-- do not reappear around someone standing on the spot
			for _, v in ipairs(ents.FindInSphere(self:WorldSpaceCenter(), self:BoundingRadius())) do
				if (v:IsPlayer()) then
					blocked = true
					break
				end
			end

			if (!blocked) then
				self:Refill()
				PLUGIN:QueueSave()
			end
		end

		self:NextThink(CurTime() + 5)

		return true
	end

	function ENT:OnRemove()
		PLUGIN:QueueSave()
	end
else
	function ENT:Draw()
		self:DrawModel()
	end
end
