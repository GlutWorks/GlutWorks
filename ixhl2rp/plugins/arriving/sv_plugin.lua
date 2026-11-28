local PLUGIN = PLUGIN

util.AddNetworkString("ixArrivingReady")
util.AddNetworkString("ixArrivingMirror")

local states = PLUGIN.states
local layout = PLUGIN.layout

-- The fade stepping off the train (seconds).
PLUGIN.fadeTime = 0.6
-- The desk: how far in front of the clerk applicants stand, how near that they're asked, how far they go
-- before they're no longer at it, and how far the clerk is heard (units).
PLUGIN.deskFront = 52
PLUGIN.askedWithin = 110
PLUGIN.leftBeyond = 220
PLUGIN.clerkHeard = 420

-- Where things go on maps we know, when an admin hasn't placed them (`/ArrivingSet...`): the train's back
-- corner and the way it runs, the platform (feet, facing), the clerk (feet, facing the applicants).
PLUGIN.places = {
	-- the paved square by the spawn points, the clerk's back to the building
	gm_construct = {
		platform = {origin = Vector(700, 0, -143), yaw = 0},
		desk = {origin = Vector(990, 0, -143), yaw = 180}
	}
}

-- ------------------------------------------------------------------ places

-- A place this map has for `key` (train, platform or desk): one an admin set, the map's default, or nil.
function PLUGIN:GetPlace(key)
	local saved = self:GetData()[key]

	if (istable(saved) and isvector(saved.origin)) then
		return {origin = saved.origin, yaw = saved.yaw or 0}
	end

	local known = self.places[game.GetMap():lower()]

	return known and known[key] and {origin = Vector(known[key].origin), yaw = known[key].yaw} or nil
end

function PLUGIN:SetPlace(key, origin, yaw)
	local data = self:GetData()

	data[key] = {origin = origin, yaw = math.Round(yaw)}
	self:SetData(data)
end

-- The carriage's box with the night around it, in its own measures.
local function TrainBounds()
	local margin = layout.backdrop + layout.thick + 8

	return Vector(-margin, -margin, -margin), Vector(layout.Long() + margin, layout.cabinTo + margin, layout.high + margin)
end

