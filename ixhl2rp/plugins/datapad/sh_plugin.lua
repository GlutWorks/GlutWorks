PLUGIN.name = "Field Datapad"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Carry, body readings and searches on a handheld field terminal."

ix.datapad = ix.datapad or {}
local pad = ix.datapad

function pad.Available(client)
	return IsValid(client) and client:GetCharacter() and client:Alive() and !client:IsRestricted()
		and client:GetLocalVar("ragdoll", 0) == 0 and !IsValid(client.ixRagdoll)
end

ix.util.Include("sh_carry.lua")
ix.util.Include("sh_body.lua")
ix.util.Include("sv_device.lua")
ix.util.Include("sv_frisk.lua")
ix.util.Include("cl_device.lua")
ix.util.Include("cl_display.lua")

function PLUGIN:StartCommand(client, cmd)
	if (client:GetNetVar("datapadRaised")) then
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
		cmd:RemoveKey(IN_SPEED)
		cmd:RemoveKey(IN_USE)
	end
end

function PLUGIN:SetupMove(client, move)
	local band = client:GetLocalVar("carryBand", 1)
	if (band > 1 and move:KeyDown(IN_SPEED)) then
		local speed = math.min(move:GetMaxClientSpeed(), client:GetRunSpeed() * (band == 3 and 0.67 or 0.84))
		move:SetMaxClientSpeed(speed)
	end
end

function PLUGIN:CalcMainActivity(client, velocity)
	if (client:GetNetVar("datapadRaised") and client:OnGround() and !client:Crouching() and !client:InVehicle()) then
		return velocity:Length2D() > 4 and ACT_HL2MP_WALK_SLAM or ACT_HL2MP_IDLE_SLAM, -1
	end
end
