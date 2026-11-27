
local PLUGIN = PLUGIN

PLUGIN.name = "Ragdoll State"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Wake-up hooks and the dead-player flag for character ragdolls."

-- Server hooks this provides:
--   OnCharacterWakeup(client, ragdoll): a timed knockdown ran out and the ragdoll is being
--     removed. The ragdoll is still valid; the player gets their position and weapons back
--     when it is deleted, just after this.
--   OnCharacterWakeupWeapon(client, weaponClass): the player got up by any means and was
--     handed back the weapon they were holding (a class name, not an entity).
-- Ragdoll net var: "isDeadPlayer" is true on a ragdoll whose owner is dead.

if (CLIENT) then
	return
end

local playerMeta = FindMetaTable("Player")

-- Unwrapped methods, kept across a Lua refresh of this file. Tables, so they are not cached as hooks.
PLUGIN.base = PLUGIN.base or {}
PLUGIN.wrapped = PLUGIN.wrapped or {}

local function Wrap(name, build)
	if (playerMeta[name] != PLUGIN.wrapped[name]) then
		PLUGIN.base[name] = playerMeta[name]
	end

	PLUGIN.wrapped[name] = build(PLUGIN.base[name])
	playerMeta[name] = PLUGIN.wrapped[name]
end

-- Both hooks rely on how Helix's SetRagdolled works inside (its countdown timer's name, the
-- "fixer" remove callback). Should an update change that, say so once instead of going quiet.
local function WarnOnce(key, message)
	PLUGIN.warned = PLUGIN.warned or {}

	if (!PLUGIN.warned[key]) then
		PLUGIN.warned[key] = true
		ErrorNoHalt("[ragdollstate] " .. message .. "\n")
	end
end

local function MarkDead(client)
	if (IsValid(client.ixRagdoll)) then
		client.ixRagdoll:SetNetVar("isDeadPlayer", true)
	end
end

-- Runs after Helix's own "fixer" remove callback has restored the player.
local function OnRagdollRemoved(client, entity)
	if (!IsValid(client)) then
		return
	end

	-- Helix never clears this, which leaves a NULL entity that is truthy for the rest of the life.
	if (client.ixRagdoll == entity) then
		client.ixRagdoll = nil
	end

	if (!entity.ixIgnoreDelete and entity.ixActiveWeapon and client:HasWeapon(entity.ixActiveWeapon)) then
		hook.Run("OnCharacterWakeupWeapon", client, entity.ixActiveWeapon)
	end
end

Wrap("CreateServerRagdoll", function(base)
	return function(self, ...)
		local entity = base(self, ...)

		if (IsValid(entity) and !self:Alive()) then
			entity:SetNetVar("isDeadPlayer", true)
		end

		return entity
	end
end)

Wrap("SetRagdolled", function(base)
	return function(self, bState, time, getUpGrace)
		if (!bState) then
			return base(self, bState, time, getUpGrace)
		end

		local timerID = "ixUnRagdoll" .. self:SteamID()
		local timerCreate = timer.Create
		local previous = self.ixRagdoll
		local bCountdown = false

		-- Helix removes the ragdoll from inside this countdown when a timed knockdown runs out.
		-- Wrapping the callback lets the wake-up hook fire for that removal and no other.
		timer.Create = function(identifier, delay, repetitions, callback)
			if (identifier == timerID and time) then
				local countdown = callback
				local entity = self.ixRagdoll
				bCountdown = true

				callback = function()
					local bPending = IsValid(entity) and !entity:IsMarkedForDeletion()

					countdown()

					if (bPending and IsValid(self) and self:Alive() and (!IsValid(entity) or entity:IsMarkedForDeletion())) then
						hook.Run("OnCharacterWakeup", self, entity)
					end
				end
			end

			return timerCreate(identifier, delay, repetitions, callback)
		end

		-- timer.Create must be put back even if Helix errors; the traceback goes along with the error
		local bSuccess, result = xpcall(base, debug.traceback, self, bState, time, getUpGrace)
		timer.Create = timerCreate

		if (!bSuccess) then
			error(result, 0)
		end

		local entity = self.ixRagdoll

		-- nothing was made (a dead player is not ragdolled)
		if (!IsValid(entity) or entity == previous) then
			return
		end

		local fixer = entity.OnDieFunctions and entity.OnDieFunctions.fixer

		if (time and !bCountdown) then
			WarnOnce("countdown", "Helix's knockdown countdown (" .. timerID .. ") was not found; OnCharacterWakeup will not fire.")
		end

		if (!fixer) then
			WarnOnce("fixer", "Helix's \"fixer\" ragdoll callback was not found; OnCharacterWakeupWeapon will not fire.")
		end

		-- Replace the callback under the same name so code that removes "fixer" (persistent
		-- corpses) also removes this.
		if (fixer and !entity.ixWakeupHooked) then
			local restore = fixer.Function
			entity.ixWakeupHooked = true

			entity:CallOnRemove("fixer", function(ragdoll, ...)
				ProtectedCall(restore, ragdoll, ...)
				OnRagdollRemoved(self, ragdoll)
			end, unpack(fixer.Args or {}))
		end
	end
end)

function PLUGIN:DoPlayerDeath(client)
	MarkDead(client)
end

function PLUGIN:PlayerDeath(client)
	MarkDead(client)

	-- A body kept on death (ShouldRemoveRagdollOnDeath returned false) stays down. Left running,
	-- Helix's countdown would delete it later and stand the dead player up in its place.
	timer.Remove("ixUnRagdoll" .. client:SteamID())
end
