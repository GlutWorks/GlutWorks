
-- Base for ore nodes. A node type only names its ore item and skin; see ix_orenode_coal.lua.
-- Each stage takes `stageHealth` damage to break and drops `yields[stage]` kg of ore, scaled by
-- the node's richness (0-1, snapshot at the first stage of a cycle so a full node still gives its
-- full yields). Every stage harvested spends richness (its share of the total yield, half a full
-- node's worth over a whole cycle); richness regrows by os.time over oreRichnessRegen seconds.
-- Breaking the last stage, or dropping below oreRichnessFloor, depletes the node: it disappears
-- and grows back after oreNodeRespawnTime once richness is at or above the floor again.
local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.PrintName = "Ore Node"
ENT.Category = "HL2 RP"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.IsOreNode = true
-- saved by the mining plugin, so Helix's persistence plugin must not save a second copy
ENT.bNoPersist = true

ENT.oreItem = nil
ENT.skin = 0
ENT.stages = {"verylarge", "large", "medium", "small"}
ENT.yields = {2, 2, 2, 3}
ENT.stageHealth = 200

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Stage")
end

if (SERVER) then
	function ENT:SpawnFunction(client, trace, className)
		local entity = ents.Create(className)
		entity:SetPos(trace.HitPos + trace.HitNormal * 16)
		entity:SetAngles(Angle(0, client:EyeAngles().y, 0))
		entity:Spawn()
		entity:DropToFloor()
		PLUGIN:QueueSave()

		return entity
	end

	function ENT:Initialize()
		self:SetStage(1)
		self.nodeHealth = self.stageHealth
		self.richness = 1
		self.lastHarvest = os.time()
		self:ApplyStage()
	end

	-- Richness now: the stored value plus what has regrown since the last harvest.
	function ENT:GetRichness()
		local richness = tonumber(self.richness)

		if (richness == nil) then
			return 1
		end

		local regen = math.max(tonumber(ix.config.Get("oreRichnessRegen", 7200)) or 7200, 1)
		local elapsed = math.max(os.time() - (tonumber(self.lastHarvest) or os.time()), 0)

		return math.Clamp(richness + elapsed / regen, 0, 1)
	end

	function ENT:RefreshRichness()
		self.richness = self:GetRichness()
		self.lastHarvest = os.time()

		return self.richness
	end

	function ENT:GetRichnessFloor()
		return math.Clamp(tonumber(ix.config.Get("oreRichnessFloor", 0.25)) or 0.25, 0, 1)
	end

	function ENT:ApplyStage()
		local stage = self:GetStage()

		self:SetModel("models/ore_" .. self.stages[stage] .. ".mdl")
		self:SetSkin(self.skin)
		self:SetSolid(SOLID_VPHYSICS)

		-- the ore models are Workshop content; without them the node is a box that shrinks per stage
		if (!self:PhysicsInit(SOLID_VPHYSICS)) then
			local size = 28 - (stage - 1) * 6
			local mins, maxs = Vector(-size, -size, 0), Vector(size, size, size * 1.5)

			self:PhysicsInitBox(mins, maxs)
			self:SetCollisionBounds(mins, maxs)
		end

		self:SetMoveType(MOVETYPE_VPHYSICS)

		local physObj = self:GetPhysicsObject()

		if (IsValid(physObj)) then
			physObj:EnableMotion(false)
		end
	end

	function ENT:IsDepleted()
		return self.respawnAt != nil
	end

	function ENT:GetDropPosition()
		return self:GetPos() + Vector(math.Rand(-8, 8), math.Rand(-8, 8), self:OBBMaxs().z + 8)
	end

	function ENT:OnTakeDamage(dmginfo)
		if (self:IsDepleted() or dmginfo:GetInflictor() == self) then
			return
		end

		self.nodeHealth = self.nodeHealth - dmginfo:GetDamage()
		self:EmitSound(math.random(2) == 1 and "physics/concrete/concrete_break2.wav" or "physics/concrete/concrete_break3.wav", 70)

		local effect = EffectData()
			effect:SetStart(dmginfo:GetDamagePosition())
			effect:SetOrigin(dmginfo:GetDamagePosition())
			effect:SetScale(3)

			if (IsValid(dmginfo:GetAttacker()) and dmginfo:GetAttacker():IsPlayer()) then
				effect:SetNormal(-dmginfo:GetAttacker():GetAimVector())
			end
		util.Effect("MetalSpark", effect)

		if (self.nodeHealth <= 0) then
			self:BreakStage()
		end
	end

	function ENT:BreakStage()
		local stage = self:GetStage()
		local baseAmount = self.yields[stage] or 0

		-- the cycle's yield scale is fixed at its first stage, so one pass over a node is even
		if (stage == 1 or self.yieldRichness == nil) then
			self.yieldRichness = self:GetRichness()
		end

		local amount = baseAmount

		if (self.oreItem and amount > 0) then
			local step = ix.stack.GetStep(self.oreItem)
			amount = math.max(step, ix.stack.Normalize(self.oreItem, baseAmount * self.yieldRichness))
			ix.stack.Spawn(self.oreItem, self:GetDropPosition(), amount)
		end

		-- spend this stage's share of richness: a whole cycle spends half a full node
		local total = 0

		for _, yield in ipairs(self.yields) do
			total = total + yield
		end

		self:RefreshRichness()
		self.richness = math.Clamp(self.richness - (total > 0 and baseAmount / total * 0.5 or 0), 0, 1)

		local effect = EffectData()
			effect:SetStart(self:GetPos())
			effect:SetOrigin(self:GetPos())
			effect:SetScale(30 - stage)
		util.Effect("GlassImpact", effect)
		self:EmitSound("physics/concrete/boulder_impact_hard1.wav", 80)

		if (stage >= #self.stages or self.richness < self:GetRichnessFloor()) then
			self:Deplete()
		else
			self:SetStage(stage + 1)
			self.nodeHealth = self.stageHealth
			self:ApplyStage()
		end

		PLUGIN:QueueSave()
	end

	--- Hides the node until `respawnAt` (os.time), by default the configured delay from now.
	function ENT:Deplete(respawnAt)
		self.respawnAt = respawnAt or os.time() + ix.config.Get("oreNodeRespawnTime", 1800)
		self:SetNoDraw(true)
		self:SetNotSolid(true)
		self:DrawShadow(false)
	end

	function ENT:Refill()
		self.respawnAt = nil
		self:RefreshRichness()
		self.yieldRichness = nil
		self:SetStage(1)
		self.nodeHealth = self.stageHealth
		self:ApplyStage()
		self:SetNoDraw(false)
		self:SetNotSolid(false)
		self:DrawShadow(true)
	end

	function ENT:Think()
		if (self:IsDepleted() and os.time() >= self.respawnAt and self:GetRichness() >= self:GetRichnessFloor()) then
			local blocked = false

			-- do not grow back around someone standing on the spot
			for _, v in ipairs(ents.FindInSphere(self:GetPos(), 48)) do
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
	ENT.PopulateEntityInfo = true

	function ENT:OnPopulateEntityInfo(tooltip)
		local name = tooltip:AddRow("name")
		name:SetImportant()
		name:SetText(self.PrintName)
		name:SetMaxWidth(math.max(name:GetMaxWidth(), ScrW() * 0.5))
		name:SizeToContents()

		local description = tooltip:AddRow("description")
		description:SetText("A node of " .. self.PrintName .. ". Break it apart to mine it.")
		description:SizeToContents()
	end

	function ENT:Draw()
		self:DrawModel()
	end
end
