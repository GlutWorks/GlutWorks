local PLUGIN = PLUGIN

util.AddNetworkString("ixInteractionUse")
util.AddNetworkString("ixInteractionExamine")
util.AddNetworkString("ixInteractionRefused")

-- Seconds between two tap requests from one player.
PLUGIN.useInterval = 0.25

local traceData = {mask = MASK_SOLID}

-- Whether a solid line from `origin` to `target` reaches `entity` with nothing else in the way: it
-- ends on the entity (or something parented to it, or its parent), or reaches the point unblocked.
local function Reaches(client, origin, entity, target)
	traceData.start = origin
	traceData.endpos = target
	traceData.filter = client

	local trace = util.TraceLine(traceData)

	if (!trace.Hit) then
		return true
	end

	local hit = trace.Entity

	return IsValid(hit) and (hit == entity or hit:GetParent() == entity or entity:GetParent() == hit)
end

--- Whether `client` may use `entity` now: alive, with a character, on their feet, untied, not
-- frozen, out of a vehicle, within reach of its surface and with nothing solid in between. The
-- client only asks; this decides. There is no facing check: in third person the eyes do not follow
-- the camera while standing still.
function PLUGIN:CanUseEntity(client, entity)
	if (!IsValid(client) or !IsValid(entity) or entity:IsWorld() or entity == client) then
		return false
	end

	if (!client:Alive() or !client:GetCharacter() or client:IsRestricted() or IsValid(client.ixRagdoll) or
		client:InVehicle() or client:IsFrozen()) then
		return false
	end

	local origin = client:GetShootPos()
	local nearest = entity:NearestPoint(origin)
	-- a little slack over the client's trace, for movement while the request travels
	local reach = self.reach + 16

	if (origin:DistToSqr(nearest) > reach * reach) then
		return false
	end

	-- the nearest point can sit behind an edge while the middle is in plain view, or the other way
	-- round, so either line reaching it is enough
	return Reaches(client, origin, entity, nearest) or Reaches(client, origin, entity, entity:WorldSpaceCenter())
end

--- Runs the entity's Use for `client` as the engine would on a press of Use: the PlayerUse hooks
-- first (so every plugin's rule and side effect applies), then the scripted entity's Use. An
-- interaction that would wait for Use to be held (Helix's item and money pickup) happens at once,
-- since the tap is already over by the time it arrives.
function PLUGIN:UseEntity(client, entity)
	client.ixInteractionInstant = true

	local bSuccess, err = xpcall(function()
		local bAllowed = hook.Run("PlayerUse", client, entity)

		if (bAllowed != false and IsValid(entity) and entity:IsScripted() and isfunction(entity.Use)) then
			entity:Use(client, client, USE_ON, 1)
		end
	end, debug.traceback)

	client.ixInteractionInstant = nil

	if (!bSuccess) then
		ErrorNoHalt(tostring(err) .. "\n")
	end
end

--- The tap request: validated, rate limited, then used. Returns whether it was used.
-- What a pickup changes: the entity, and its item data or amount.
local function Snapshot(entity)
	if (entity:GetClass() == "ix_money") then
		return tostring(entity.GetAmount and entity:GetAmount())
	elseif (entity:GetClass() == "ix_item") then
		return util.TableToJSON(entity:GetNetVar("data", {}))
	end
end

-- Tells the player's client the tap did nothing, so it can sound like it.
function PLUGIN:Refuse(client)
	net.Start("ixInteractionRefused")
	net.Send(client)
end

--- The tap request: validated, rate limited, then used. Returns whether it was used. A refused
-- tap, and a pickup that left the thing exactly as it was (Helix refuses some silently, such as
-- when another entity is on the engine's use line), are answered with ixInteractionRefused.
function PLUGIN:HandleUse(client, entity)
	if ((client.ixNextInteractionUse or 0) > CurTime()) then
		return false
	end

	client.ixNextInteractionUse = CurTime() + self.useInterval

	if (!self:CanUseEntity(client, entity)) then
		if (IsValid(client)) then
			self:Refuse(client)
		end

		return false
	end

	local before = Snapshot(entity)

	self:UseEntity(client, entity)

	if (before and IsValid(entity) and !entity:IsMarkedForDeletion() and Snapshot(entity) == before) then
		self:Refuse(client)
	end

	return true
end

net.Receive("ixInteractionUse", function(length, client)
	PLUGIN:HandleUse(client, net.ReadEntity())
end)

--- /Examine: the description is built on the client, which has the tooltip contributors and the
-- recognition state, so the server only tells it to look.
function PLUGIN:RequestExamine(client)
	net.Start("ixInteractionExamine")
	net.Send(client)
end

-- Helix's pickup of items and money waits for Use to be held for itemPickupTime. A tap has already
-- been released when it reaches the server, so the wait is skipped for one (see UseEntity).
do
	local PLAYER = FindMetaTable("Player")

	ix.interactionPerformInteraction = ix.interactionPerformInteraction or PLAYER.PerformInteraction

	function PLAYER:PerformInteraction(time, entity, callback)
		if (self.ixInteractionInstant) then
			time = 0
		end

		return ix.interactionPerformInteraction(self, time, entity, callback)
	end
end
