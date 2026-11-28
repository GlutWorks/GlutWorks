
local PLUGIN = PLUGIN

-- Bounded aim tremor from arm wounds and felt step-dip from leg wounds. Moves the view by the
-- frame-to-frame delta of a bounded wave so aim shakes or dips noticeably without drifting, and
-- returns cleanly to zero.
PLUGIN.tremor = {
	smoothing = 2.5,
	degrees = {0.14, 0.72},
	speed = 11.5
}

PLUGIN.limp = {
	smoothing = 4.0,
	dipDegrees = {0.45, 1.35},
	swayDegrees = {0.18, 0.55},
	pelvisRoll = {4.0, 9.0},
	spinePitch = {3.0, 7.0},
	spineRoll = {2.5, 6.0},
	range = 1400
}

local state = {
	shake = 0,
	limp = 0,
	limpPhase = 0,
	viewOffset = Angle(0, 0, 0),
	character = nil
}

local function ResetState()
	state.shake = 0
	state.limp = 0
	state.limpPhase = 0
	state.viewOffset = Angle(0, 0, 0)
	state.character = nil
end

local function ResetLimpBones(ply)
	if (!IsValid(ply) or !ply.ixBodyLimpActive) then
		return
	end

	for _, boneName in ipairs({"ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Spine"}) do
		local bone = ply:LookupBone(boneName)

		if (bone) then
			ply:ManipulateBoneAngles(bone, angle_zero)
		end
	end

	ply.ixBodyLimpActive = nil
	ply.ixBodyLimpPhase = nil
end

local function ClearAllLimpBones()
	for _, ply in player.Iterator() do
		ResetLimpBones(ply)
	end
end

local function Tremor(time)
	return math.sin(time) * 0.45 + math.sin(time * 1.63 + 1.4) * 0.35 + math.sin(time * 2.91 + 0.7) * 0.2
end

local function UpdateViewEffects(client, now)
	local offset = Angle(0, 0, 0)

	if (!ix.option.Get("reduceMotionEffects", false) and !client:InVehicle()
		and !IsValid(Entity(client:GetLocalVar("ragdoll", 0)))) then
		if (state.shake > 0.001) then
			local degrees = Lerp(state.shake, PLUGIN.tremor.degrees[1], PLUGIN.tremor.degrees[2])
			local time = now * PLUGIN.tremor.speed

			offset.p = offset.p + Tremor(time + 3.7) * degrees
			offset.y = offset.y + Tremor(time * 1.19) * degrees
		end

		if (state.limp > 0.001) then
			local hitch = math.max(0, math.sin(state.limpPhase)) ^ 2
			local dip = Lerp(state.limp, PLUGIN.limp.dipDegrees[1], PLUGIN.limp.dipDegrees[2])
			local sway = Lerp(state.limp, PLUGIN.limp.swayDegrees[1], PLUGIN.limp.swayDegrees[2])

			offset.p = offset.p + hitch * dip
			offset.y = offset.y + math.sin(state.limpPhase) * sway
		end
	end

	local delta = offset - state.viewOffset
	state.viewOffset = offset

	if (delta.p == 0 and delta.y == 0) then
		return
	end

	if (client.CanOverrideView and client:CanOverrideView() and client.camAng) then
		client.camAng.p = math.Clamp(client.camAng.p + delta.p, -85, 85)
		client.camAng.y = client.camAng.y + delta.y
	else
		local angles = client:EyeAngles()
		angles.p = math.Clamp(angles.p + delta.p, -89, 89)
		angles.y = angles.y + delta.y
		angles.r = 0

		client:SetEyeAngles(angles)
	end
end

