
-- Client half of ix.smelting: the smelter's tooltip rows (read by Examine), its entries in the entity menu (the
-- options held Use shows), and how it looks and sounds while it works.

-- Library files load alphabetically, so this one runs before sh_smelting.lua.
ix.smelting = ix.smelting or {}

function ix.smelting.PopulateTooltip(entity, tooltip)
	for _, v in ipairs(ix.smelting.DescribeState(entity)) do
		local row = tooltip:AddRow(v.id)
		row:SetText(v.text)
		row:SizeToContents()
	end
end

-- Collecting first, then what can go in: one entry per smeltable item and per fuel the player carries. The labels
-- sort that way in the options (interaction sorts by label). The server re-checks every choice.
function ix.smelting.AddMenuOptions(entity, client, options)
	local character = client:GetCharacter()
	local inventory = character and character:GetInventory()

	if (!inventory or !ix.stack) then
		return
	end

	if (ix.smelting.HasOutput(entity)) then
		options["Collect output"] = function()
			return {action = "collect"}
		end
	end

	for uniqueID in SortedPairs(ix.smelting.inputs) do
		local count = ix.stack.Count(inventory, uniqueID)

		if (count > 0) then
			options["Smelt " .. ix.smelting.GetItemName(uniqueID) .. " (" ..
				ix.smelting.FormatQuantity(uniqueID, ix.smelting.ToTenths(count)) .. ")"] = function()
				return {action = "smelt", uniqueID = uniqueID}
			end
		end
	end

	for uniqueID in SortedPairs(ix.smelting.fuels) do
		local count = ix.stack.Count(inventory, uniqueID)

		if (count > 0) then
			options["Stoke with " .. ix.smelting.GetItemName(uniqueID) .. " (" ..
				ix.smelting.FormatQuantity(uniqueID, ix.smelting.ToTenths(count)) .. ")"] = function()
				return {action = "fuel", uniqueID = uniqueID}
			end
		end
	end
end

-- How a smelter shows its state by itself, to everyone near it: while smelting a warm flickering glow at the
-- mouth (a sprite, and a dynamic light when near), smoke from the top and a low fire loop; with fuel but
-- nothing smelting a faint ember glow; cold and dark when empty. The cue when a batch finishes is played by the
-- server (sv_smelting.lua). Positions are fractions of the model's bounds, or a station's own
-- `STATION.smelting.effects = {mouth = Vector(x, y, z), chimney = Vector(x, y, z)}` (fractions, 0 to 1, of the
-- bounds along each local axis).
ix.smelting.effects = {
	-- the mouth: low on the front (local +x) face; the chimney: the middle of the top
	mouth = Vector(1.03, 0.5, 0.22),
	chimney = Vector(0.5, 0.5, 1),
	loopSound = "ambient/fire/fire_small_loop2.wav",
	loopLevel = 62,
	loopVolume = 0.6,
	-- how far (from the eyes) each part reaches; nothing is done for a smelter further than the farthest
	smokeDistance = 2500,
	soundDistance = 1200,
	lightDistance = 900,
	glowColor = Color(255, 140, 60),
	lightColor = Color(255, 120, 45),
	smokeMaterials = {"particle/smokesprites_0001", "particle/smokesprites_0002", "particle/smokesprites_0003",
		"particle/smokesprites_0004"},
	smokeInterval = 0.2,
	-- the engine has 32 dynamic lights in all; at most this many smelters, the nearest, take one
	maxLights = 4,
	-- seconds the fire loop takes to fade in and out
	fadeTime = 1.5
}

local effects = ix.smelting.effects
local glowMaterial = Material("sprites/light_glow02_add")
local MODE_COLD, MODE_EMBER, MODE_BURNING = 0, 1, 2
local LIGHT_KEY = 0x6A00

-- smelters with effects running, to stop them when they go out of view (a dormant entity does not think)
ix.smelting.active = ix.smelting.active or {}
-- smelters near enough for a dynamic light this frame
ix.smelting.lit = ix.smelting.lit or {}

function ix.smelting.GetMode(entity)
	if (entity:GetSmeltEnd() > 0) then
		return MODE_BURNING
	elseif (entity:GetSmeltFuel() > 0) then
		return MODE_EMBER
	end

	return MODE_COLD
end

