
-- Base for scavengeable props. A prop type sets its name, model and `yields` (item uniqueID =
-- quantity); see ix_barrel.lua. Taking `scavengeHealth` damage breaks it for its yields, scaled by
-- its richness (0-1); a break spends richness, which regrows by os.time over
-- scavengeRichnessRegen seconds. After a break it disappears until scavengeRespawnTime has passed
-- and richness is at or above scavengeRichnessFloor again.
-- A metal prop (its yields are mostly metal_scrap, e.g. the oil drum) only takes damage from a
-- player holding the crowbar weapon or carrying a blowtorch; tool-less and non-player damage
-- does nothing to it, with no partial progress. Wood props take damage as before.
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
		self.richness = 1
		self.lastHarvest = os.time()
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

	-- Richness now: the stored value plus what has regrown since the last break.
	function ENT:GetRichness()
		local richness = tonumber(self.richness)

		if (richness == nil) then
			return 1
		end

		local regen = math.max(tonumber(ix.config.Get("scavengeRichnessRegen", 3600)) or 3600, 1)
		local elapsed = math.max(os.time() - (tonumber(self.lastHarvest) or os.time()), 0)

		return math.Clamp(richness + elapsed / regen, 0, 1)
	end

	function ENT:RefreshRichness()
		self.richness = self:GetRichness()
		self.lastHarvest = os.time()

		return self.richness
	end

	function ENT:GetRichnessFloor()
		return math.Clamp(tonumber(ix.config.Get("scavengeRichnessFloor", 0.25)) or 0.25, 0, 1)
	end

	-- Metal from the prop's own yields: mostly metal scrap (the drum), not mostly wood (the bench).
	function ENT:IsMetal()
		local yields = self.yields or {}

		return (tonumber(yields.metal_scrap) or 0) > (tonumber(yields.wooden_scrap) or 0)
	end

	-- Server-side break-in tool test, shared in spirit with the vending machine's (duplicated
	-- there to avoid schema->plugin coupling): the crowbar in hand, or a blowtorch carried.
	function ENT:HasBreakTool(client)
		if (!IsValid(client) or !client:IsPlayer() or !client:Alive() or client:IsRestricted() or IsValid(client.ixRagdoll)) then
			return false
		end

		local weapon = client:GetActiveWeapon()

		if (IsValid(weapon) and weapon:GetClass() == "tfa_projecthl2_crowbar") then
			return true
		end

		local character = client:GetCharacter()
		local inventory = character and character:GetInventory()

		return inventory != nil and ix.stack.Count(inventory, "blowtorch") >= ix.stack.GetTradeAmount("blowtorch")
	end

	function ENT:OnTakeDamage(dmginfo)
		if (self:IsDepleted() or dmginfo:GetInflictor() == self) then
			return
		end

		local attacker = dmginfo:GetAttacker()

		if (IsValid(attacker) and attacker:IsPlayer() and (!attacker:Alive() or attacker:IsRestricted() or IsValid(attacker.ixRagdoll))) then
			return
		end

		if (self:IsMetal() and !self:HasBreakTool(attacker)) then
			return
		end

		self.damage = self.damage + dmginfo:GetDamage()

		if (self.damage >= self.scavengeHealth) then
			self:Scavenge()
		end
	end

	function ENT:Scavenge()
		local position = self:WorldSpaceCenter() + Vector(0, 0, 8)
		local richness = self:GetRichness()

		for uniqueID, quantity in SortedPairs(self.yields or {}) do
			if (isnumber(quantity)) then
				local step = ix.stack.GetStep(uniqueID)
				local amount = math.max(step, ix.stack.Normalize(uniqueID, quantity * richness))

				ix.stack.Spawn(uniqueID, position, amount)
			end
		end

		-- a break spends most of a prop's richness; the rest regrows while it is gone
		self:RefreshRichness()
		self.richness = math.Clamp(self.richness - 0.6, 0, 1)

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
		self:RefreshRichness()
		self.damage = 0
		self:SetNoDraw(false)
		self:SetNotSolid(false)
		self:DrawShadow(true)
	end

	function ENT:Think()
		if (self:IsDepleted() and os.time() >= self.respawnAt and self:GetRichness() >= self:GetRichnessFloor()) then
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
