
local PLUGIN = PLUGIN

PLUGIN.name = "Kick"
PLUGIN.author = "Oebelysk"
PLUGIN.description = "Adds /kickdoor functionality for Civil Protection."

PLUGIN.staminaCost = 25
PLUGIN.cooldown = 1.7
PLUGIN.impactDelay = 0.8
PLUGIN.minDistance = 65
PLUGIN.maxDistance = 100
PLUGIN.breakChance = 0.5

--- Checks whether `client` may kick `door` right now. Returns false and a message if not.
function PLUGIN:CanKick(client, door)
	if (!client:Alive() or IsValid(client.ixRagdoll) or client:IsRestricted()) then
		return false, "You cannot do that right now!"
	end

	if (!client:IsCombine()) then
		return false, "You are not Civil Protection!"
	end

	if (!IsValid(door) or door:GetClass() != "prop_door_rotating" or door:GetNetVar("disabled")) then
		return false, "You are not looking at a door!"
	end

	if (client:GetVelocity():LengthSqr() > 1) then
		return false, "You need to be standing still!"
	end

	local distance = client:GetPos():Distance(door:GetPos())

	if (distance >= self.maxDistance) then
		return false, "You are not close enough to the door!"
	elseif (distance <= self.minDistance) then
		return false, "You are too close to the door!"
	end

	if (client:GetLocalVar("stm", 0) <= self.staminaCost) then
		return false, "You don't have enough stamina!"
	end

	if ((client.ixNextKick or 0) > CurTime()) then
		return false, "You are using this command too quickly!"
	end

	return true
end

--- The kick lands: either the door comes off its hinges or it just takes the hit.
function PLUGIN:KickImpact(client, door, bBreak)
	if (!IsValid(door)) then
		return
	end

	if (!bBreak) then
		door:EmitSound("physics/wood/wood_panel_impact_hard1.wav", 90)
		return
	end

	door:EmitSound("physics/wood/wood_plank_break1.wav", 90)

	for _, offset in ipairs({Vector(0, 0, 24), Vector(0, 0, -24)}) do
		local effect = EffectData()
			effect:SetStart(door:GetPos() + offset)
			effect:SetOrigin(door:GetPos() + offset)
			effect:SetScale(5)
		util.Effect("GlassImpact", effect)
	end

	local direction = IsValid(client) and client:GetAimVector() or door:GetForward()
	door:BlastDoor(direction * 300, 120, false)
end

function PLUGIN:Kick(client, door)
	client.ixNextKick = CurTime() + self.cooldown
	client:ConsumeStamina(self.staminaCost)
	client:ForceSequence("kickdoorbaton")

	-- Show the kick from third person, then put the camera back the way it was. The option
	-- is only readable here when the thirdperson option is networked; otherwise it reads as
	-- first person and the toggle is undone afterwards all the same.
	local bWasThirdPerson = ix.option.Get(client, "thirdpersonEnabled", false)

	if (!bWasThirdPerson) then
		client:ConCommand("ix_togglethirdperson")
	end

	local bBreak = math.random() < self.breakChance

	timer.Simple(self.impactDelay, function()
		self:KickImpact(client, door, bBreak)
	end)

	timer.Simple(self.cooldown, function()
		if (IsValid(client) and !bWasThirdPerson) then
			client:ConCommand("ix_togglethirdperson")
		end
	end)
end

ix.command.Add("KickDoor", {
	description = "Attempt to kick down the door.",
	OnRun = function(self, client)
		local door = client:GetEyeTrace().Entity
		local bCanKick, message = PLUGIN:CanKick(client, door)

		if (!bCanKick) then
			return message
		end

		PLUGIN:Kick(client, door)
	end
})
