
local PLUGIN = PLUGIN

PLUGIN.name = "Stealth Ability"
PLUGIN.author = "Shooter#5269"
PLUGIN.description = "Hold walk (ALT) while using a door to open it slowly and silently."

ix.config.Add("StealthySpeed", 10, "How fast the door opens when a player attempts to stealthy open it.", nil, {
	data = {min = 1, max = 100},
	category = PLUGIN.name
})

PLUGIN.doors = {
	["func_door_rotating"] = true,
	["prop_door_rotating"] = true
}

if (!SERVER) then return end

function PLUGIN:IsStealthy(door)
	return door:GetKeyValues()["speed"] == ix.config.Get("StealthySpeed")
end

--- Opens `door` slowly when `client` holds walk, and restores its normal speed otherwise.
-- Double doors share a name, so the partner within reach gets the same treatment.
function PLUGIN:PlayerUse(client, entity)
	if (!IsValid(client) or !IsValid(entity) or !self.doors[entity:GetClass()] or entity:IsLocked()) then
		return
	end

	local position = entity:GetPos()
	local bStealthy = client:KeyDown(IN_WALK)

	-- openawayfrom takes a targetname
	local name = "ixStealth" .. client:EntIndex()
	client:SetName(name)

	local doorName = entity:GetName()

	for _, v in ipairs(ents.FindInSphere(position, 100)) do
		local bPartner = v == entity or (doorName != "" and v:GetName() == doorName)

		if (!bPartner or !self.doors[v:GetClass()]) then
			continue
		end

		-- PlayerUse repeats while use is held; the flag keeps it from re-firing every tick.
		if (!v:GetNWBool("RunOnce")) then
			v:SetNWBool("RunOnce", true)
			continue
		end

		v:SetNWBool("RunOnce", false)
		v:SetNWEntity("ControlingPlayer", client)

		local defaultSpeed = v:GetNWInt("DefaultSpeed", 100)

		if (bStealthy and v:GetKeyValues()["speed"] == defaultSpeed) then
			v:Fire("setspeed", ix.config.Get("StealthySpeed"))
			v:Fire("openawayfrom", name)
		elseif (!bStealthy and self:IsStealthy(v)) then
			v:Fire("setspeed", defaultSpeed)
			v:Fire("openawayfrom", name)
		end
	end
end

function PLUGIN:EntityKeyValue(entity, key, value)
	if (self.doors[entity:GetClass()] and key == "speed") then
		entity:SetNWInt("DefaultSpeed", tonumber(value))
	end
end

function PLUGIN:EntityEmitSound(data)
	local door = data.Entity

	if (!IsValid(door) or !self.doors[door:GetClass()]) then
		return
	end

	local client = door:GetNWEntity("ControlingPlayer")

	if (IsValid(client) and (self:IsStealthy(door) or client:KeyDown(IN_WALK))) then
		return false
	end
end
