
local PLUGIN = PLUGIN

util.AddNetworkString("ixLogoffSearch")

-- Knocks a body takes as it settles, or from a prop nudged against it, don't hurt it: crush damage of this much
-- or less, and any crush damage within this long of the last.
PLUGIN.crushIgnored = 10
PLUGIN.crushGrace = 0.5

-- Bodies left asleep, by character id.
PLUGIN.sleepers = PLUGIN.sleepers or {}

ix.log.AddType("logoffAsleep", function(client, name, how)
	return string.format("%s left %s asleep %s.", client:SteamName(), name, how)
end)

ix.log.AddType("logoffKilledAsleep", function(client, name)
	return string.format("%s killed %s in their sleep.", client:SteamName(), name)
end)

-- ------------------------------------------------------------------ who sleeps

--- When a player last hurt another player, or was hurt by one (CurTime), or nil.
function ix.logoff.GetLastFight(client)
	return client.ixLogoffFight
end

--- Whether a player's body has to stay the whole time they're away, wherever they leave from: they're wanted
-- (the ShouldSleepWhileAway hook) or have just been in a fight.
function ix.logoff.MustStay(client)
	local character = client:GetCharacter()

	if (character and hook.Run("ShouldSleepWhileAway", client, character) == true) then
		return true
	end

	local fight = ix.logoff.GetLastFight(client)

	return fight != nil and CurTime() - fight < ix.config.Get("logoffFightMemory", 300)
end

--- Whether a player may leave cleanly from where they are now (leaving no body, or switching characters):
-- somewhere safe, and nothing holding them.
function ix.logoff.MayLeaveCleanly(client)
	return ix.logoff.IsSafe(client) and !ix.logoff.MustStay(client)
end

--- What leaving now would do with a player's body: nil when they'd leave cleanly, a number of seconds it would
-- sleep where they stand, or true when it would sleep the whole time they're away (somewhere dangerous, or held).
function ix.logoff.GetSleep(client)
	if (!client:GetCharacter() or !client:Alive() or ix.logoff.MayLeaveCleanly(client)) then
		return
	end

	if (ix.logoff.MustStay(client) or ix.logoff.GetSafety(client) == ix.logoff.DANGEROUS) then
		return true
	end

	local time = ix.config.Get("logoffSleepTime", 300)

	return time > 0 and time or nil
end

-- Someone hurt by another player, and whoever hurt them (a sleeping body too), have been in a fight.
function PLUGIN:PostEntityTakeDamage(target, damage, bTook)
	local attacker = damage:GetAttacker()

	if (!bTook or !IsValid(attacker) or !attacker:IsPlayer() or attacker == target) then
		return
	end

	if (target:IsPlayer()) then
		target.ixLogoffFight = CurTime()
		attacker.ixLogoffFight = CurTime()
	elseif (target.ixSleeper) then
		attacker.ixLogoffFight = CurTime()
	end
end

-- ------------------------------------------------------------------ falling asleep

-- Copies one ragdoll's pose onto another of the same model.
local function CopyPose(from, to)
	for i = 0, to:GetPhysicsObjectCount() - 1 do
		local source, target = from:GetPhysicsObjectNum(i), to:GetPhysicsObjectNum(i)

		if (IsValid(source) and IsValid(target)) then
			target:SetPos(source:GetPos())
			target:SetAngles(source:GetAngles())
			target:SetVelocity(source:GetVelocity())
		end
	end
end

