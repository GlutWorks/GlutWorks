AddCSLuaFile()

-- A Civil Workers' Union terminal: citizens deliver wanted goods for tokens here, and Combine
-- units run the city's off-map trade and draw rations. Use opens a world panel beside it
-- (cityeconomy/cl_plugin.lua); all of the trade itself is server-side (sv_plugin.lua). The
-- plugin saves and reloads these itself, so Helix's persistence must not keep a second copy.
ENT.Type = "anim"
ENT.PrintName = "CWU Terminal"
ENT.Category = "Helix"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.bNoPersist = true

if (SERVER) then
	function ENT:SpawnFunction(client, trace, className)
		local entity = ents.Create(className)
		entity:SetAngles(Angle(0, client:EyeAngles().y + 180, 0))
		entity:SetPos(trace.HitPos)
		entity:Spawn()
		entity:Activate()
		entity:SetPos(trace.HitPos - Vector(0, 0, entity:OBBMins().z))

		local plugin = ix.plugin.list.cityeconomy

		if (plugin) then
			plugin:QueueSave()
		end

		return entity
	end

	function ENT:Initialize()
		-- the Combine console the application terminal uses (applicationsystem)
		self:SetModel("models/props_combine/breenconsole.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		local physics = self:GetPhysicsObject()

		if (IsValid(physics)) then
			physics:EnableMotion(false)
			physics:Sleep()
		end
	end

	-- World furniture; it cannot be destroyed.
	function ENT:OnTakeDamage()
	end

	function ENT:Use(client)
		if (!IsValid(client) or !client:IsPlayer() or !client:Alive() or !client:GetCharacter()) then
			return
		end

		if (client:IsRestricted() or IsValid(client.ixRagdoll)) then
			return
		end

		local plugin = ix.plugin.list.cityeconomy

		if (plugin) then
			plugin:OpenTerminal(client, self)
		end
	end

	function ENT:OnRemove()
		local plugin = ix.plugin.list.cityeconomy

		if (plugin and !plugin.bLoadingTerminals) then
			plugin:QueueSave()
		end
	end
else
	function ENT:Draw()
		self:DrawModel()
	end
end
