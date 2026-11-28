
AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "Vending Machine"
ENT.Category = "HL2 RP"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.PhysgunDisable = true
ENT.bNoPersist = true

ENT.MaxRenderDistance = math.pow(256, 2)
ENT.MaxStock = 4
ENT.Items = {
	{"REGULAR", "water", 15},
	{"SPARKLING", "water_sparkling", 25},
	{"SPECIAL", "water_special", 35}
}

function ENT:GetStock(id)
	return self:GetNetVar("stock", {})[id] or self.MaxStock
end

function ENT:GetAllStock()
	return self:GetNetVar("stock", {})
end

-- Broken open by a crowbar break-in (server, below): the stock netvar already shows empty
-- buttons on the client, and this netvar marks the machine itself broken until repaired.
function ENT:IsBroken()
	return self:GetNetVar("broken", false) == true
end

ENT.BreakInThreshold = 150

if (SERVER) then
	function ENT:Initialize()
		self:SetModel("models/props_interiors/vendingmachinesoda01a.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		local physics = self:GetPhysicsObject()
		physics:EnableMotion(false)
		physics:Sleep()

		self.nextUseTime = 0
		self.breakInDamage = 0
		self:SetNetVar("stock", {})
		-- broken need not persist: Schema:SaveVendingMachines stores pos/ang/stock only, so a
		-- broken machine comes back repaired (but still empty) after a restart
		self:SetNetVar("broken", false)
	end

	-- The crowbar-in-hand test for a break-in. Duplicates scavenging's HasBreakTool crowbar
	-- branch: the schema must not depend on that plugin. Server-side only.
	local function HasCrowbar(client)
		if (!IsValid(client) or !client:IsPlayer() or !client:Alive() or client:IsRestricted() or IsValid(client.ixRagdoll)) then
			return false
		end

		local weapon = client:GetActiveWeapon()

		return IsValid(weapon) and weapon:GetClass() == "tfa_projecthl2_crowbar"
	end

	-- A non-Combine player with a crowbar can break the machine open: its drink stock spills
	-- out as world items and it stays broken until a Combine restock repairs it (Use, below).
	function ENT:OnTakeDamage(dmginfo)
		if (self:IsBroken() or dmginfo:GetInflictor() == self) then
			return
		end

		local attacker = dmginfo:GetAttacker()

		if (!HasCrowbar(attacker)) then
			return
		end

		local character = attacker:GetCharacter()

		if (!character or character:IsCombine()) then
			return
		end

		self.breakInDamage = (self.breakInDamage or 0) + dmginfo:GetDamage()

		if (self.breakInDamage >= self.BreakInThreshold) then
			self:BreakOpen()
		end
	end

	function ENT:BreakOpen()
		local position = self:GetPos() + self:GetForward() * 19 + self:GetRight() * 4 + self:GetUp() * -26

		for id, itemInfo in ipairs(self.Items) do
			local count = self:GetStock(id)

			-- the waters are not stackable, so each can drops on its own; a stackable
			-- drink would go through ix.stack instead
			if (ix.stack and ix.stack.IsStackable(itemInfo[2])) then
				if (count > 0) then
					ix.stack.Spawn(itemInfo[2], position, count)
				end
			else
				for _ = 1, count do
					ix.item.Spawn(itemInfo[2], position)
				end
			end

			self:SetStock(id, 0)
		end

		self.breakInDamage = 0
		self:SetNetVar("broken", true)
		self:EmitSound("physics/metal/metal_box_break1.wav", 80)
	end

	function ENT:SpawnFunction(client, trace)
		local vendor = ents.Create("ix_vendingmachine")

		vendor:SetPos(trace.HitPos + Vector(0, 0, 48))
		vendor:SetAngles(Angle(0, (vendor:GetPos() - client:GetPos()):Angle().y - 180, 0))
		vendor:Spawn()
		vendor:Activate()

		Schema:SaveVendingMachines()
		return vendor
	end

	function ENT:GetClosestButton(client)
		local data = {}
			data.start = client:GetShootPos()
			data.endpos = data.start + client:GetAimVector() * 96
			data.filter = client
		local trace = util.TraceLine(data)
		local tracePosition = trace.HitPos

		if (tracePosition) then
			for k, v in ipairs(self.Items) do
				local position = self:GetPos() + self:GetForward() * 17.5 + self:GetRight() * -24.4 + (self:GetUp() * 5.3 - Vector(0, 0, (k - 1) * 2.1))

				if (position:DistToSqr(tracePosition) <= 1) then
					return k
				end
			end
		end
	end

	function ENT:SetStock(id, amount)
		if (type(id) == "table") then
			self:SetNetVar("stock", id)
			return
		end

		local stock = self:GetNetVar("stock", {})
		stock[id] = math.Clamp(amount, 0, self.MaxStock)

		self:SetNetVar("stock", stock)
	end

	function ENT:ResetStock(id)
		local stock = self:GetNetVar("stock", {})

		-- reset stock of all items if no id is specified
		if (id) then
			stock[id] = self.MaxStock
		else
			for k, v in ipairs(self.Items) do
				stock[k] = self.MaxStock
			end
		end

		self:SetNetVar("stock", stock)
	end

	function ENT:RemoveStock(id)
		self:SetStock(id, self:GetStock(id) - 1)
	end

	function ENT:Use(client)
		local buttonID = self:GetClosestButton(client)

		if (buttonID) then
			client:EmitSound("buttons/lightswitch2.wav", 40, 150)
		else
			return
		end

		local character = client:GetCharacter()

		if (!character or self.nextUseTime > CurTime()) then
			return
		end

		-- broken open: nobody can buy until a Combine unit repairs it through the restock
		-- branch below (its stock is 0, so that branch runs and restocks as it repairs)
		if (self:IsBroken()) then
			if (!character:IsCombine()) then
				return
			end

			self:SetNetVar("broken", false)
			self.breakInDamage = 0
		end

		if (!character:IsCombine()) then
			local itemInfo = self.Items[buttonID]
			local price = itemInfo[3]

			if (!character:HasMoney(price)) then
				self:EmitSound("buttons/button2.wav", 50)
				self.nextUseTime = CurTime() + 1

				client:NotifyLocalized("vendingNeedMoney", ix.currency.Get(price))
				return false
			end

			if (self:GetStock(buttonID) > 0) then
				-- set before spawning: the spawn callback can run later, and a second use in
				-- between would sell another drink from the same stock and money
				self.nextUseTime = CurTime() + 1

				ix.item.Spawn(itemInfo[2], self:GetPos() + self:GetForward() * 19 + self:GetRight() * 4 + self:GetUp() * -26, function(item, entity)
					self:EmitSound("buttons/button4.wav", 60)

					-- the drink drops out and the machine is heard; nothing is said
					character:TakeMoney(price)

					self:RemoveStock(buttonID)
				end)
			else
				self:EmitSound("buttons/button2.wav", 50)
				self.nextUseTime = CurTime() + 1
			end
		elseif (self:GetStock(buttonID) == 0) then
			self:ResetStock(buttonID)

			-- the button's light shows the stock is back; the machine is heard taking it
			self:EmitSound("buttons/button4.wav", 60)
			self.nextUseTime = CurTime() + 1
		end
	end

	function ENT:OnRemove()
		if (!ix.shuttingDown and !Schema.bCleaningUp) then
			Schema:SaveVendingMachines()
		end
	end
else
	surface.CreateFont("ixVendingMachine", {
		font = "Default",
		size = 13,
		weight = 800,
		antialias = false
	})

	-- the price under each item's name, so a buyer sees what a drink costs on the machine itself
	surface.CreateFont("ixVendingMachinePrice", {
		font = "Default",
		size = 11,
		weight = 500,
		antialias = false
	})

	local color_price = Color(210, 200, 150, 255)

	local color_red = Color(100, 20, 20, 255)
	local color_blue = Color(0, 50, 100, 255)
	local color_black = Color(60, 60, 60, 255)

	function ENT:Draw()
		self:DrawModel()

		local position = self:GetPos()

		if (LocalPlayer():GetPos():DistToSqr(position) > self.MaxRenderDistance) then
			return
		end

		local angles = self:GetAngles()
		local forward, right, up = self:GetForward(), self:GetRight(), self:GetUp()

		angles:RotateAroundAxis(angles:Up(), 90)
		angles:RotateAroundAxis(angles:Forward(), 90)

		cam.Start3D2D(position + forward * 17.33 + right * -19.2 + up * 6.1, angles, 0.06)
			render.PushFilterMin(TEXFILTER.NONE)
			render.PushFilterMag(TEXFILTER.NONE)

			local width = 70
			local smallWidth = 20
			local height = 29
			local halfWidth = width / 2
			local halfHeight = height / 2

			for i = 1, 8 do
				local itemInfo = self.Items[i]
				local x = 0
				local y = (i - 1) * 34

				surface.SetDrawColor(color_black)
				surface.DrawOutlinedRect(x, y, width, height)

				surface.SetDrawColor(color_black)
				surface.DrawRect(x + 1, y + 1, width - 2, height - 2)

				surface.SetDrawColor(color_red)

				if (itemInfo) then
					draw.SimpleText(itemInfo[1], "ixVendingMachine", x + halfWidth, y + halfHeight - 5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					draw.SimpleText(ix.currency.Get(itemInfo[3]), "ixVendingMachinePrice", x + halfWidth, y + halfHeight + 7, color_price, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

					if (self:GetStock(i) > 0) then
						surface.SetDrawColor(color_blue)
					end
				end

				surface.DrawRect(x + width + 6, y, smallWidth, height)
			end

			render.PopFilterMin()
			render.PopFilterMag()
		cam.End3D2D()
	end
end