--- Leaves a leaving player's body asleep where they are, for `sleep` seconds or (true) until they come back.
-- A knocked-out player's body is copied where it lies; Helix removes theirs as they go.
function PLUGIN:LeaveAsleep(client, sleep)
	local character = client:GetCharacter()
	local knocked = client.ixRagdoll
	local body = client:CreateServerRagdoll(true)

	if (IsValid(knocked)) then
		body:SetPos(knocked:GetPos())
		CopyPose(knocked, body)
	elseif (client.ixObsData) then
		-- staff watching in noclip leave their body where they were before, the place Spawn Saver keeps
		local offset = client.ixObsData[1] - client:GetPos()

		body:SetPos(body:GetPos() + offset)

		for i = 0, body:GetPhysicsObjectCount() - 1 do
			local physics = body:GetPhysicsObjectNum(i)

			if (IsValid(physics)) then
				physics:SetPos(physics:GetPos() + offset)
				physics:SetVelocity(vector_origin)
			end
		end
	end

	local id = character:GetID()

	body.ixSleeper = {
		character = character,
		id = id,
		name = character:GetName(),
		health = client:Health(),
		bSearched = false
	}
	body.ixLogoffCrush = CurTime() + 1

	-- what anyone looking at it sees: the first line of its description
	local description = character:GetDescription() or ""
	body:SetNetVar("asleep", description:match("^[^\r\n]*"):sub(1, 128))

	self.sleepers[id] = body

	body:CallOnRemove("ixLogoffSleeper", function(entity)
		if (PLUGIN.sleepers[id] == entity) then
			PLUGIN.sleepers[id] = nil
		end

		timer.Remove("ixLogoffSleep" .. id)
		PLUGIN:CloseSearch(entity)
	end)

	if (isnumber(sleep)) then
		timer.Create("ixLogoffSleep" .. id, sleep, 1, function()
			if (IsValid(body) and !body.ixSleeper.bDead) then
				body:Remove()
			end
		end)
	end

	ix.log.Add(client, "logoffAsleep", character:GetName(),
		isnumber(sleep) and string.format("for %d seconds", sleep) or "until they come back")


	return body
end

-- Helix's own handler runs after the plugins', so the player is still all there.
function PLUGIN:PlayerDisconnected(client)
	local sleep = ix.logoff.GetSleep(client)

	if (sleep) then
		self:LeaveAsleep(client, sleep)
	end
end

--- A character's sleeping body, if they left one that's still there (and alive).
function ix.logoff.GetSleeper(character)
	local body = character and PLUGIN.sleepers[character:GetID()]

	return IsValid(body) and !body.ixSleeper.bDead and body or nil
end

-- ------------------------------------------------------------------ searched, hurt and killed

--- Closes the search of a sleeping body for whoever has it open.
function PLUGIN:CloseSearch(body)
	local inventory = body.ixSleeper and body.ixSleeper.character:GetInventory()

	if (inventory and inventory.storageInfo and inventory.storageInfo.entity == body) then
		ix.storage.Close(inventory)
	end
end

--- Opens a sleeping body's pockets to `client`, through a search as long as a corpse's.
function PLUGIN:Search(client, body)
	local sleeper = body.ixSleeper
	local inventory = sleeper and !sleeper.bDead and sleeper.character:GetInventory()

	if (!inventory) then
		return false
	end

	if (ix.storage.InUse(inventory)) then
		client:NotifyLocalized("storageInUse")
		return false
	end

	sleeper.bSearched = true

	ix.storage.Open(client, inventory, {
		entity = body,
		name = "Someone asleep",
		searchText = "Going through their pockets...",
		searchTime = ix.config.Get("corpseSearchTime", 1)
	})

	return true
end

net.Receive("ixLogoffSearch", function(length, client)
	local body = net.ReadEntity()

	if ((client.ixNextLogoffSearch or 0) > CurTime()) then
		return
	end

	client.ixNextLogoffSearch = CurTime() + 1

	if (!IsValid(body) or !body.ixSleeper) then
		return
	end

	local interaction = ix.plugin.list.interaction

	if (interaction and !interaction:CanUseEntity(client, body)) then
		return
	end

	PLUGIN:Search(client, body)
end)

-- A sleeping body has the health its player left with; what hurts it takes from that, and at none it dies.
function PLUGIN:EntityTakeDamage(entity, damage)
	local sleeper = entity.ixSleeper

	if (!sleeper or sleeper.bDead) then
		return
	end

	if (damage:IsDamageType(DMG_CRUSH)) then
		if ((entity.ixLogoffCrush or 0) > CurTime() or damage:GetDamage() <= self.crushIgnored) then
			return
		end

		entity.ixLogoffCrush = CurTime() + self.crushGrace
	end

	sleeper.health = sleeper.health - damage:GetDamage()

	if (sleeper.health <= 0) then
		self:KillSleeper(entity, damage:GetAttacker())
	end
end

