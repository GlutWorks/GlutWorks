-- The station's departures (plugins/arriving): a checkpoint booth on the platform. Tapping Use offers the
-- train out of the city; whoever takes it chooses on the train who comes in instead (sv_plugin.lua, Depart).
-- It works only where it's safe to leave from (ix.logoff), which the station is.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Departures"
ENT.Spawnable = false
ENT.bNoPersist = true
ENT.bInteractive = true
ENT.PhysgunDisabled = true

ENT.model = "models/props_combine/combine_booth_short01a.mdl"

function ENT:Initialize()
	self:SetModel(self.model)

	if (SERVER) then
		local PLUGIN = ix.plugin.list.arriving

		if (PLUGIN) then
			PLUGIN:MakeFixture(self)
		end
	end
end

if (CLIENT) then
	function ENT:OnPopulateEntityInfo(container)
		local name = container:AddRow("name")
		name:SetImportant()
		name:SetText("Departures")
		name:SizeToContents()

		local description = container:AddRow("description")
		description:SetText("The checkpoint for trains out of the city. Leaving, you choose who comes in instead.")
		description:SizeToContents()
	end

	-- Tapping Use asks before anyone leaves.
	function ENT:GetInteractionTap(client)
		return "Take the train out", function()
			ix.worldui.Open({
				anchor = self,
				name = "departures",
				title = "Departures",
				rows = {{label = "Leave the city by train", detail = "choose who comes in"}},
				OnSelect = function()
					net.Start("ixArrivingDepart")
						net.WriteEntity(self)
					net.SendToServer()
				end
			})
		end
	end
end