-- A point of the model's bounds, as fractions along its local axes, in world space.
local function Spot(entity, fraction)
	local mins, maxs = entity:OBBMins(), entity:OBBMaxs()
	local size = maxs - mins

	return entity:LocalToWorld(Vector(mins.x + size.x * fraction.x, mins.y + size.y * fraction.y, mins.z + size.z * fraction.z))
end

function ix.smelting.GetEffectSpots(entity)
	local station = entity:GetStationTable()
	local custom = station and station.smelting and station.smelting.effects or {}

	return Spot(entity, custom.mouth or effects.mouth), Spot(entity, custom.chimney or effects.chimney)
end

-- A slow, uneven flicker between about 0.7 and 1, different for each smelter.
function ix.smelting.Flicker(entity)
	local time = RealTime()
	local seed = entity:EntIndex() * 1.7

	return 0.85 + math.sin(time * 7.3 + seed) * 0.07 + math.sin(time * 13.1 + seed * 2) * 0.05 +
		math.sin(time * 29.7 + seed * 3) * 0.03
end

local function StopEffects(entity)
	local fx = entity.ixSmeltFX

	if (!fx) then
		return
	end

	if (fx.sound) then
		fx.sound:Stop()
		fx.sound = nil
	end

	fx.bSounding = false
	fx.silentAt = nil

	if (IsValid(fx.emitter)) then
		fx.emitter:Finish()
	end

	fx.emitter = nil
	ix.smelting.lit[entity] = nil
	ix.smelting.active[entity] = nil
end

ix.smelting.StopEffects = StopEffects

