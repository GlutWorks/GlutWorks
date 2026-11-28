local PLUGIN = PLUGIN
ENT.Type = "anim"
ENT.PrintName = "Construction"
ENT.bInteractive = true
ENT.interactionTap = false
ENT.bNoPersist = true
ENT.PhysgunDisabled = true
ENT.DoNotDuplicate = true

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Kind")
	self:NetworkVar("Vector", 0, "Foot")
	self:NetworkVar("Int", 0, "Turn")
	self:NetworkVar("Int", 1, "Builder")
end

function ENT:CanSalvage(client)
	local char = client:GetCharacter()
	return char and (self:GetBuilder() == 0 or self:GetBuilder() == char:GetID() or client:IsAdmin())
end

if (SERVER) then
	function ENT:Fit(kind)
		local part = PLUGIN.parts[kind]
		if (!part) then return false end
		local pos, ang = PLUGIN:PartPose(kind, self:GetFoot(), self:GetTurn())
		self:SetModel(part.model)
		self:SetMaterial(part.material or "")
		self:SetPos(pos)
		self:SetAngles(ang)
		if (!self:PhysicsInit(SOLID_VPHYSICS)) then return false end
		self:SetMoveType(MOVETYPE_NONE)
		self:GetPhysicsObject():EnableMotion(false)
		self:SetKind(kind)
		return true
	end

	function ENT:Initialize()
		if (!self:Fit(self:GetKind())) then self:Remove() end
	end

	function ENT:OnOptionSelected(client, _, action)
		if (action != "salvage_" .. self:GetKind() or self:IsMarkedForDeletion() or !self:CanSalvage(client)
			or !ix.plugin.list.interaction:CanUseEntity(client, self)) then return end
		local kind = self:GetKind()
		if (PLUGIN:SupportsCut(self)) then client:Notify("Remove the pieces attached to this one first.") return end
		if (kind == "frame" and PLUGIN:HoldsRoof(self)) then
			client:Notify("Take the roof down before removing its support.")
			return
		end
		if (kind == "boards" or kind == "metal") then
			if (!self:Fit("frame")) then return end
		else
			self:Remove()
		end
		local part = PLUGIN.parts[kind]
		ix.stack.GiveOrDrop(client, part.item, part.cost)
		client:EmitSound("physics/wood/wood_box_impact_soft2.wav")
		PLUGIN:SaveData()
	end
else
	ENT.PopulateEntityInfo = true
	function ENT:OnPopulateEntityInfo(tooltip)
		local part = PLUGIN.parts[self:GetKind()]
		local name = tooltip:AddRow("name")
		name:SetText(part and part.name or self.PrintName)
		name:SizeToContents()
	end

	function ENT:GetEntityMenu(client)
		if (!self:CanSalvage(client)) then return {} end
		local kind = self:GetKind()
		local label = (kind == "boards" or kind == "metal") and "Remove cladding" or "Dismantle for scrap"
		return {[label] = function() return "salvage_" .. kind end}
	end
end
