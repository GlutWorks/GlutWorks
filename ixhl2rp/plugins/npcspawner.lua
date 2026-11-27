
local PLUGIN = PLUGIN

PLUGIN.name = "NPC Spawner"
PLUGIN.author = "Black Tea (NS 1.0), Neon (NS 1.1),Port to helix by B4tr1p"
PLUGIN.description = "Spawns NPCs at admin-placed points away from players."
PLUGIN.spawnpoints = PLUGIN.spawnpoints or {}

ix.config.Add("spawner_enabled", true, "Whether NPC spawners are on or not.", nil, {
	category = "NPC Spawner"
})

ix.config.Add("npc_spawnrate", 90, "How often an npc will be spawned at an npc spawn point.", nil, {
	data = {min = 1, max = 84600},
	category = "NPC Spawner"
})

-- Spawn points placed with an unknown group name use the default group.
PLUGIN.defaultGroup = "headcrab"

PLUGIN.spawngroups = {
	["birds"] = {
		"npc_crow",
		"npc_pigeon",
		"npc_seagull"
	},
	["zombie"] = {
		"npc_zombie"
	},
	["headcrab"] = {
		"npc_headcrab"
	},
	["blackheadcrab"] = {
		"npc_headcrab_black"
	},
	["antlion"] = {
		"npc_antlion"
	}
}

PLUGIN.maxnpcs = 40
PLUGIN.minPlayerDistance = 1000
PLUGIN.spawnedNPCs = PLUGIN.spawnedNPCs or {}

function PLUGIN:GetGroupNames()
	local names = table.GetKeys(self.spawngroups)
	table.sort(names)

	return names
end

if (SERVER) then
	util.AddNetworkString("ixNPCSpawnDisplay")

	local nextSpawn = 0

	--- Picks an NPC class from a spawn group, falling back to the default group.
	function PLUGIN:PickClass(group)
		local classes = self.spawngroups[group] or self.spawngroups[self.defaultGroup]

		return classes[math.random(#classes)]
	end

	function PLUGIN:IsNearPlayer(position)
		local distance = self.minPlayerDistance * self.minPlayerDistance

		for _, v in player.Iterator() do
			if (v:GetMoveType() != MOVETYPE_NOCLIP and v:GetPos():DistToSqr(position) < distance) then
				return true
			end
		end

		return false
	end

	--- Spawns one NPC of the point's group, unless something is in the way. Returns the NPC.
	function PLUGIN:SpawnAt(point)
		local position = point[1]
		local trace = util.TraceHull({
			start = position,
			endpos = position + Vector(0, 0, 1),
			mins = Vector(-16, -16, 0),
			maxs = Vector(16, 16, 16)
		})

		-- don't stack NPCs on each other or spawn them inside something
		if (IsValid(trace.Entity)) then
			return
		end

		local entity = ents.Create(self:PickClass(point[2]))

		if (!IsValid(entity)) then
			return
		end

		entity:SetPos(position + Vector(0, 0, 26))
		entity:Spawn()

		self.spawnedNPCs[#self.spawnedNPCs + 1] = entity

		return entity
	end

	function PLUGIN:Think()
		if (nextSpawn > CurTime()) then
			return
		end

		nextSpawn = CurTime() + ix.config.Get("npc_spawnrate", 90)

		if (!ix.config.Get("spawner_enabled", false)) then
			return
		end

		for i = #self.spawnedNPCs, 1, -1 do
			if (!IsValid(self.spawnedNPCs[i])) then
				table.remove(self.spawnedNPCs, i)
			end
		end

		if (#self.spawnedNPCs >= self.maxnpcs or #self.spawnpoints == 0) then
			return
		end

		local point = self.spawnpoints[math.random(#self.spawnpoints)]

		if (!self:IsNearPlayer(point[1])) then
			self:SpawnAt(point)
		end
	end

	function PLUGIN:LoadData()
		self.spawnpoints = {}

		-- older saves removed points by leaving holes in the list
		for _, v in pairs(self:GetData() or {}) do
			if (istable(v) and isvector(v[1])) then
				self.spawnpoints[#self.spawnpoints + 1] = {v[1], isstring(v[2]) and v[2] or self.defaultGroup}
			end
		end
	end

	function PLUGIN:SaveData()
		self:SetData(self.spawnpoints)
	end
else
	net.Receive("ixNPCSpawnDisplay", function()
		local emitter = ParticleEmitter(LocalPlayer():GetPos())

		for _ = 1, net.ReadUInt(16) do
			local position = net.ReadVector()
			local glow = emitter:Add("sprites/glow04_noz", position)

			if (glow) then
				glow:SetVelocity(Vector(0, 0, 1))
				glow:SetDieTime(10)
				glow:SetStartAlpha(255)
				glow:SetEndAlpha(255)
				glow:SetStartSize(64)
				glow:SetEndSize(64)
				glow:SetColor(255, 50, 50)
				glow:SetAirResistance(300)
			end
		end

		emitter:Finish()
	end)
end

ix.command.Add("NPCSpawnAdd", {
	description = "Adds an NPC spawn point where you are looking.",
	adminOnly = true,
	arguments = ix.type.string,
	OnRun = function(self, client, group)
		group = string.lower(group)

		if (!PLUGIN.spawngroups[group]) then
			return "Unknown NPC group. Groups: " .. table.concat(PLUGIN:GetGroupNames(), ", ")
		end

		local trace = client:GetEyeTraceNoCursor()

		PLUGIN.spawnpoints[#PLUGIN.spawnpoints + 1] = {trace.HitPos + trace.HitNormal * 5, group}
		PLUGIN:SaveData()

		return "You added a " .. group .. " NPC spawner."
	end
})

ix.command.Add("NPCSpawnRemove", {
	description = "Removes NPC spawn points near where you are looking.",
	adminOnly = true,
	arguments = bit.bor(ix.type.number, ix.type.optional),
	OnRun = function(self, client, range)
		local trace = client:GetEyeTraceNoCursor()
		local position = trace.HitPos + trace.HitNormal * 5
		local distance = (range or 128) ^ 2
		local removed = 0

		for i = #PLUGIN.spawnpoints, 1, -1 do
			if (PLUGIN.spawnpoints[i][1]:DistToSqr(position) <= distance) then
				table.remove(PLUGIN.spawnpoints, i)
				removed = removed + 1
			end
		end

		PLUGIN:SaveData()

		return removed .. " NPC spawners have been removed."
	end
})

ix.command.Add("NPCSpawnDisplay", {
	description = "Shows all NPC spawn points for ten seconds.",
	adminOnly = true,
	OnRun = function(self, client)
		net.Start("ixNPCSpawnDisplay")
			net.WriteUInt(#PLUGIN.spawnpoints, 16)

			for _, v in ipairs(PLUGIN.spawnpoints) do
				net.WriteVector(v[1])
			end
		net.Send(client)

		return "Displayed all points for 10 seconds."
	end
})

ix.command.Add("NPCSpawnToggle", {
	description = "Turns the NPC spawners on or off.",
	adminOnly = true,
	OnRun = function(self, client)
		local bEnabled = !ix.config.Get("spawner_enabled", false)

		ix.config.Set("spawner_enabled", bEnabled)

		return bEnabled and "NPC Spawners have been turned on." or "NPC Spawners have been turned off."
	end
})
