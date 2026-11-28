
local PLUGIN = PLUGIN

-- Bounded aim tremor from arm wounds. Moves the view by the frame-to-frame delta of a bounded
-- wave so aim shakes noticeably without permanently drifting, and returns cleanly to zero.
PLUGIN.tremor = {
	smoothing = 2.5,
	degrees = {0.14, 0.72},
	speed = 11.5
}

local state = {
	shake = 0,
	shakeOffset = Angle(0, 0, 0),
	character = nil
}

local function ResetState()
	state.shake = 0
	state.shakeOffset = Angle(0, 0, 0)
	state.character = nil
end

local function Tremor(time)
	return math.sin(time) * 0.45 + math.sin(time * 1.63 + 1.4) * 0.35 + math.sin(time * 2.91 + 0.7) * 0.2
end

local function UpdateTremor(client, now)
	local offset

	if (state.shake <= 0.001 or ix.option.Get("reduceMotionEffects", false) or client:InVehicle()
		or IsValid(Entity(client:GetLocalVar("ragdoll", 0)))) then
		offset = Angle(0, 0, 0)
	else
		local degrees = Lerp(state.shake, PLUGIN.tremor.degrees[1], PLUGIN.tremor.degrees[2])
		local time = now * PLUGIN.tremor.speed

		offset = Angle(Tremor(time + 3.7) * degrees, Tremor(time * 1.19) * degrees, 0)
	end

	local delta = offset - state.shakeOffset
	state.shakeOffset = offset

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

function PLUGIN:GetWoundTremorState()
	return state
end

function PLUGIN:Think()
	local client = LocalPlayer()

	if (!IsValid(client)) then
		return
	end

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
	local rate = RealFrameTime() * self.tremor.smoothing

	state.shake = math.Approach(state.shake, targetShake, rate)

	UpdateTremor(client, RealTime())
end

function PLUGIN:CharacterLoaded()
	ResetState()
end
