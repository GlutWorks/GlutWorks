
local PLUGIN = PLUGIN

-- Damage taken right after being knocked out is ignored for this long, so the rest of the
-- burst that knocked someone down (or the ragdoll hitting the floor) does not finish them.
PLUGIN.knockoutGrace = 0.3

local fallSounds = {"player/pl_fallpain1.wav", "player/pl_fallpain3.wav"}

local function BloodEffects(position)
	local spray = EffectData()
		spray:SetStart(position)
		spray:SetOrigin(position)
		spray:SetFlags(3)
		spray:SetColor(0)
		spray:SetScale(6)
	util.Effect("bloodspray", spray)

	local splatter = EffectData()
		splatter:SetStart(position)
		splatter:SetOrigin(position)
		splatter:SetScale(10)
	util.Effect("BloodImpact", splatter)
end

--- Knocks a player out for `time` seconds. The state is remembered on the character if they
-- disconnect, so rejoining resumes it.
function PLUGIN:KnockOut(client, time)
	client:SetRagdolled(true, time)

	local ragdoll = client.ixRagdoll

	if (IsValid(ragdoll)) then
		ragdoll.ixKnockout = true
		ragdoll.ixFallGrace = CurTime() + self.knockoutGrace
		client.ixKnockoutGrace = CurTime() + self.knockoutGrace
	end
end

--- Seconds left of a knockout started by this plugin, or nil if the player is not knocked out.
function PLUGIN:GetKnockoutRemaining(client)
	local ragdoll = client.ixRagdoll

	if (!IsValid(ragdoll) or !ragdoll.ixKnockout) then
		return
	end

	return math.max((ragdoll.ixFinish or CurTime()) - CurTime(), 1)
end

function PLUGIN:EntityTakeDamage(target, dmg)
	if (!target:IsPlayer()) then
		return
	end

	local damage = dmg:GetDamage()

	if (damage <= 0) then
		return
	end

	-- A downed player only takes damage through their ragdoll; Helix forwards it here.
	if (IsValid(target.ixRagdoll)) then
		if ((target.ixKnockoutGrace or 0) > CurTime()) then
			dmg:SetDamage(0)
			return
		end

		dmg:ScaleDamage(0.5)

		if (damage > 10 and dmg:GetInflictor() == game.GetWorld()) then
			target:EmitSound(fallSounds[math.random(#fallSounds)])
		end

		BloodEffects(dmg:GetDamagePosition())
	end
end

-- Knockouts and falling over are decided from the health the hit actually left, once armour,
-- god mode and other plugins have had their say. Ragdolling before the hit would also switch off
-- god mode (SetRagdolled does) and let the damage through.
function PLUGIN:PostEntityTakeDamage(target, dmg, bTook)
	if (!bTook or !target:IsPlayer() or dmg:GetDamage() <= 0) then
		return
	end

	if (!target:Alive() or target:HasGodMode() or IsValid(target.ixRagdoll) or target:Health() <= 0) then
		return
	end

	if (target:Health() < ix.config.Get("unconsciousHealth", 20)) then
		self:KnockOut(target, ix.config.Get("unconsciousTime", 100))
		return
	end

	if (dmg:IsFallDamage() and ix.config.Get("falloverAfterFallDamage", true)) then
		target:SetRagdolled(true, ix.config.Get("fallDamageBaseTime", 5) + dmg:GetDamage() * ix.config.Get("fallDamageTimeMultiplier", 0.1))

		-- the ragdoll lands where the player did; that impact is not a second fall
		if (IsValid(target.ixRagdoll)) then
			target.ixRagdoll.ixFallGrace = CurTime() + 1
		end

		return
	end

	if (dmg:IsBulletDamage() and target:LastHitGroup() == HITGROUP_HEAD) then
		target:EmitSound("physics/body/body_medium_break3.wav", 75, math.random(75, 125), 1)
	end
end

function PLUGIN:EntityEmitSound(data)
	local entity = data.Entity

	if (IsValid(entity) and entity:IsPlayer() and entity:Crouching() and string.find(data.SoundName, "player/footsteps", 1, true)) then
		data.Volume = data.Volume * 0.25
		return true
	end
end

function PLUGIN:OnCharacterDisconnect(client, character)
	local remaining = self:GetKnockoutRemaining(client)

	-- saved by the character save that follows this hook
	character:SetData("knockout", remaining)
end

function PLUGIN:ResumeKnockout(client, character)
	local remaining = character:GetData("knockout")

	if (!remaining) then
		return
	end

	character:SetData("knockout", nil)

	if (client:Alive()) then
		self:KnockOut(client, remaining)
	end
end

function PLUGIN:PlayerLoadedCharacter(client, character)
	-- after the spawn that follows loading, which would otherwise undo the ragdoll
	timer.Simple(0, function()
		if (IsValid(client) and client:GetCharacter() == character) then
			self:ResumeKnockout(client, character)
		end
	end)
end
