local PLUGIN = PLUGIN

ENT.Type = "anim"
ENT.PrintName = "Site supplies"
ENT.bInteractive = true
ENT.interactionTap = false
ENT.bNoPersist = true
ENT.PhysgunDisabled = true
ENT.DoNotDuplicate = true

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Sections")
end

function ENT:HasSection(flag)
	return bit.band(self:GetSections(), flag) != 0
end

function ENT:CanBuild(key)
	local piece = PLUGIN.pieces[key]
	if (!piece or !piece.item) then return false end
	if (piece.flag and self:HasSection(piece.flag)) then return false end
	if (self:HasSection(16) or self:HasSection(32)) then return false end
	return key != "roof" or (self:HasSection(1) and self:HasSection(2))
end

if (SERVER) then
	function ENT:Initialize()
		self:SetModel("models/props_junk/wood_crate001a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
		self:GetPhysicsObject():EnableMotion(false)
	end

	function ENT:OnOptionSelected(client, option, key)
		if (!isstring(key) or self:IsMarkedForDeletion() or !self:CanBuild(key)) then return end
		if (!ix.plugin.list.interaction:CanUseEntity(client, self)) then return end
		PLUGIN:Build(self, client, key)
	end
else
	ENT.PopulateEntityInfo = true

	function ENT:OnPopulateEntityInfo(tooltip)
		local row = tooltip:AddRow("name")
		row:SetText(self.PrintName)
		row:SizeToContents()

		local desc = tooltip:AddRow("description")
		if (self:HasSection(16) or self:HasSection(32)) then
			desc:SetText("A survey crate. Hold Reload to raise your crowbar, then break the packed rock to clear the workshop bay.")
		else
			desc:SetText("A survey crate. Use scrap to build here. The two side walls support a sheet roof.")
		end
		desc:SizeToContents()
	end

	function ENT:GetEntityMenu()
		local options = {}
		for key, piece in pairs(PLUGIN.pieces) do
			if (self:CanBuild(key)) then
				local material = piece.item == "wooden_scrap" and "wood" or "metal"
				options[piece.label .. " (" .. piece.cost .. " kg " .. material .. ")"] = function() return key end
			end
		end

		return options
	end
end
