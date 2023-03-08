ENT.Type = "anim"
ENT.PrintName = "Gold Ore"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.m_bApplyingDamage = false
ENT.oreType = "gold"
ENT.skin = 2
ENT.states = { "verylarge", "large", "medium", "small", "verysmall" }
ENT.curState = 1
ENT.curHealth = 200 // could be table of different healths in future

// helps to randomly determine the output placement of the nodes
function ENT:DetermineOutputPlacement()
	local x = (18 - self.curState * 3)*(-1)^math.random(1, 2)
	local y = (18 - self.curState * 3)*(-1)^math.random(1, 2)
	local z = (18 - self.curState * 3)*(-1)^math.random(1, 2)
	return self:GetPos() + Vector(x, y, z)
end

function ENT:DecreaseSize()
	if (self.curState == 4) then
		ix.item.Spawn(self.oreType.."_ore", self:GetPos())
		self:Remove()
	end
	self.curHealth = 200

	local effectRockBreakDust = EffectData()
		effectRockBreakDust:SetStart(self:GetPos())
		effectRockBreakDust:SetOrigin(self:GetPos())
		effectRockBreakDust:SetScale(30 - self.curState)
	util.Effect("GlassImpact", effectRockBreakDust)

	ix.item.Spawn(self.oreType.."_ore", Vector(self:DetermineOutputPlacement()))
	ix.item.Spawn(self.oreType.."_ore", Vector(self:DetermineOutputPlacement()))

	self.curState = self.curState + 1
	self:SetModel("models/ore_"..self.states[self.curState]..".mdl")
	self:SetSkin(self.skin)
	if (SERVER and self:PhysicsInit(SOLID_VPHYSICS)) then
		self:SetUseType(SIMPLE_USE)
		self:GetPhysicsObject():Wake()
		self:DropToFloor()
	end  
	self:EmitSound("physics/concrete/boulder_impact_hard1.wav", 200)
end

function ENT:OnTakeDamage( dmginfo )
	if ( self.m_bApplyingDamage ) then return end
	if ( dmginfo:GetInflictor() == self ) then
		-- change 'self' to types that should not damage the entity in this way
		-- and add functionality perhaps for other types of damage 
	else
		self.m_bApplyingDamage = true
		self.curHealth = self.curHealth - dmginfo:GetDamage()
		self.m_bApplyingDamage = false
		// play one of two sounds randomly when damage is taken
		local type = math.random(0 , 1)
		if (type == 1) then
			self:EmitSound("physics/concrete/concrete_break3.wav", 70)
		else
			self:EmitSound("physics/concrete/concrete_break2.wav", 70)
		end

		// produce sparks at location of hit
		local effectRockHitSparks = EffectData()
			effectRockHitSparks:SetStart(dmginfo:GetDamagePosition())
			effectRockHitSparks:SetOrigin(dmginfo:GetDamagePosition())
			// point the effect towards the player
			if (IsValid(dmginfo:GetAttacker())) then
				effectRockHitSparks:SetNormal(-dmginfo:GetAttacker():EyeAngles():Forward())
			end
			effectRockHitSparks:SetScale(3)
		util.Effect("MetalSpark", effectRockHitSparks)

		if (self.curHealth < 0) then
			self:DecreaseSize()
		end
	end
end

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Display")
	self:NetworkVar("Bool", 1, "Enabled")
end

if (SERVER) then
	function ENT:SpawnFunction(client, trace)
		local orenode = ents.Create("ix_orenode_"..self.oreType)

        print(orenode:GetName())

		if (orenode:IsValid()) then
			orenode:SetPos(trace.HitPos)
			orenode:SetAngles(trace.HitNormal:Angle())
			orenode:Spawn()
			orenode:SetEnabled(true)
		end

		return orenode
	end
end

function ENT:Initialize()
	self:SetModel("models/ore_verylarge.mdl")
	self:SetSkin(self.skin)
	// scuffed function
	//self:SetModelScale(0.5, 0.001)
	if (SERVER and self:PhysicsInit(SOLID_VPHYSICS)) then
		self:SetUseType(SIMPLE_USE)
		self:GetPhysicsObject():Wake()
		self:DropToFloor()
	end  
	// use timer if using nonzero time for SetModelScale
	//timer.Simple(0.5, function() 
		self:Activate() 
	//end)
end

if (CLIENT) then
	ENT.PopulateEntityInfo = true

	function ENT:OnPopulateEntityInfo(tooltip)
		local name = tooltip:AddRow("name")
		name:SetImportant()
		name:SetText(self.PrintName)
		name:SetMaxWidth(math.max(name:GetMaxWidth(), ScrW() * 0.5))
		name:SizeToContents()
	
		local description = tooltip:AddRow("description")
		description:SetText("A node of "..self.PrintName)
		description:SizeToContents()

		if (self.PopulateTooltip) then
			self:PopulateTooltip(tooltip)
		end
	end

	function ENT:Draw()
		self:DrawModel()
	end
end
