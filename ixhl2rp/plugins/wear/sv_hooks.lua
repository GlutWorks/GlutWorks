
local PLUGIN = PLUGIN

-- What wears things. Each rule is a method taking explicit amounts (WearFeet, WearFromDamage, WearFromTime);
-- the timers and hooks at the bottom only feed them.

-- Condition points per point of damage taken, by damage type, before wearDamageScale and durability. With
-- several type bits set the highest factor counts; a hit with no known bit uses GENERIC_FACTOR.
PLUGIN.DAMAGE_FACTORS = {
	[DMG_BURN] = 1,
	[DMG_SLOWBURN] = 1,
	[DMG_ACID] = 1,
	[DMG_PLASMA] = 0.6,
	[DMG_ENERGYBEAM] = 0.6,
	[DMG_SLASH] = 0.5,
	[DMG_BLAST] = 0.4,
	[DMG_BULLET] = 0.3,
	[DMG_BUCKSHOT] = 0.3,
	[DMG_FALL] = 0.25,
	[DMG_SHOCK] = 0.2,
	[DMG_CLUB] = 0.15,
	[DMG_CRUSH] = 0.15,
	[DMG_SONIC] = 0.1,
	[DMG_DROWN] = 0,
	[DMG_DROWNRECOVER] = 0,
	[DMG_POISON] = 0,
	[DMG_NERVEGAS] = 0,
	[DMG_RADIATION] = 0,
	[DMG_PARALYZE] = 0
}
PLUGIN.GENERIC_FACTOR = 0.15

-- Damage types whose LastHitGroup says where the hit landed.
PLUGIN.LOCATED_DAMAGE = bit.bor(DMG_BULLET, DMG_BUCKSHOT, DMG_SLASH, DMG_CLUB)

-- Share of a body hit that goes to the body garment when an outer one is worn over it.
PLUGIN.UNDER_OUTER_SHARE = 0.5
-- Share of a fall that goes to the body garment covering legs (all of it goes to the feet).
PLUGIN.FALL_BODY_SHARE = 0.5
-- Extra condition points an armoured garment loses per armour point it absorbs.
PLUGIN.ARMOR_ABSORB_WEAR = 0.25

-- Footwear: multipliers by the surface under the player (trace MatType), by sprinting and by wading.
PLUGIN.SURFACE_FACTORS = {
	[MAT_CONCRETE] = 1.25,
	[MAT_METAL] = 1.25,
	[MAT_GRATE] = 1.4,
	[MAT_VENT] = 1.25,
	[MAT_DIRT] = 1.1, -- dirt and gravel
	[MAT_SAND] = 1.2,
	[MAT_GLASS] = 1.5,
	[MAT_TILE] = 1,
	[MAT_COMPUTER] = 1,
	[MAT_PLASTIC] = 0.9,
	[MAT_WOOD] = 0.9,
	[MAT_GRASS] = 0.8,
	[MAT_FOLIAGE] = 0.8,
	[MAT_SNOW] = 0.9,
	[MAT_SLOSH] = 1.3,
	[MAT_FLESH] = 1,
	[MAT_ANTLION] = 1,
	[MAT_ALIENFLESH] = 1,
	[MAT_BLOODYFLESH] = 1
}
PLUGIN.SPRINT_FACTOR = 1.5
PLUGIN.WADING_FACTORS = {[1] = 1.5, [2] = 2, [3] = 2}

-- Time worn: extra condition points per hour, for every worn item, by water level (2 waist deep, 3 under).
PLUGIN.WATER_PER_HOUR = {[2] = 6, [3] = 12}

-- One Source unit in metres.
PLUGIN.METRES_PER_UNIT = 0.01905

-- Seconds between position samples, samples per footwear update, seconds between time-worn updates.
PLUGIN.SAMPLE_INTERVAL = 1
PLUGIN.SAMPLES_PER_FLUSH = 10
PLUGIN.TIME_INTERVAL = 60
-- A sample that moved further than this (units per second) was a teleport, not a walk.
PLUGIN.MAX_SAMPLE_SPEED = 1000

--- Whether movement and time wear the player's things now: alive with a character, not in noclip, a vehicle
-- or a ragdoll.
function PLUGIN:CanWearFromMovement(client)
	return IsValid(client) and client:GetCharacter() != nil and client:Alive() and
		client:GetMoveType() != MOVETYPE_NOCLIP and !client:InVehicle() and !IsValid(client.ixRagdoll)