-- Whether the whole carriage fits clear of the world at a place.
function PLUGIN:TrainFits(place)
	local mins, maxs = TrainBounds()
	local corners = {}

	for _, x in ipairs({mins.x, maxs.x}) do
		for _, y in ipairs({mins.y, maxs.y}) do
			for _, z in ipairs({mins.z, maxs.z}) do
				corners[#corners + 1] = self:ToWorld(place, Vector(x, y, z))
			end
		end
	end

	local low, high = Vector(corners[1]), Vector(corners[1])

	for _, corner in ipairs(corners) do
		low.x, low.y, low.z = math.min(low.x, corner.x), math.min(low.y, corner.y), math.min(low.z, corner.z)
		high.x, high.y, high.z = math.max(high.x, corner.x), math.max(high.y, corner.y), math.max(high.z, corner.z)
	end

	local middle = (low + high) / 2
	local trace = util.TraceHull({
		start = middle, endpos = middle, mins = low - middle, maxs = high - middle, mask = MASK_SOLID_BRUSHONLY
	})

	return !trace.StartSolid and !trace.Hit and util.IsInWorld(low) and util.IsInWorld(high)
end

-- Where the train goes: an admin's or the map's place, else open sky over a spawn point, high enough that
-- nobody reaches it and low enough to stay under the sky.
function PLUGIN:FindTrainPlace()
	local place = self:GetPlace("train")

	if (place) then
		return place
	end

	local spawns = ents.FindByClass("info_player_start")

	for _, class in ipairs({"info_player_combine", "info_player_rebel", "info_player_deathmatch"}) do
		table.Add(spawns, ents.FindByClass(class))
	end

	local mins, maxs = TrainBounds()

	for _, spawn in ipairs(spawns) do
		local from = spawn:GetPos() + Vector(0, 0, 32)
		local up = util.TraceLine({start = from, endpos = from + Vector(0, 0, 32768), mask = MASK_SOLID_BRUSHONLY})

		if (up.HitSky and up.HitPos.z - from.z > maxs.z - mins.z + 1200) then
			local candidate = {
				origin = Vector(from.x - layout.Long() / 2, from.y - layout.cabinTo / 2, up.HitPos.z - maxs.z - 160),
				yaw = 0
			}

			if (self:TrainFits(candidate)) then
				return candidate
			end
		end
	end
end

-- The platform: an admin's or the map's place, else the first spawn point.
function PLUGIN:GetPlatform()
	local place = self:GetPlace("platform")

	if (place) then
		return place
	end

	local spawn = ents.FindByClass("info_player_start")[1]

	return spawn and {origin = spawn:GetPos(), yaw = spawn:GetAngles().y} or {origin = vector_origin, yaw = 0}
end

-- ------------------------------------------------------------------ the set

-- Removes the set and the desk, if they're up.
function PLUGIN:TearDown()
	for _, entity in ipairs(self.train and self.train.entities or {}) do
		if (IsValid(entity)) then
			entity:Remove()
		end
	end

	for _, entity in ipairs(self.desk or {}) do
		if (IsValid(entity)) then
			entity:Remove()
		end
	end

	self.train, self.desk = nil, nil
	SetNetVar("arrivingTrainPlace", nil)
end

local function SpawnPiece(train, piece)
	local entity = ents.Create("ix_arriving_piece")

	entity:SetPos(train.place.origin)
	entity:SetAngles(Angle(0, train.place.yaw, 0))
	entity:SetKind(piece.kind)
	entity:SetBoxMins(piece.mins)
	entity:SetBoxMaxs(piece.maxs)

	if (piece.model) then
		entity:SetPieceModel(piece.model)
	end

	entity:Spawn()
	train.entities[#train.entities + 1] = entity

	return entity
end

-- Builds the train set where it goes, and the desk, and hides the set from everyone not aboard.
function PLUGIN:Build()
	self:TearDown()

	local place = self:FindTrainPlace()

	if (place) then
		local train = {place = place, entities = {}, doors = {}, mirrors = {}, occupants = {}}

		for _, piece in ipairs(layout.Pieces()) do
			local entity = SpawnPiece(train, piece)

			if (piece.kind == "door") then
				entity.slide = piece.slide
				train.doors[piece.door or piece.cabin] = entity
			end
		end

		for _, prop in ipairs(layout.Props()) do
			local pos, yaw = self:ToWorld(place, prop.pos, prop.yaw)
			local entity = ents.Create("ix_arriving_piece")

			entity:SetPos(pos)
			entity:SetAngles(Angle(0, yaw, 0))
			entity:SetKind("prop")
			entity:SetPieceModel(prop.model)
			entity:Spawn()
			train.entities[#train.entities + 1] = entity
		end

		for i = 1, layout.cabins do
			local pos, yaw = self:ToWorld(place, layout.Mirror(i))
			local mirror = ents.Create("ix_arriving_mirror")

			mirror:SetPos(pos)
			mirror:SetAngles(Angle(0, yaw, 0))
			mirror:Spawn()
			mirror.cabin = i
			train.mirrors[i] = mirror
			train.entities[#train.entities + 1] = mirror
		end

		self.train = train
		SetNetVar("arrivingTrainPlace", {origin = place.origin, yaw = place.yaw})
		self:SetTrainState("riding")
		ix.log.AddRaw(string.format("Arriving: the train is at %s, turned %d.", tostring(place.origin), place.yaw))
	else
		ix.log.AddRaw("Arriving: no open sky for the train on this map; newcomers arrive on the platform.")
	end

	local desk = self:GetPlace("desk")

	if (desk) then
		local clerk = ents.Create("ix_intake_clerk")

		clerk:SetPos(desk.origin)
		clerk:SetAngles(Angle(0, desk.yaw, 0))
		clerk:Spawn()

		local counter = ents.Create("prop_dynamic")
		local forward = Angle(0, desk.yaw, 0):Forward()

		counter:SetModel("models/props_combine/breendesk.mdl")
		counter:SetPos(desk.origin + forward * 30)
		counter:SetAngles(Angle(0, desk.yaw + 180, 0))
		counter:SetKeyValue("solid", "6")
		counter:Spawn()

		self.desk = {clerk, counter}
	end

	self.bBuilt = true
	self:UpdateTransmit()
end

function PLUGIN:InitPostEntity()
	self:Build()
end

function PLUGIN:PostCleanupMap()
	self:Build()
end

-- Only those aboard are sent the set, and those aboard are sent only to each other.
function PLUGIN:UpdateTransmit()
	local aboard, ashore = {}, {}

	for _, client in player.Iterator() do
		if (self:IsAboard(client)) then
			aboard[#aboard + 1] = client
		else
			ashore[#ashore + 1] = client
		end
	end

	for _, entity in ipairs(self.train and self.train.entities or {}) do
		if (IsValid(entity)) then
			for _, client in ipairs(aboard) do
				entity:SetPreventTransmit(client, false)
			end

			for _, client in ipairs(ashore) do
				entity:SetPreventTransmit(client, true)
			end
		end
	end

	for _, passenger in ipairs(aboard) do
		for _, client in ipairs(aboard) do
			if (client != passenger) then
				passenger:SetPreventTransmit(client, false)
			end
		end

		for _, client in ipairs(ashore) do
			passenger:SetPreventTransmit(client, true)
		end
	end

	for _, client in ipairs(ashore) do
		for _, other in ipairs(ashore) do
			if (other != client) then
				client:SetPreventTransmit(other, false)
			end
		end
	end
end

-- Sets where someone is in arriving, and who sees what.
function PLUGIN:SetState(client, character, state)
	character:SetData("arrival", state)
	self:UpdateTransmit()
end

-- ------------------------------------------------------------------ joining

net.Receive("ixArrivingReady", function(length, client)
	if (!client.ixLoaded or client:GetCharacter() or client.ixArriving) then
		return
	end

	if ((client.ixNextArrive or 0) > RealTime()) then
		return
	end

	client.ixNextArrive = RealTime() + 2
	client.ixArriving = true

	-- Helix kills a joining player a second after they join (they have no character yet), and the set is
	-- built as the map starts: arrive after both.
	local wait = math.max(0, (client.ixJoinTime or 0) + 1.25 - RealTime())

	local function Go()
		if (!IsValid(client)) then
			return
		end

		if (!PLUGIN.bBuilt) then
			timer.Simple(0.5, Go)
			return
		end

		client.ixArriving = nil

		if (!client:GetCharacter()) then
			PLUGIN:Arrive(client)
		end
	end

	timer.Simple(wait, Go)
end)

-- Whether a character may be loaded for its player now, as Helix's own checks (and the plugins') say.
function PLUGIN:MayUse(client, character)
	client.ixArrivingLoading = character:GetID()
	local status = hook.Run("CanPlayerUseCharacter", client, character)
	client.ixArrivingLoading = nil

	return status != false
end

-- Brings a player into the city: their most recently played character that may be used, else a new one.
function PLUGIN:Arrive(client)
	local best

	for _, id in ipairs(client.ixCharList or {}) do
		local character = ix.char.loaded[id]

		if (character and character:GetPlayer() == client and self:MayUse(client, character)
			and (!best or (character:GetLastJoinTime() or 0) > (best:GetLastJoinTime() or 0))) then
			best = character
		end
	end

	if (best) then
		self:Load(client, best)
	else
		self:MakeNewcomer(client)
	end
end

-- Loads a character for its player, as Helix's ixCharacterChoose does.
function PLUGIN:Load(client, character)
	local current = client:GetCharacter()

	if (current) then
		current:Save()

		for _, inventory in ipairs(current:GetInventory(true)) do
			if (istable(inventory)) then
				inventory:RemoveReceiver(client)
			end
		end
	end

	client.ixArrivingLoading = character:GetID()
	hook.Run("PrePlayerLoadedCharacter", client, character, current)
	character:Setup()
	client:Spawn()
	hook.Run("PlayerLoadedCharacter", client, character, current)
	client.ixArrivingLoading = nil
end

-- A nameless citizen in the blue suit, made for a player with no character to come back as, who wakes on
-- the train.
function PLUGIN:MakeNewcomer(client)
	local faction = ix.faction.indices[FACTION_CITIZEN]
	local bodies = self:GetBodies()

	if (!faction or #bodies == 0) then
		ErrorNoHalt("[Arriving] no citizen faction or bodies to make a newcomer with\n")
		return
	end

	local model = bodies[math.random(#bodies)]

	client.ixArriving = true

	ix.char.Create({
		name = "",
		description = self:Seen(model, self.middleStature, self.middleAge),
		model = model,
		faction = faction.uniqueID,
		steamID = client:SteamID64(),
		data = {arrival = states.cabin, stature = self.middleStature, age = self.middleAge}
	}, function(id)
		if (!IsValid(client)) then
			return
		end

		client.ixArriving = nil

		local character = ix.char.loaded[id]

		if (!character) then
			return
		end

		character:Sync(client)
		MsgN("Arriving: made newcomer '" .. id .. "' for " .. client:SteamName() .. ".")
		hook.Run("OnCharacterCreated", client, character)
		self:Load(client, character)
	end)
end

-- Characters are made by arriving and chosen by the server, never by a client's message.
function PLUGIN:CanPlayerCreateCharacter(client, payload)
	return false, "unknownError"
end

function PLUGIN:CanPlayerUseCharacter(client, character)
	if (client.ixArrivingLoading != character:GetID()) then
		return false, "@unknownError"
	end
end

-- Someone on the train is put there whenever they load or spawn, not where they last saved.
function PLUGIN:PrePlayerLoadedCharacter(client, character, current)
	local state = self:GetState(character)

	if (state == states.cabin or state == states.aboard) then
		character:SetData("pos", nil)
	end

	if (current and self.train) then
		self:FreeCabin(client)
	end
end

function PLUGIN:PostPlayerLoadout(client)
	local character = client:GetCharacter()

	if (!character) then
		return
	end

	self:ApplyScale(client, character)

	local state = self:GetState(character)

	if (state == states.cabin or state == states.aboard) then
		self:PutAboard(client, character)
	end

	self:UpdateTransmit()
end

function PLUGIN:PlayerLoadedCharacter(client, character)
	self:UpdateTransmit()
end

function PLUGIN:PlayerInitialSpawn(client)
	timer.Simple(0, function()
		if (IsValid(client)) then
			self:UpdateTransmit()
		end
	end)
end

function PLUGIN:PlayerDisconnected(client)
	if (self.train) then
		self:FreeCabin(client)
	end
end

-- ------------------------------------------------------------------ aboard

-- The cabin a player wakes in, if they have one.
function PLUGIN:CabinOf(client)
	for i, occupant in pairs(self.train and self.train.occupants or {}) do
		if (occupant == client) then
			return i
		end
	end
end

function PLUGIN:FreeCabin(client)
	local i = self:CabinOf(client)

	if (i) then
		self.train.occupants[i] = nil
	end
end

-- Puts someone on the train: a newcomer in a free cabin facing its mirror, its door shut; anyone else
-- (or a newcomer with no cabin free, drawn at random) in the corridor.
function PLUGIN:PutAboard(client, character)
	local train = self.train

	if (!train) then
		self:SetState(client, character, states.station)
		self:PutOnPlatform(client)
		return
	end

	local state = self:GetState(character)
	local cabin

	if (state == states.cabin) then
		cabin = self:CabinOf(client)

		if (!cabin) then
			for i = 1, layout.cabins do
				local occupant = train.occupants[i]

				if (!IsValid(occupant) or !self:IsAboard(occupant) or self:CabinOf(occupant) != i
					or self:GetState(occupant:GetCharacter()) != states.cabin) then
					cabin = i
					break
				end
			end
		end

		if (!cabin) then
			-- no cabin free: someone drawn at random walks the corridor
			local bodies = self:GetBodies()
			local model = bodies[math.random(#bodies)]

			character:SetModel(model)
			client:SetModel(model)
			character:SetData("stature", math.random(#self.statures))
			character:SetData("age", math.random(#self.ages))
			character:SetDescription(self:Seen(model, character:GetData("stature"), character:GetData("age")))
			self:ApplyScale(client, character)
			character:SetData("arrival", states.aboard)
			state = states.aboard
		end
	end

	if (cabin) then
		train.occupants[cabin] = client
		self:ClearCabin(cabin, client)
		self:SetDoor(train.doors[cabin], false)

		local pos, yaw = self:ToWorld(train.place, layout.Bed(cabin))

		client:SetPos(pos)
		client:SetEyeAngles(Angle(0, yaw, 0))
	else
		local pos, yaw = self:ToWorld(train.place, layout.Corridor(client:EntIndex()))

		client:SetPos(pos)
		client:SetEyeAngles(Angle(0, yaw, 0))
	end

	client:SetVelocity(-client:GetVelocity())
end

-- Anyone but its newcomer standing in a cabin about to be shut is moved to the corridor.
function PLUGIN:ClearCabin(cabin, newcomer)
	local train = self.train
	local start = layout.CabinStart(cabin)

	for _, client in player.Iterator() do
		if (client != newcomer and self:IsAboard(client)) then
			local pos = self:ToLocal(train.place, client:GetPos())

			if (pos.x > start and pos.x < start + layout.cabinLong and pos.y > layout.corridor) then
				local spot, yaw = self:ToWorld(train.place, layout.Corridor(client:EntIndex()))

				client:SetPos(spot)
				client:SetEyeAngles(Angle(0, yaw, 0))
			end
		end
	end
end

-- Opens or shuts a door of the set.
function PLUGIN:SetDoor(door, bOpen)
	if (IsValid(door)) then
		door:SetOpen(bOpen)
	end
end

function PLUGIN:PutOnPlatform(client)
	local platform = self:GetPlatform()

	client:SetPos(platform.origin + Vector(math.Rand(-24, 24), math.Rand(-24, 24), 4))
	client:SetEyeAngles(Angle(0, platform.yaw, 0))
	client:SetVelocity(-client:GetVelocity())
end

-- The train's state, sent to everyone: riding, braking or standing, and since when.
function PLUGIN:SetTrainState(state)
	self.trainState = state
	self.trainSince = CurTime()
	SetNetVar("arrivingTrain", state)
	SetNetVar("arrivingTrainSince", self.trainSince)
end

-- Someone left their cabin: the train pulls in a while after the first to do so this ride.
function PLUGIN:PassengerLeftCabin()
	if (self.trainState == "riding" and !self.arriveAt) then
		self.arriveAt = CurTime() + ix.config.Get("arrivingRideTime", 60)
	end
end

-- Steps someone off the train onto the platform, through a fade.
function PLUGIN:Disembark(client)
	if (client.ixDisembarking) then
		return
	end

	client.ixDisembarking = true
	client:ScreenFade(SCREENFADE.OUT, color_black, self.fadeTime, self.fadeTime)

	timer.Simple(self.fadeTime, function()
		if (!IsValid(client)) then
			return
		end

		client.ixDisembarking = nil

		local character = client:GetCharacter()

		if (!character or self:GetState(character) != states.aboard) then
			return
		end

		self:SetState(client, character, states.station)
		self:PutOnPlatform(client)
		client:ScreenFade(SCREENFADE.IN, color_black, 1.2, 0)
		client:EmitSound("ambient/machines/train_idle.wav", 60, 100, 0.4)
		ix.log.Add(client, "arrivingDisembark")
	end)
end

ix.log.AddType("arrivingDisembark", function(client)
	return string.format("%s stepped off the train.", client:SteamName())
end)

ix.log.AddType("arrivingRegistered", function(client, name, number)
	return string.format("%s was registered at the intake desk as %s, number %s.", client:SteamName(), name, number)
end)

-- The ride: pulls in a while after someone leaves their cabin, opens the side door, lets them off, and
-- rides again once nobody who has left a cabin is aboard.
function PLUGIN:ThinkTrain()
	local train = self.train

	if (!train) then
		return
	end

	local out = {}

	for _, client in player.Iterator() do
		local character = client:GetCharacter()

		if (character and self:GetState(character) == states.aboard and client:Alive()) then
			out[#out + 1] = client
		end
	end

	local now = CurTime()

	if (self.trainState == "riding") then
		if (#out > 0 and !self.arriveAt) then
			self.arriveAt = now + ix.config.Get("arrivingRideTime", 60)
		end

		if (self.arriveAt and now >= self.arriveAt) then
			self.arriveAt = nil
			self:SetTrainState("braking")
		end
	elseif (self.trainState == "braking") then
		if (now - self.trainSince >= self.brakeTime) then
			self:SetTrainState("standing")
			self:SetDoor(train.doors.side, true)
		end
	elseif (self.trainState == "standing") then
		if (#out == 0) then
			self:SetDoor(train.doors.side, false)
			self:SetTrainState("riding")
		end
	end

	local stepMins, stepMaxs = layout.StepBox()

	for _, client in ipairs(out) do
		local pos = self:ToLocal(train.place, client:GetPos())

		if (pos.z < -40 or pos.z > layout.high + 40 or pos.x < -60 or pos.x > layout.Long() + 60) then
			-- fell or got out of the set some other way: back inside
			local spot, yaw = self:ToWorld(train.place, layout.Vestibule())

			client:SetPos(spot)
			client:SetEyeAngles(Angle(0, yaw, 0))
		elseif (self.trainState == "standing" and pos:WithinAABox(stepMins, stepMaxs)) then
			self:Disembark(client)
		end
	end
end

-- ------------------------------------------------------------------ the mirror

-- Someone looks in a mirror: the view turns to face them from the glass, and they're held still.
function PLUGIN:LookIn(client, mirror)
	local character = client:GetCharacter()

	if (!character or !client:Alive() or self:GetMirror(client) or client:GetPos():Distance(mirror:GetPos()) > 160) then
		return
	end

	client:SetNetVar("arrivingMirror", mirror)
	client:EmitSound("physics/cardboard/cardboard_box_impact_soft2.wav", 50, 110, 0.3)
end

-- Which of the bodies a character is in.
function PLUGIN:BodyIndex(character)
	local model = character:GetModel():lower()

	for i, body in ipairs(self:GetBodies()) do
		if (body:lower() == model) then
			return i
		end
	end

	return 0
end

PLUGIN.mirrorActions = {"bodyBack", "bodyNext", "taller", "shorter", "older", "keep"}

net.Receive("ixArrivingMirror", function(length, client)
	local action = PLUGIN.mirrorActions[net.ReadUInt(3)]
	local mirror = PLUGIN:GetMirror(client)
	local character = client:GetCharacter()

	if (!action or !mirror or !character) then
		return
	end

	if ((client.ixNextMirror or 0) > RealTime()) then
		return
	end

	client.ixNextMirror = RealTime() + 0.08
	PLUGIN:Choose(client, character, mirror, action)
end)

-- What someone at a mirror asks: another body, taller or shorter, older or younger, or to keep it all.
function PLUGIN:Choose(client, character, mirror, action)
	if (action == "bodyBack" or action == "bodyNext") then
		local bodies = self:GetBodies()
		local index = self:BodyIndex(character)
		local step = action == "bodyNext" and 1 or -1

		index = ((index - 1 + step) % #bodies) + 1

		character:SetModel(bodies[index])
		client:SetModel(bodies[index])
		client:ResetBodygroups()
		client:SetSkin(0)
		character:SetData("groups", nil)
		character:SetData("skin", nil)
		self:ApplyScale(client, character)
	elseif (action == "taller" or action == "shorter") then
		local stature = character:GetData("stature", self.middleStature)

		stature = math.Clamp(stature + (action == "taller" and 1 or -1), 1, #self.statures)
		character:SetData("stature", stature)
		self:ApplyScale(client, character)
	elseif (action == "older") then
		character:SetData("age", (character:GetData("age", self.middleAge) % #self.ages) + 1)
	elseif (action == "keep") then
		local seen = self:Seen(character:GetModel(), character:GetData("stature", self.middleStature),
			character:GetData("age", self.middleAge))

		character:SetDescription(seen)
		client:SetNetVar("arrivingMirror", nil)

		if (self:GetState(character) == states.cabin) then
			local cabin = self:CabinOf(client) or mirror.cabin

			self:SetState(client, character, states.aboard)
			self:FreeCabin(client)

			if (self.train and cabin) then
				self:SetDoor(self.train.doors[cabin], true)
			end

			self:PassengerLeftCabin()
		end
	end
end

-- Leaving a mirror's reach, dying or going away lets go of it.
function PLUGIN:ThinkMirrors()
	for _, client in player.Iterator() do
		local mirror = client:GetNetVar("arrivingMirror")

		if (mirror != nil and (!IsValid(mirror) or !client:Alive() or !client:GetCharacter()
			or client:GetPos():Distance(mirror:GetPos()) > 200)) then
			client:SetNetVar("arrivingMirror", nil)
		end
	end
end

-- ------------------------------------------------------------------ the intake desk

local function Clerk()
	local desk = PLUGIN.desk

	return desk and IsValid(desk[1]) and desk[1] or nil
end

-- Where applicants stand: in front of the clerk.
function PLUGIN:DeskFront()
	local clerk = Clerk()

	return clerk and clerk:GetPos() + clerk:GetForward() * (self.deskFront + 30) or nil
end

-- The clerk says something, heard by whoever is near the desk.
function PLUGIN:ClerkSays(text)
	local clerk = Clerk()

	if (!clerk) then
		return
	end

	local receivers = {}

	for _, client in player.Iterator() do
		if (client:GetCharacter() and client:GetPos():Distance(clerk:GetPos()) <= self.clerkHeard) then
			receivers[#receivers + 1] = client
		end
	end

	if (#receivers > 0) then
		ix.chat.Send(nil, "intake", text, false, receivers)
	end

	clerk:EmitSound("npc/metropolice/vo/on" .. math.random(1, 2) .. ".wav", 55, 100, 0.25)
end

-- Whether a character has no name yet.
function PLUGIN:IsNameless(character)
	return character != nil and string.Trim(character:GetName() or "") == ""
end

-- Someone nameless coming up to the desk is asked for their name; going off, they're no longer at it.
function PLUGIN:ThinkDesk()
	local front = self:DeskFront()

	if (!front) then
		return
	end

	for _, client in player.Iterator() do
		local character = client:GetCharacter()
		local flat = client:GetPos()
		local away = Vector(flat.x, flat.y, front.z):Distance(front)
		local near = math.abs(flat.z - front.z) < 96

		if (!client.ixIntakeAsked) then
			if (character and client:Alive() and self:IsNameless(character) and !self:IsAboard(client)
				and near and away <= self.askedWithin and (client.ixIntakeNext or 0) <= CurTime()) then
				client.ixIntakeAsked = true
				self:ClerkSays("Name? First and last.")
			end
		elseif (!character or !self:IsNameless(character) or !near or away > self.leftBeyond) then
			client.ixIntakeAsked = nil
			client.ixIntakeNext = CurTime() + 3
		end
	end
end

-- Whether a living character has this name, as far as the characters in memory know.
function PLUGIN:NameInMemory(name)
	local lower = name:utf8lower()

	for _, character in pairs(ix.char.loaded) do
		if (!character.isBot and (character:GetName() or ""):utf8lower() == lower) then
			return true
		end
	end

	return self.pendingNames and self.pendingNames[lower] or false
end

-- Whether a number is anyone's, as far as the characters in memory know.
function PLUGIN:NumberInMemory(number)
	for _, character in pairs(ix.char.loaded) do
		if (tostring(character:GetData("cid", "")) == number) then
			return true
		end
	end

	return self.pendingNumbers and self.pendingNumbers[number] or false
end

-- A number nobody has, checked against every saved character too, then `callback(number)`.
function PLUGIN:PickNumber(callback, tries)
	tries = tries or 0

	local number

	repeat
		number = tostring(math.random(10000, 99999))
	until (!self:NumberInMemory(number))

	if (tries >= 8) then
		return callback(number)
	end

	local query = mysql:Select("ix_characters")
		query:Select("id")
		query:Where("schema", Schema.folder)
		query:WhereLike("data", "\"cid\":\"" .. number .. "\"")
		query:Limit(1)
		query:Callback(function(result)
			if (istable(result) and #result > 0) then
				self:PickNumber(callback, tries + 1)
			else
				callback(number)
			end
		end)
	query:Execute()
end

-- What someone asked at the desk says next is their answer: refused, the clerk says why; taken, they're
-- given their name and a number, and handed their papers.
function PLUGIN:PostPlayerSay(client, chatType, message)
	if (chatType != "ic" or !client.ixIntakeAsked or client.ixIntakeBusy) then
		return
	end

	local character = client:GetCharacter()

	if (!self:IsNameless(character)) then
		return
	end

	local name, refusal = self:CheckName(message, function(candidate)
		return self:NameInMemory(candidate)
	end)

	if (!name) then
		timer.Simple(0.7, function()
			self:ClerkSays(self.refusals[refusal])
		end)

		return
	end

	client.ixIntakeBusy = true
	self.pendingNames = self.pendingNames or {}
	self.pendingNames[name:utf8lower()] = true

	local function Done()
		client.ixIntakeBusy = nil
		self.pendingNames[name:utf8lower()] = nil
	end

	local query = mysql:Select("ix_characters")
		query:Select("id")
		query:Where("schema", Schema.folder)
		query:WhereLike("name", name, "%s")
		query:Limit(1)
		query:Callback(function(result)
			if (!IsValid(client) or client:GetCharacter() != character) then
				Done()
				return
			end

			if (istable(result) and #result > 0) then
				Done()
				timer.Simple(0.7, function()
					self:ClerkSays(self.refusals.taken)
				end)

				return
			end

			self:PickNumber(function(number)
				Done()

				if (IsValid(client) and client:GetCharacter() == character and self:IsNameless(character)) then
					self:Register(client, character, name, number)
				end
			end)
		end)
	query:Execute()
end

-- A name and a number for someone, and their papers.
function PLUGIN:Register(client, character, name, number)
	character:SetName(name)
	character:SetData("cid", number)
	self:SetState(client, character, nil)
	client.ixIntakeAsked = nil

	-- the papers are theirs at once (in their pockets, or at their feet when those are full); the clerk's
	-- words and the handing over follow
	local data = {name = name, id = number}
	local inventory = character:GetInventory()

	if (!inventory or !inventory:Add("cid", 1, data)) then
		ix.item.Spawn("cid", client:GetPos() + Vector(0, 0, 40), nil, angle_zero, data)
	end

	timer.Simple(0.7, function()
		self:ClerkSays(name .. ". Number " .. number .. ". Your papers. Next.")

		timer.Simple(0.6, function()
			if (IsValid(client)) then
				client:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav", 55, 120, 0.5)
				client:Notify("You're handed your papers.")
			end
		end)
	end)

	character:Save()
	ix.log.Add(client, "arrivingRegistered", name, number)
	hook.Run("CharacterRegistered", client, character, name, number)
end

-- ------------------------------------------------------------------ every so often

function PLUGIN:Think()
	if ((self.nextThink or 0) > CurTime()) then
		return
	end

	self.nextThink = CurTime() + 0.25
	self:ThinkTrain()
	self:ThinkMirrors()
	self:ThinkDesk()
end

-- ------------------------------------------------------------------ placing it on a map

do
	local function Placer(key, describe)
		return {
			description = "Puts the " .. describe .. " where you stand, facing the way you face, on this map.",
			superAdminOnly = true,
			OnRun = function(self, client)
				PLUGIN:SetPlace(key, client:GetPos(), client:EyeAngles().y)
				PLUGIN:Build()

				return "The " .. describe .. " is here now."
			end
		}
	end

	-- Staff (and playtests of anything else) skip arriving: named on the spot and put on the platform.
	ix.command.Add("ArrivingSkip", {
		description = "Skips arriving: your nameless character is named (as given, or a plain name) and put on the platform.",
		superAdminOnly = true,
		arguments = bit.bor(ix.type.text, ix.type.optional),
		OnRun = function(self, client, said)
			local character = client:GetCharacter()

			if (!PLUGIN:IsNameless(character)) then
				return "You already have a name."
			end

			local name, refusal = PLUGIN:CheckName(said or "", function(candidate)
				return PLUGIN:NameInMemory(candidate)
			end)

			if (!said or said == "") then
				name, refusal = nil, "taken"

				for _ = 1, 40 do
					local candidate = table.Random({"Ada", "Ben", "Clara", "Dmitri", "Elsa", "Felix", "Greta", "Henrik"}) .. " "
						.. table.Random({"Black", "Novak", "Weller", "Moreau", "Hale", "Kovac", "Lind", "Marsh"})

					if (!PLUGIN:NameInMemory(candidate)) then
						name = candidate
						break
					end
				end
			end

			if (!name) then
				return PLUGIN.refusals[refusal]
			end

			if (PLUGIN:IsAboard(client)) then
				PLUGIN:FreeCabin(client)
				client:SetNetVar("arrivingMirror", nil)
				PLUGIN:SetState(client, character, states.station)
				PLUGIN:PutOnPlatform(client)
			end

			PLUGIN:PickNumber(function(number)
				if (IsValid(client) and client:GetCharacter() == character and PLUGIN:IsNameless(character)) then
					PLUGIN:Register(client, character, name, number)
				end
			end)
		end
	})

	ix.command.Add("ArrivingSetPlatform", Placer("platform", "platform newcomers step off onto"))
	ix.command.Add("ArrivingSetDesk", Placer("desk", "intake clerk (you stand where they stand)"))
	ix.command.Add("ArrivingSetTrain", Placer("train", "train's back corner (it runs the way you face)"))
end
