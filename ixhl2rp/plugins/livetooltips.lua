
local PLUGIN = PLUGIN

PLUGIN.name = "Live Entity Tooltips"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Rebuilds the tooltip of the entity being looked at when what it shows has changed."

-- Helix fills an entity's tooltip once, when the player starts looking at it, so a smelter's countdown or a
-- stack's quantity stayed as it was until the player looked away and back. An entity opts in by defining
-- ENT:GetEntityInfoState(), returning a string that changes whenever its tooltip should; world items are
-- covered here through their networked data.
if (CLIENT) then
	local nextCheck = 0

	local function GetState(entity)
		if (entity.GetEntityInfoState) then
			return entity:GetEntityInfoState()
		elseif (entity:GetClass() == "ix_item") then
			return util.TableToJSON(entity:GetNetVar("data", {}))
		end
	end

	function PLUGIN:Think()
		local now = RealTime()

		if (now < nextCheck) then
			return
		end

		nextCheck = now + 0.2

		local panel = ix.gui.entityInfo

		-- The minimal tooltip keeps its own layout children, so it is left as Helix made it.
		if (!IsValid(panel) or !panel.bEntity or panel:GetName() != "ixTooltip") then
			return
		end

		local entity = panel:GetEntity()

		if (!IsValid(entity) or entity:IsPlayer()) then
			return
		end

		local state = GetState(entity)

		if (state == nil) then
			return
		end

		if (panel.ixInfoEntity != entity) then
			panel.ixInfoEntity = entity
			panel.ixInfoState = state

			return
		end

		if (panel.ixInfoState == state) then
			return
		end

		panel.ixInfoState = state

		-- Removal is deferred to the end of the frame; detach the old rows first so the new ones are sized
		-- and found without them.
		for _, child in ipairs(panel:GetChildren()) do
			child:SetVisible(false)
			child:SetParent(nil)
			child:Remove()
		end

		if (entity.OnPopulateEntityInfo) then
			entity:OnPopulateEntityInfo(panel)
		else
			hook.Run("PopulateEntityInfo", entity, panel)
		end

		panel:SizeToContents()
	end
end