local function UpdateLimpBones(frameTime)
	local bEnabled = ix.config.Get("bodyWoundsEnabled", true)
	local origin = EyePos()
	local maxDistSqr = PLUGIN.limp.range ^ 2

	for _, ply in player.Iterator() do
		local effects = bEnabled and ply:GetNetVar("bodyWoundEffects")
		local legPenalty = istable(effects) and tonumber(effects.legs) or 0
		local speed = ply:GetVelocity():Length2D()
		local bLimping = bEnabled and legPenalty > 0 and ply:Alive() and !ply:IsDormant()
			and ply:OnGround() and !ply:InVehicle() and speed > 15
			and ply:GetMoveType() != MOVETYPE_NOCLIP and !ply:GetNoDraw()
			and origin:DistToSqr(ply:EyePos()) <= maxDistSqr

		if (bLimping) then
			local cadence = math.Clamp(speed / 36, 2.2, 5.5)
			ply.ixBodyLimpPhase = (ply.ixBodyLimpPhase or (ply:EntIndex() * 0.9)) + frameTime * cadence

			local frac = math.Clamp(legPenalty / 0.35, 0, 1)
			local hitch = math.max(0, math.sin(ply.ixBodyLimpPhase)) ^ 2
			local pelvis = ply:LookupBone("ValveBiped.Bip01_Pelvis")
			local spine = ply:LookupBone("ValveBiped.Bip01_Spine")

			if (pelvis) then
				ply:ManipulateBoneAngles(pelvis, Angle(0, 0, hitch * Lerp(frac, PLUGIN.limp.pelvisRoll[1], PLUGIN.limp.pelvisRoll[2])))
			end

			if (spine) then
				ply:ManipulateBoneAngles(spine, Angle(
					hitch * Lerp(frac, PLUGIN.limp.spinePitch[1], PLUGIN.limp.spinePitch[2]),
					0,
					-hitch * Lerp(frac, PLUGIN.limp.spineRoll[1], PLUGIN.limp.spineRoll[2])
				))
			end

			ply.ixBodyLimpActive = true
		elseif (ply.ixBodyLimpActive) then
			ResetLimpBones(ply)
		end
	end
end

function PLUGIN:GetWoundTremorState()
	return state
end

function PLUGIN:Think()
	local client = LocalPlayer()

	if (!IsValid(client)) then
		return
	end

	local frameTime = RealFrameTime()
	UpdateLimpBones(frameTime)

	local character = client:GetCharacter()
	local bActive = ix.config.Get("bodyWoundsEnabled", true) and character != nil and client:Alive()
		and client:GetViewEntity() == client
		and !(IsValid(ix.gui.characterMenu) and !ix.gui.characterMenu:IsClosing())

	if (!bActive) then
		if (state.character) then
			ResetState()
		end

		return
	end

	if (state.character != character:GetID()) then
		ResetState()
		state.character = character:GetID()
	end

	local targetShake = ix.body.GetArmShake(client)
	local rate = frameTime * self.tremor.smoothing
	state.shake = math.Approach(state.shake, targetShake, rate)

	local effects = client:GetNetVar("bodyWoundEffects")
	local legPenalty = istable(effects) and tonumber(effects.legs) or 0
	local speed = client:GetVelocity():Length2D()
	local targetLimp = (legPenalty > 0 and client:OnGround() and speed > 15) and math.Clamp(legPenalty / 0.35, 0, 1) or 0

	if (targetLimp > 0) then
		state.limpPhase = state.limpPhase + frameTime * math.Clamp(speed / 36, 2.2, 5.5)
	end

	state.limp = math.Approach(state.limp, targetLimp, frameTime * self.limp.smoothing)

	UpdateViewEffects(client, RealTime())
end

function PLUGIN:PopulateCharacterInfo(client, character, tooltip)
	if (!ix.config.Get("bodyWoundsEnabled", true) or !IsValid(client) or !client:Alive()) then
		return
	end

	local effects = client:GetNetVar("bodyWoundEffects")

	if (!istable(effects)) then
		return
	end

	local harmColor = ix.body and ix.body.COLORS and ix.body.COLORS.harm

	if (isnumber(effects.legs) and effects.legs > 0) then
		local row = tooltip:AddRowAfter("description", "ixBodyLimp")
		row:SetText("Walking with a limp.")

		if (harmColor) then
			row:SetBackgroundColor(harmColor)
		end

		row:SizeToContents()
	end

	if (isnumber(effects.arms) and effects.arms > 0) then
		local row = tooltip:AddRowAfter("description", "ixBodyArmInjury")
		row:SetText("Favouring an injured arm.")

		if (harmColor) then
			row:SetBackgroundColor(harmColor)
		end

		row:SizeToContents()
	end
end

function PLUGIN:CharacterLoaded()
	ResetState()
end

function PLUGIN:ShutDown()
	ClearAllLimpBones()
end
