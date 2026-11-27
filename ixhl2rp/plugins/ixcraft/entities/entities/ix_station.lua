
-- Shared base for every ix_station_<id> entity. The station definition in stations/ gives the model
-- and name; a definition with a `smelting` table also makes the station a smelter (ix.smelting, in
-- the glutcraft plugin). Placing, picking up and saving stations is ix.station, also in glutcraft.
local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.PrintName = "Station"
ENT.Category = "Helix"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.IsStation = true
-- the smelter's glow is drawn in the translucent pass (cl_smelting.lua in glutcraft)
ENT.RenderGroup = RENDERGROUP_BOTH
-- saved by ix.station (glutcraft), so Helix's persistence plugin must not save a second copy
ENT.bNoPersist = true

-- Used when the station's model is not installed (Workshop content), so it is still solid and usable.
local FALLBACK_MINS = Vector(-24, -24, 0)
local FALLBACK_MAXS = Vector(24, 24, 48)
local INTERACT_RANGE = 128

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "StationID")
	self:NetworkVar("Int", 0, "OwnerCharacter")

	-- Smelting state for the tooltip; stations that do not smelt leave these empty.
	self:NetworkVar("String", 1, "SmeltContents")
	self:NetworkVar("Int", 1, "SmeltFuel")
	self:NetworkVar("Float", 0, "SmeltEnd")
end

function ENT:GetStationTable()
	return PLUGIN.craft.stations[self:GetStationID() != "" and self:GetStationID() or self.uniqueID]
end

function ENT:IsSmelter()
	local station = self:GetStationTable()

	return ix.smelting != nil and station != nil and station.smelting != nil
end

-- A station that does not smelt is a bench: things are made at it (PLUGIN.craft.GetStationList).
function ENT:IsBench()
	return self:GetStationTable() != nil and !self:IsSmelter()
end

-- Admins can pick up any station; players only the ones their current character placed.
function ENT:CanPickUp(client)
	local character = client:GetCharacter()

	if (!character) then
		return false
	end

	return client:IsAdmin() or (self:GetOwnerCharacter() != 0 and self:GetOwnerCharacter() == character:GetID())
end

if (SERVER) then
	function ENT:SpawnFunction(client, trace, className)
		local entity = ents.Create(className)
		entity:SetAngles(Angle(0, client:EyeAngles().y + 180, 0))
		entity:SetPos(trace.HitPos)
		entity:Spawn()
		entity:Activate()
		entity:SetPos(trace.HitPos - Vector(0, 0, entity:OBBMins().z))

		if (ix.station) then
			ix.station.QueueSave()
		end

		return entity
	end

	function ENT:Initialize()
		local station = self:GetStationTable()

		-- the bare base has no station definition and is never meant to exist on its own
		if (!station) then
			self:Remove()
			return
		end

		self:SetStationID(self.uniqueID)
		self:SetModel(station:GetModel())
		self:SetSolid(SOLID_VPHYSICS)

		if (!self:PhysicsInit(SOLID_VPHYSICS)) then
			self:PhysicsInitBox(FALLBACK_MINS, FALLBACK_MAXS)
			self:SetCollisionBounds(FALLBACK_MINS, FALLBACK_MAXS)
		end

		self:SetMoveType(MOVETYPE_VPHYSICS)

		local physObj = self:GetPhysicsObject()

		if (IsValid(physObj)) then
			physObj:EnableMotion(false)
			physObj:Sleep()
		end

		if (self:IsSmelter()) then
			ix.smelting.Register(self)
		end
	end

	-- Choices from the entity menu (GetEntityMenu below). Helix does not check the player's state
	-- before calling this, and glutcraft lets this range check replace Helix's, so everything is
	-- validated here.
	function ENT:OnOptionSelected(client, option, data)
		if (!istable(data) or !isstring(data.action) or self:IsMarkedForDeletion()) then
			return
		end

		if (!client:Alive() or !client:GetCharacter() or client:IsRestricted() or IsValid(client.ixRagdoll)) then
			return
		end

		if (client:GetShootPos():DistToSqr(self:NearestPoint(client:GetShootPos())) > INTERACT_RANGE * INTERACT_RANGE) then
			return
		end

		if ((client.ixNextStationAction or 0) > CurTime()) then
			return
		end

		client.ixNextStationAction = CurTime() + 0.5

		if (data.action == "pickup") then
			if (ix.station) then
				ix.station.PickUp(client, self)
			end
		elseif (self:IsSmelter()) then
			ix.smelting.HandleAction(self, client, data)
		end
	end

	function ENT:OnRemove()
		if (ix.smelting) then
			ix.smelting.Unregister(self)
		end

		if (ix.station) then
			ix.station.QueueSave()
		end
	end

	function ENT:UpdateTransmitState()
		return TRANSMIT_PVS
	end
else
	ENT.PopulateEntityInfo = true

	function ENT:OnPopulateEntityInfo(tooltip)
		local station = self:GetStationTable()

		if (station) then
			PLUGIN:PopulateStationTooltip(tooltip, station)

			if (self:IsSmelter()) then
				ix.smelting.PopulateTooltip(self, tooltip)
			end
		end
	end

	function ENT:GetEntityMenu(client)
		local options = {}

		if (self:IsSmelter()) then
			ix.smelting.AddMenuOptions(self, client, options)
		end

		if (self:CanPickUp(client)) then
			options["Pick Up"] = function()
				return {action = "pickup"}
			end
		end

		return options
	end

	-- Tapping Use at a bench opens what can be made there; at a smelter it collects the output when there
	-- is some, and otherwise opens its options (see the interaction plugin).
	function ENT:GetInteractionTap(client)
		if (self:IsBench()) then
			return L("craftOpen"), function()
				PLUGIN:OpenStationPanel(self)
			end
		elseif (self:IsSmelter() and ix.smelting.HasOutput(self)) then
			return "Collect output", function()
				ix.menu.NetworkChoice(self, "Collect output", {action = "collect"})
			end
		end
	end

	-- scheduled first, so that an error in the effects can never stop the thinking
	function ENT:Think()
		self:SetNextClientThink(CurTime() + 0.1)

		if (self:IsSmelter()) then
			ix.smelting.ThinkEffects(self)
		end

		return true
	end

	function ENT:Draw()
		self:DrawModel()
	end

	function ENT:DrawTranslucent()
		if (self.ixSmeltFX) then
			ix.smelting.DrawGlow(self)
		end
	end

	function ENT:OnRemove()
		if (ix.smelting and ix.smelting.StopEffects) then
			ix.smelting.StopEffects(self)
		end
	end
end
