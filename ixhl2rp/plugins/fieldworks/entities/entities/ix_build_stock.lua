local PLUGIN = PLUGIN
ENT.Type = "anim"
ENT.PrintName = "Construction material"
ENT.bInteractive = true
ENT.interactionTap = false
ENT.bNoPersist = true
ENT.DoNotDuplicate = true
ENT.PhysgunDisabled = true

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Stock")
	self:NetworkVar("Vector", 0, "Size")
	self:NetworkVar("Int", 0, "Builder")
end

function ENT:UpdateShape()
	local half = self:GetSize() / 2
	if (half.x <= 0 or half.y <= 0 or half.z <= 0) then return end
	self:PhysicsInitBox(-half, half)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_NONE)
	self:EnableCustomCollisions(true)
	local phys = self:GetPhysicsObject()
	if (!IsValid(phys)) then return end
	phys:SetPos(self:GetPos())
	phys:SetAngles(self:GetAngles())
	phys:EnableMotion(false)
	phys:Sleep()
	if (CLIENT) then self:SetRenderBounds(-half, half) end
	return true
end

function ENT:CanRecover(client)
	local char = client:GetCharacter()
	return char and (char:GetID() == self:GetBuilder() or client:IsAdmin())
end

if (SERVER) then
	function ENT:Initialize()
		self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
		if (!PLUGIN.stock[self:GetStock()] or !self:UpdateShape()) then self:Remove() end
	end

	function ENT:OnOptionSelected(client, _, action)
		if (action != "recover" or self:IsMarkedForDeletion() or !self:CanRecover(client)
			or !ix.plugin.list.interaction:CanUseEntity(client, self)) then return end
		if (PLUGIN:SupportsCut(self)) then client:Notify("Remove the pieces attached to this one first.") return end
		local kind, size = self:GetStock(), self:GetSize()
		self:Remove()
		ix.stack.GiveOrDrop(client, PLUGIN.stock[kind].item, PLUGIN:StockCost(kind, size))
		PLUGIN:SaveData()
	end
else
	ENT.PopulateEntityInfo = true

	function ENT:Think()
		if (self.shapeReady) then return end
		self.shapeReady = self:UpdateShape()
	end

	function ENT:Draw()
		local stock = PLUGIN.stock[self:GetStock()]
		if (!stock) then return end
		local half = self:GetSize() / 2
		render.SetMaterial(ix.util.GetMaterial(stock.material))
		render.DrawBox(self:GetPos(), self:GetAngles(), -half, half, color_white)
	end

	function ENT:OnPopulateEntityInfo(tooltip)
		local stock = PLUGIN.stock[self:GetStock()]
		if (!stock) then return end
		local row = tooltip:AddRow("name")
		local size = self:GetSize()
		row:SetText(string.format("%s, %.0f × %.0f units", stock.name, size.x, size.y))
		row:SizeToContents()
	end

	function ENT:GetEntityMenu(client)
		if (self:CanRecover(client)) then return {["Recover material"] = function() return "recover" end} end
		return {}
	end
end
