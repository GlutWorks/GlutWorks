
local PLUGIN = PLUGIN

PLUGIN.name = "Shoot Locks"
PLUGIN.author = "Chessnut ported to Helix by FatherSquirrel"
PLUGIN.description = "Shoot a door's lock to open it, or blast it off its hinges with a shotgun."

PLUGIN.shootDistance = 180
PLUGIN.handleRadius = 12

-- Shotguns are identified by their weapon item (ITEM.isShotgun) or, for weapons without an
-- item, by this list.
PLUGIN.shotgunClasses = {
	["weapon_shotgun"] = true
}

function PLUGIN:IsShotgun(weapon)
	if (!IsValid(weapon)) then
		return false
	end

	return (weapon.ixItem and weapon.ixItem.isShotgun) or self.shotgunClasses[weapon:GetClass()] or false
end

--- Blasts the door off its hinges.
function PLUGIN:BreachDoor(client, door, position)
	door:EmitSound("physics/wood/wood_crate_break" .. math.random(1, 5) .. ".wav", 150)
	door:BlastDoor(client:GetAimVector() * 380)

	local effect = EffectData()
		effect:SetStart(position)
		effect:SetOrigin(position)
		effect:SetScale(10)
	util.Effect("GlassImpact", effect, true, true)

	door.ixNextBreach = CurTime() + 1
end

--- Breaks the lock and swings the door open away from the shooter.
function PLUGIN:BustLock(client, door, position)
	local effect = EffectData()
		effect:SetStart(position)
		effect:SetOrigin(position)
		effect:SetScale(2)
	util.Effect("GlassImpact", effect)

	-- openawayfrom takes a targetname
	local name = "ixBreacher" .. client:EntIndex()
	client:SetName(name)

	door.ixOldSpeed = door.ixOldSpeed or door:GetKeyValues().speed or 100

	door:Fire("setspeed", door.ixOldSpeed * 3.5)
	door:Fire("unlock")
	door:Fire("openawayfrom", name)
	door:EmitSound("physics/wood/wood_plank_break" .. math.random(1, 4) .. ".wav", 100, 120)

	door.ixNextBreach = CurTime() + 1

	timer.Simple(0.5, function()
		if (IsValid(door)) then
			door:Fire("setspeed", door.ixOldSpeed)
		end
	end)
end

function PLUGIN:EntityTakeDamage(entity, dmgInfo)
	if (entity:GetClass() != "prop_door_rotating" or (entity.ixNextBreach or 0) >= CurTime() or !dmgInfo:IsBulletDamage()) then
		return
	end

	local handle = entity:LookupBone("handle")
	local client = dmgInfo:GetAttacker()

	if (!handle or !IsValid(client) or !client:IsPlayer()) then
		return
	end

	local position = dmgInfo:GetDamagePosition()

	if (client:GetEyeTrace().Entity != entity or client:GetPos():Distance(position) > self.shootDistance) then
		return
	end

	if (hook.Run("CanPlayerBustLock", client, entity) == false) then
		return
	end

	if (self:IsShotgun(client:GetActiveWeapon())) then
		self:BreachDoor(client, entity, position)
	elseif (position:Distance(entity:GetBonePosition(handle)) <= self.handleRadius) then
		self:BustLock(client, entity, position)
	end
end
