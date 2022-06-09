
local PLUGIN = PLUGIN

ENT.name = "Workbench"
ENT.description = "A workbench used for crafting."
ENT.model = "models/mosi/fnv/props/workstations/workbench.mdl"
ENT.Type = "anim"
ENT.PrintName = "Station"
ENT.Category = "Helix"
ENT.Spawnable = true

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "StationID")

	if (SERVER) then
		self:NetworkVarNotify("StationID", self.OnVarChanged)
	end
end

if (SERVER) then
	function ENT:SpawnFunction(client)

		workbench:Spawn()
		workbench:SetAngles(Angle(0, (workbench:GetPos() - client:GetPos()):Angle().y - 180, 0))
		workbench:SetPos(client:GetPos())
		workbench:Activate()

		hook.Run("OnItemSpawned", workbench)
		return workbench
	end
	function ENT:Initialize()
		if (!self.uniqueID) then
			self:Remove()

			return
		end

		self:SetStationID(self.uniqueID)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:PhysicsInit(SOLID_VPHYSICS)

		local physObj = self:GetPhysicsObject()

		if (IsValid(physObj)) then
			physObj:EnableMotion(false)
			physObj:Sleep()
		end
	end

	function ENT:OnVarChanged(name, oldID, newID)
		local stationTable = PLUGIN.craft.stations[newID]

		if (stationTable) then
			self:SetModel(stationTable:GetModel())
		end
	end

	function ENT:UpdateTransmitState()
		return TRANSMIT_PVS
	end
else
	ENT.PopulateEntityInfo = true

	function ENT:OnPopulateEntityInfo(tooltip)
		local stationTable = self:GetStationTable()

		if (stationTable) then
			PLUGIN:PopulateStationTooltip(tooltip, stationTable)
		end
	end

	function ENT:Draw()
		self:DrawModel()
	end
end

function ENT:GetStationTable()
	return PLUGIN.craft.stations[self:GetStationID()]
end