end

--- The highest damage factor among the type bits in damageType.
function PLUGIN:GetDamageFactor(damageType)
	local best
	local bMatched = false

	for flag, factor in pairs(self.DAMAGE_FACTORS) do
		if (flag != 0 and bit.band(damageType, flag) == flag) then
			bMatched = true
			best = math.max(best or 0, factor)
		end
	end

	if (!bMatched) then
		return self.GENERIC_FACTOR
	end

	return best
end

--- The multiplier for footwear wear from circumstances {sprint = bool, material = MAT_*, water = level}.
function PLUGIN:GetDistanceMultiplier(circumstances)
	local multiplier = 1

	if (circumstances.sprint) then
		multiplier = multiplier * self.SPRINT_FACTOR
	end

	if (circumstances.material) then
		multiplier = multiplier * (self.SURFACE_FACTORS[circumstances.material] or 1)
	end

	if (circumstances.water) then
		multiplier = multiplier * (self.WADING_FACTORS[circumstances.water] or 1)
	end

	return multiplier
end

--- The player's circumstances now, for GetDistanceMultiplier.
function PLUGIN:GetCircumstances(client)
	local position = client:GetPos()
	local trace = util.TraceLine({
		start = position + Vector(0, 0, 4),
		endpos = position - Vector(0, 0, 32),
		filter = client,
		mask = MASK_PLAYERSOLID
	})

	return {
		sprint = client:IsSprinting() and client:GetVelocity():Length2D() > client:GetWalkSpeed() + 10,
		material = trace.Hit and trace.MatType or nil,
		water = client:WaterLevel()
	}
end

--- Wears the player's footwear for `distance` units walked. circumstances (optional) scales it; without
-- it the distance counts as ordinary walking. Returns the condition removed.
function PLUGIN:WearFeet(client, distance, circumstances)
	if (!self:CanWearFromMovement(client) or !isnumber(distance) or distance <= 0) then
		return 0
	end

	local item = ix.body and ix.body.GetCoveringGarments(client, "feet")[1] or ix.wear.GetWornPart(client, "feet")

	if (!item) then
		return 0
	end

	local kilometres = distance * self.METRES_PER_UNIT / 1000

	if (circumstances) then
		kilometres = kilometres * self:GetDistanceMultiplier(circumstances)
	end

	local points = kilometres / math.max(ix.config.Get("wearBootsDistance", 100), 0.001) * 100

	return ix.wear.Damage(item, points, "walk", client)
end

--- Wears what covers a hit of `damage` points of damageType (DMG_*) that landed on hitGroup (HITGROUP_*;
-- only trusted for located damage) and of which the armour absorbed `absorbed` points. Returns a table of
-- item ID -> condition removed.
function PLUGIN:WearFromDamage(client, damage, damageType, hitGroup, absorbed)
	local result = {}

	if (!IsValid(client) or !isnumber(damage) or damage <= 0) then
		return result
	end

	damageType = damageType or DMG_GENERIC

	local scale = ix.config.Get("wearDamageScale", 1)
	local points = damage * self:GetDamageFactor(damageType) * scale
	local bFall = bit.band(damageType, DMG_FALL) != 0
	local bLocated = bit.band(damageType, self.LOCATED_DAMAGE) != 0
	local region = (bFall or bLocated) and ix.body.HitGroupToRegion(hitGroup, damageType) or "chest"

	local function WearItem(item, amount)
		if (item and amount > 0) then
			result[item:GetID()] = (result[item:GetID()] or 0) + ix.wear.Damage(item, amount, "damage", client)
		end
	end

	local bHasOuter = false
	local armored

	for _, item in ipairs(ix.body.GetCoveringGarments(client, region)) do
		local share = ix.body.GetRegionWearShare(item, region)

		if (item.wearPart == "outer") then
			bHasOuter = true
			WearItem(item, points * share)
		elseif (item.wearPart == "body") then
			WearItem(item, points * (bHasOuter and self.UNDER_OUTER_SHARE or 1) * share)
		else
			WearItem(item, points * share)
		end

		if (!armored and isfunction(item.GetArmorCapacity)) then
			armored = item
		end
	end

	if (bFall) then
		for _, item in ipairs(ix.body.GetCoveringGarments(client, "legs")) do
			if (item.wearPart == "body") then
				WearItem(item, points * self.FALL_BODY_SHARE * ix.body.GetRegionWearShare(item, "legs"))

				if (!armored and isfunction(item.GetArmorCapacity)) then
					armored = item
				end
			end
		end
	end

	-- the plates took the hit: an armoured garment wears for what it absorbed
	if (!armored) then
		for _, item in ipairs(ix.wear.GetWorn(client)) do
			if (isfunction(item.GetArmorCapacity)) then
				armored = item
				break
			end
		end
	end

	if (armored and isnumber(absorbed) and absorbed > 0) then
		WearItem(armored, absorbed * self.ARMOR_ABSORB_WEAR * scale)
	end

	return result