--- A sleeping body dies: it's a corpse from now on, and its character comes back dead.
function PLUGIN:KillSleeper(body, attacker)
	local sleeper = body.ixSleeper

	sleeper.bDead = true
	self.sleepers[sleeper.id] = nil
	timer.Remove("ixLogoffSleep" .. sleeper.id)
	self:CloseSearch(body)

	body:SetNetVar("asleep", nil)
	body:SetNetVar("isDeadPlayer", true)

	-- saved now: the server may well restart before they come back
	sleeper.character:SetData("diedAsleep", true)
	sleeper.character:Save()

	if (IsValid(attacker) and attacker:IsPlayer()) then
		ix.log.Add(attacker, "logoffKilledAsleep", sleeper.name)
	end

	-- it lies and decays like any other corpse
	local corpses = ix.plugin.list.persistent_corpses

	if (corpses and corpses.KeepCorpse and ix.config.Get("persistentCorpses", true)) then
		corpses:KeepCorpse(body)
	else
		SafeRemoveEntityDelayed(body, 10)
	end

end

-- ------------------------------------------------------------------ waking

-- The floor under a body, a little up, facing the way it lies.
local function WakeSpot(body)
	local trace = util.TraceLine({
		start = body:GetPos() + Vector(0, 0, 16),
		endpos = body:GetPos() - Vector(0, 0, 64),
		filter = body,
		mask = MASK_PLAYERSOLID
	})

	return trace.HitPos + Vector(0, 0, 2), Angle(0, body:GetAngles().y, 0)
end

-- Coming back to a body still asleep: it wakes where it lies (wherever it's been dragged), as hurt as it is.
-- The body goes as they load; they're put where it lay once Spawn Saver has put them where they stood. (Its
-- saved place can't simply be changed here: changing a character queues a save for the end of the tick, after
-- the spawn, and every save records where the player stands.)
function PLUGIN:PrePlayerLoadedCharacter(client, character, lastCharacter)
	local body = ix.logoff.GetSleeper(character)

	if (!body) then
		return
	end

	local pos, angles = WakeSpot(body)

	client.ixLogoffWaking = {
		pos = pos,
		angles = angles,
		health = body.ixSleeper.health,
		bSearched = body.ixSleeper.bSearched
	}

	body:Remove()
end

function PLUGIN:PlayerLoadedCharacter(client, character, lastCharacter)
	local waking = client.ixLogoffWaking
	local bDied = character:GetData("diedAsleep")

	client.ixLogoffWaking = nil

	if (!waking and !bDied) then
		return
	end

	-- after Spawn Saver's own move, a tick after loading
	timer.Simple(0.1, function()
		if (!IsValid(client) or client:GetCharacter() != character) then
			return
		end

		if (bDied) then
			self:DieAsleep(client, character)
		else
			self:Wake(client, waking)
		end
	end)
end

-- Whether a player standing at `pos` would be stuck in something they can't walk through. (Helix's IsStuck
-- counts anything solid, such as a corpse lying there, which players walk through.)
local function Blocked(client, pos)
	return util.TraceHull({
		start = pos,
		endpos = pos,
		mins = client:OBBMins(),
		maxs = client:OBBMaxs(),
		filter = client,
		mask = MASK_PLAYERSOLID,
		collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT
	}).StartSolid
end

--- Someone back to their sleeping body wakes where it lay, as hurt as it was, and hears if it was searched.
-- `waking` is what PrePlayerLoadedCharacter kept of the body: pos, angles, health, bSearched.
function PLUGIN:Wake(client, waking)
	client:SetPos(waking.pos)

	-- (the free spots are looked for around where they now stand)
	if (Blocked(client, waking.pos)) then
		for _, spot in ipairs(ix.util.FindEmptySpace(client, {client})) do
			if (!Blocked(client, spot)) then
				client:SetPos(spot)
				break
			end
		end
	end

	client:SetEyeAngles(waking.angles)
	client:SetHealth(math.Clamp(math.ceil(waking.health), 1, client:GetMaxHealth()))

	if (waking.bSearched) then
		client:Notify("You wake. Someone has been through your pockets.")
	end
end

--- A character killed in their sleep, back: they die now, through the death everyone has (its screen, the
-- respawn and what every plugin does on a death), but leave no second body; theirs already lay where they slept.
function PLUGIN:DieAsleep(client, character)
	character:SetData("diedAsleep", nil)

	client.ixLogoffDiedAsleep = true
	client:Kill()
	client.ixLogoffDiedAsleep = nil

	client:Notify("You were killed in your sleep.")
end

function PLUGIN:ShouldSpawnPlayerCorpse(client)
	if (IsValid(client) and client.ixLogoffDiedAsleep) then
		return false
	end
end

function PLUGIN:ShouldSpawnClientRagdoll(client)
	if (client.ixLogoffDiedAsleep) then
		return false
	end
end