local function EmitSmoke(entity, fx, position)
	if (!IsValid(fx.emitter)) then
		fx.emitter = ParticleEmitter(position)
	end

	local emitter = fx.emitter
	local particle = emitter:Add(effects.smokeMaterials[math.random(#effects.smokeMaterials)], position + VectorRand() * 3)

	if (particle) then
		local grey = math.random(55, 80)

		particle:SetVelocity(Vector(math.Rand(-4, 4), math.Rand(-4, 4), math.Rand(18, 28)))
		particle:SetGravity(Vector(4, 2, 5))
		particle:SetAirResistance(15)
		particle:SetDieTime(math.Rand(5, 7))
		particle:SetStartAlpha(math.random(110, 140))
		particle:SetEndAlpha(0)
		particle:SetStartSize(math.Rand(5, 8) * fx.scale)
		particle:SetEndSize(math.Rand(40, 60) * fx.scale)
		particle:SetRoll(math.Rand(0, 360))
		particle:SetRollDelta(math.Rand(-0.3, 0.3))
		-- as bright as the light where it rises, but never quite gone: the fire below lights it a little
		grey = grey * fx.smokeLight

		particle:SetColor(grey, grey, grey)
	end
end

-- Where the local player sees from: the camera in third person (ix.worldui), else the eyes.
local function ViewOrigin()
	local client = LocalPlayer()

	if (ix.worldui and ix.worldui.GetView) then
		return (ix.worldui.GetView(client))
	end

	return client:EyePos()
end

--- Called from the station's client Think, about ten times a second while it is in view.
function ix.smelting.ThinkEffects(entity)
	local mode = ix.smelting.GetMode(entity)
	local distance = ViewOrigin():Distance(entity:WorldSpaceCenter())
	local fx = entity.ixSmeltFX

	if (mode == MODE_COLD or distance > effects.smokeDistance) then
		if (fx) then
			StopEffects(entity)
		end

		return
	end

	if (!fx) then
		-- a larger smelter has a larger glow and plume
		fx = {nextSmoke = 0}
		entity.ixSmeltFX = fx
	end

	fx.scale = fx.scale or math.Clamp(entity:BoundingRadius() / 70, 1, 2)

	ix.smelting.active[entity] = true
	fx.mode = mode
	fx.distance = distance
	ix.smelting.lit[entity] = distance <= effects.lightDistance and true or nil

	-- One loop per smelter, kept for as long as its effects run: faded down when it stops burning and up again
	-- when it starts, and stopped only once it has been silent for a whole fade, so a fade never stops a loop
	-- that has started again.
	local bSound = mode == MODE_BURNING and distance <= effects.soundDistance

	if (bSound) then
		if (!fx.sound) then
			fx.sound = CreateSound(entity, effects.loopSound)
			fx.sound:SetSoundLevel(effects.loopLevel)
		end

		if (!fx.sound:IsPlaying()) then
			fx.sound:PlayEx(0, 90)
		end

		if (!fx.bSounding) then
			fx.sound:ChangeVolume(effects.loopVolume, effects.fadeTime)
			fx.bSounding = true
		end

		fx.silentAt = nil
	elseif (fx.sound and fx.bSounding) then
		fx.sound:ChangeVolume(0, effects.fadeTime)
		fx.bSounding = false
		fx.silentAt = CurTime() + effects.fadeTime
	elseif (fx.sound and fx.silentAt and CurTime() >= fx.silentAt and fx.sound:IsPlaying()) then
		fx.sound:Stop()
		fx.silentAt = nil
	end

	if (mode == MODE_BURNING and CurTime() >= fx.nextSmoke) then
		fx.nextSmoke = CurTime() + effects.smokeInterval

		local _, chimney = ix.smelting.GetEffectSpots(entity)

		if (!fx.smokeLight or CurTime() >= (fx.nextSmokeLight or 0)) then
			local light = render.GetLightColor(chimney)

			fx.smokeLight = math.Clamp((light.x + light.y + light.z) / 3 * 2.5, 0.45, 1)
			fx.nextSmokeLight = CurTime() + 2
		end

		EmitSmoke(entity, fx, chimney)
	end
end

--- The glow at the mouth, from the station's DrawTranslucent (so only while it is drawn).
function ix.smelting.DrawGlow(entity)
	local fx = entity.ixSmeltFX

	if (!fx or !ix.smelting.active[entity]) then
		return
	end

	local mouth = ix.smelting.GetEffectSpots(entity)
	local flicker = ix.smelting.Flicker(entity)
	local color = effects.glowColor
	local bBurning = fx.mode == MODE_BURNING
	local size = (bBurning and 64 or 22) * flicker * fx.scale
	local alpha = math.min((bBurning and 255 or 80) * flicker, 255)

	render.SetMaterial(glowMaterial)
	render.DrawSprite(mouth, size, size, Color(color.r, color.g, color.b, alpha))

	if (bBurning) then
		render.DrawSprite(mouth, size * 0.45, size * 0.45, Color(255, 220, 160, alpha * 0.8))
	end
end

-- Dynamic lights are few and must be renewed each frame, so only the nearest few smelters get one. Which ones is
-- worked out a few times a second.
local lightList = {}
local nextLightList = 0

local function ByDistance(a, b)
	return a.ixSmeltFX.distance < b.ixSmeltFX.distance
end

hook.Add("Think", "ixSmeltingLights", function()
	if (!next(ix.smelting.lit)) then
		return
	end

	if (RealTime() >= nextLightList) then
		nextLightList = RealTime() + 0.25
		table.Empty(lightList)

		for entity in pairs(ix.smelting.lit) do
			if (!IsValid(entity) or entity:IsDormant() or !entity.ixSmeltFX or !entity.ixSmeltFX.distance) then
				ix.smelting.lit[entity] = nil
			else
				lightList[#lightList + 1] = entity
			end
		end

		table.sort(lightList, ByDistance)

		for i = #lightList, effects.maxLights + 1, -1 do
			lightList[i] = nil
		end
	end

	for _, entity in ipairs(lightList) do
		if (!IsValid(entity) or !ix.smelting.lit[entity] or !entity.ixSmeltFX) then
			continue
		end

		-- keyed apart from the entity index, which the engine's own lights for the entity may use
		local light = DynamicLight(LIGHT_KEY + entity:EntIndex())

		if (light) then
			local mouth = ix.smelting.GetEffectSpots(entity)
			local flicker = ix.smelting.Flicker(entity)
			local bBurning = entity.ixSmeltFX.mode == MODE_BURNING
			local color = effects.lightColor

			light.pos = mouth + entity:GetForward() * 10
			light.r, light.g, light.b = color.r, color.g, color.b
			light.brightness = (bBurning and 2.2 or 0.6) * flicker
			light.size = (bBurning and 220 or 80) * flicker * entity.ixSmeltFX.scale
			light.decay = 1000
			light.dietime = CurTime() + 0.1
		end
	end
end)

-- A smelter that went out of view (dormant) or away no longer thinks, so its sound and light are stopped here.
timer.Create("ixSmeltingEffects", 1, 0, function()
	for entity in pairs(ix.smelting.active) do
		if (!IsValid(entity)) then
			ix.smelting.active[entity] = nil
			ix.smelting.lit[entity] = nil
		elseif (entity:IsDormant()) then
			StopEffects(entity)
		end
	end
end)