end

--- Wears everything the player has on for `seconds` worn: wearPerHour, plus WATER_PER_HOUR while waist deep
-- or under water ("water"). Returns the total condition removed.
function PLUGIN:WearFromTime(client, seconds)
	if (!self:CanWearFromMovement(client) or !isnumber(seconds) or seconds <= 0) then
		return 0
	end

	local hours = seconds / 3600
	local perHour = ix.config.Get("wearPerHour", 1)
	local water = self.WATER_PER_HOUR[client:WaterLevel()]
	local total = 0

	for _, item in ipairs(ix.wear.GetWorn(client)) do
		total = total + ix.wear.Damage(item, perHour * hours, "time", client)

		if (water) then
			total = total + ix.wear.Damage(item, water * hours, "water", client)
		end
	end

	return total
end

-- Feeders

--- One position sample: adds the weighted ground distance since the last sample and every
-- SAMPLES_PER_FLUSH samples hands it to WearFeet.
function PLUGIN:SampleMovement(client)
	local position = client:GetPos()
	local last = client.ixWearLastPos

	client.ixWearLastPos = position

	if (!self:CanWearFromMovement(client)) then
		client.ixWearLastPos = nil
		return
	end

	if (last and (client:IsOnGround() or client:WaterLevel() >= 1)) then
		local distance = Vector(position.x - last.x, position.y - last.y, 0):Length()

		if (distance > 0 and distance <= self.MAX_SAMPLE_SPEED * self.SAMPLE_INTERVAL) then
			client.ixWearDistance = (client.ixWearDistance or 0) + distance * self:GetDistanceMultiplier(self:GetCircumstances(client))
		end
	end

	client.ixWearSamples = (client.ixWearSamples or 0) + 1

	if (client.ixWearSamples >= self.SAMPLES_PER_FLUSH) then
		local distance = client.ixWearDistance or 0

		client.ixWearSamples = 0
		client.ixWearDistance = 0

		if (distance > 0) then
			self:WearFeet(client, distance)
		end
	end
end

function PLUGIN:StartTimers()
	timer.Create("ixWearMovement", self.SAMPLE_INTERVAL, 0, function()
		if (!ix.config.Get("wearEnabled", true)) then
			return
		end

		for _, client in player.Iterator() do
			self:SampleMovement(client)
		end
	end)

	timer.Create("ixWearTime", self.TIME_INTERVAL, 0, function()
		if (!ix.config.Get("wearEnabled", true)) then
			return
		end

		for _, client in player.Iterator() do
			self:WearFromTime(client, self.TIME_INTERVAL)
		end
	end)
end

function PLUGIN:InitPostEntity()
	self:StartTimers()
end

function PLUGIN:PlayerSpawn(client)
	client.ixWearLastPos = nil
end

-- Armour before the hit, so PostEntityTakeDamage can tell how much it absorbed.
function PLUGIN:EntityTakeDamage(target, dmg)
	if (target:IsPlayer()) then
		target.ixWearArmor = target:Armor()
	end
end

function PLUGIN:PostEntityTakeDamage(target, dmg, bTook)
	if (!target:IsPlayer()) then
		return
	end

	local before = target.ixWearArmor
	target.ixWearArmor = nil

	if (!bTook or !target:GetCharacter() or dmg:GetDamage() <= 0) then
		return
	end

	local absorbed = before and math.max(before - target:Armor(), 0) or 0

	self:WearFromDamage(target, dmg:GetDamage(), dmg:GetDamageType(), target:LastHitGroup(), absorbed)
end
