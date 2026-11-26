AddCSLuaFile()

ENT.Base = "base_entity"
ENT.Type = "anim"
ENT.PrintName = "Application Terminal"
ENT.Category = "Helix"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH

if (SERVER) then
	function ENT:Initialize()
		self:SetModel("models/props_combine/breenconsole.mdl")
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
	end

	-- The terminal is world furniture and cannot be destroyed, so there is nothing to repair.
	function ENT:OnTakeDamage()
	end

	function ENT:Use(user)
		local character = IsValid(user) and user:IsPlayer() and user:GetCharacter()

		if (!character or self:GetNetVar("InUse", false)) then
			return
		end

		if (!character:GetInventory():HasItem("cid")) then
			user:Notify("You need a CID to do this.")
			self:EmitSound("buttons/combine_button_locked.wav")

			return
		end

		self:EmitSound("buttons/button14.wav", 100, 75)
		self:SetNetVar("InUse", true)

		user:SelectWeapon("ix_hands")
		user:Freeze(true)
		user:SetAction("Logging in...", 2)

		-- a timer rather than the SetAction callback, which is skipped when another action
		-- replaces this one and would leave the player frozen
		timer.Simple(2, function()
			if (IsValid(self)) then
				self:SetNetVar("InUse", false)
			end

			if (!IsValid(user)) then
				return
			end

			user:Freeze(false)

			if (user:Alive() and user:GetCharacter() == character) then
				-- SubmitApplication only accepts a form from someone who logged in here
				user.ixApplicationTerminal = true
				netstream.Start(user, "OpenApplicationMenu", {})
			end
		end)
	end
else
	surface.CreateFont("panel_font", {
		["font"] = "verdana",
		["size"] = 12,
		["weight"] = 128,
		["antialias"] = true
	})

	-- The 3D2D screen is from the original CW terminals plugin.
	function ENT:Draw()
		self:DrawModel()
		local ang = self:GetAngles()
		local pos = self:GetPos() + ang:Up() * 48 + ang:Right() * -5 + ang:Forward() * -9.75
		ang:RotateAroundAxis(ang:Forward(), 42)
		cam.Start3D2D(pos, ang, 0.1)
			local width, height = 155, 77
			surface.SetDrawColor(Color(16, 16, 16))
			surface.DrawRect(0, 0, width, height)
			surface.SetDrawColor(Color(255, 255, 255, 16))
			surface.DrawRect(0, height / 2 + math.sin(CurTime() * 4) * height / 2, width, 1)

			local alpha = 191 + 64 * math.sin(CurTime() * 4)

			if (!self:GetNetVar("InUse", false)) then
				draw.SimpleText("Application Terminal", "panel_font", width / 2, 25, Color(90, 210, 255, alpha), TEXT_ALIGN_CENTER)
				draw.SimpleText("Insert CID to begin!", "panel_font", width / 2, height - 16, Color(205, 255, 180, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		cam.End3D2D()
	end
end
