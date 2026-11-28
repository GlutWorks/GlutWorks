-- The intake desk's clerk (plugins/arriving): a rule on the server, a body behind the desk. Someone nameless
-- who comes up is asked for their name, and what they say aloud next is checked (sv_plugin.lua, ThinkDesk
-- and PostPlayerSay). An officer player at the desk, stamping or refusing, is for later.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Intake clerk"
ENT.Spawnable = false
ENT.bNoPersist = true
ENT.AutomaticFrameAdvance = true
ENT.bInteractive = true
ENT.interactionTap = false
ENT.PhysgunDisabled = true

ENT.model = "models/police.mdl"
ENT.idles = {"idle_unarmed", "batonidle1", "idle1", "idle_all_01"}

function ENT:Initialize()
	self:SetModel(self.model)

	if (SERVER) then
		self:SetSolid(SOLID_BBOX)
		self:SetCollisionBounds(Vector(-14, -14, 0), Vector(14, 14, 72))
		self:SetMoveType(MOVETYPE_NONE)
		self:SetUseType(SIMPLE_USE)
	end

	for _, name in ipairs(self.idles) do
		local sequence = self:LookupSequence(name)

		if (sequence and sequence > 0) then
			self:ResetSequence(sequence)
			break
		end
	end
end

function ENT:Think()
	self:NextThink(CurTime())

	return true
end

if (CLIENT) then
	function ENT:OnPopulateEntityInfo(container)
		local name = container:AddRow("name")
		name:SetImportant()
		name:SetText("Intake clerk")
		name:SizeToContents()

		local description = container:AddRow("description")
		description:SetText("A Civil Protection clerk behind the intake desk, taking down the names of whoever comes off the trains.")
		description:SizeToContents()
	end
end
