
-- Base for ore nodes. A node type only names its ore item and skin; see ix_orenode_coal.lua.
-- Each stage takes `stageHealth` damage to break and drops `yields[stage]` kg of ore. Breaking the
-- last stage depletes the node: it disappears and grows back after the oreNodeRespawnTime config.
local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.PrintName = "Ore Node"
ENT.Category = "HL2 RP"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.IsOreNode = true

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

		return entity
	end

	function ENT:Initialize()
		self:SetStage(1)
		self.nodeHealth = self.stageHealth
		self:ApplyStage()
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
		local amount = self.yields[stage] or 0

		if (self.oreItem and amount > 0) then
			ix.stack.Spawn(self.oreItem, self:GetDropPosition(), amount)
		end

		local effect = EffectData()
			effect:SetStart(self:GetPos())
			effect:SetOrigin(self:GetPos())
			effect:SetScale(30 - stage)
		util.Effect("GlassImpact", effect)
		self:EmitSound("physics/concrete/boulder_impact_hard1.wav", 80)

		if (stage >= #self.stages) then
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
		self:SetStage(1)
		self.nodeHealth = self.stageHealth
		self:ApplyStage()
		self:SetNoDraw(false)
		self:SetNotSolid(false)
		self:DrawShadow(true)
	end

	function ENT:Think()
		if (self:IsDepleted() and os.time() >= self.respawnAt) then
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
