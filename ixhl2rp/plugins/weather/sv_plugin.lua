local PLUGIN = PLUGIN

util.AddNetworkString("ixWeatherState")
util.AddNetworkString("ixWeatherThunder")

-- Seconds between thunder strikes at full precipitation; fewer as the storm fades in or out.
ix.weather.THUNDER_INTERVAL = {8, 35}

--- A random duration for a weather type, in seconds, between weatherMinDuration and weatherMaxDuration.
function ix.weather.RandomDuration(random)
	local low = ix.config.Get("weatherMinDuration", 10)
	local high = math.max(low, ix.config.Get("weatherMaxDuration", 30))
	local roll = (random or math.random)()

	return Lerp(roll, low, high) * 60
end

--- Chooses the type to follow `from` by its `next` weights. `random` returns 0..1 (default math.random), so a
-- check can pick a particular branch. Always "clear" while weatherEnabled is off.
function ix.weather.PickNext(from, random)
	if (!ix.config.Get("weatherEnabled", true)) then
		return "clear"
	end

	local definition = ix.weather.types[from] or ix.weather.types.clear
	local weights = definition.next or {}
	local ids = table.GetKeys(weights)
	local total = 0

	-- sorted so a given roll picks the same type every time
	table.sort(ids)

	for _, id in ipairs(ids) do
		if (ix.weather.types[id]) then
			total = total + weights[id]
		end
	end

	if (total <= 0) then
		return from
	end

	local roll = (random or math.random)() * total

	for _, id in ipairs(ids) do
		if (ix.weather.types[id]) then
			roll = roll - weights[id]

			if (roll < 0) then
				return id
			end
		end
	end

	return ids[#ids]
end

local function Broadcast(client)
	local state = ix.weather.state

	net.Start("ixWeatherState")
		net.WriteString(state.type)
		net.WriteString(state.previous)
		net.WriteDouble(state.changedAt)
		net.WriteDouble(state.transition)
		net.WriteDouble(state.endsAt)

	if (client) then
		net.Send(client)
	else
		net.Broadcast()
	end
end

ix.weather.Send = Broadcast

--- Switches to weather type `id` now. `duration` (seconds) defaults to a random one from config and
-- `transition` (seconds) to weatherTransitionTime. Setting the current type again only changes when it ends.
function ix.weather.Set(id, duration, transition, now)
	if (!ix.weather.types[id]) then
		error("unknown weather type " .. tostring(id), 2)
	end

	now = now or CurTime()
	duration = duration or ix.weather.RandomDuration()

	local old = ix.weather.state

	if (old.type == id) then
		ix.weather.state = {
			type = old.type,
			previous = old.previous,
			changedAt = old.changedAt,
			transition = old.transition,
			endsAt = now + duration
		}

		Broadcast()

		return
	end

	transition = math.max(0, transition or ix.config.Get("weatherTransitionTime", 90))

	ix.weather.state = {
		type = id,
		previous = old.type,
		changedAt = now,
		transition = transition,
		endsAt = now + math.max(duration, transition)
	}

	if (ix.weather.types[id].thunder and !ix.weather.types[old.type].thunder) then
		ix.weather.nextThunder = now + math.Rand(transition * 0.5, transition + 10)
	end

	Broadcast()
	hook.Run("WeatherChanged", id, old.type)
end

--- Ends the current type now and moves to the next one the picker chooses.
function ix.weather.Advance(random, now)
	ix.weather.Set(ix.weather.PickNext(ix.weather.state.type, random), nil, nil, now)
end

--- Sends one thunder strike to everyone: which sound, and how far off it is (0 overhead, 1 distant).
function ix.weather.Strike(soundIndex, distance)
	soundIndex = soundIndex or math.random(#ix.weather.thunderSounds)
	distance = math.Clamp(distance or math.Rand(0, 1), 0, 1)

	ix.weather.lastStrike = {time = CurTime(), sound = soundIndex, distance = distance}

	net.Start("ixWeatherThunder")
		net.WriteUInt(soundIndex, 4)
		net.WriteFloat(distance)
	net.Broadcast()
end

--- One step of the weather cycle at `now`: ends a type that has run out, holds clear while disabled, and
-- rolls thunder. The plugin's timer calls it every second; checks call it with their own time.
function ix.weather.Tick(now)
	now = now or CurTime()

	local state = ix.weather.state

	if (!ix.config.Get("weatherEnabled", true)) then
		if (state.type != "clear") then
			ix.weather.Set("clear", nil, nil, now)
		end

		return
	end

	if (now >= state.endsAt) then
		ix.weather.Advance(nil, now)
		state = ix.weather.state
	end

	if (ix.weather.types[state.type].thunder) then
		local precipitation = ix.weather.GetValue("precipitation", now)
		local interval = ix.weather.THUNDER_INTERVAL

		if (precipitation > 0.5 and now >= (ix.weather.nextThunder or 0)) then
			ix.weather.Strike()
			ix.weather.nextThunder = now + math.Rand(interval[1], interval[2]) / precipitation
		end
	end
end

function PLUGIN:OnEnabledChanged(bEnabled)
	if (bEnabled) then
		-- the clear spell that ran while disabled ends on the normal schedule from now
		local state = ix.weather.state

		ix.weather.state = {
			type = state.type,
			previous = state.previous,
			changedAt = state.changedAt,
			transition = state.transition,
			endsAt = CurTime() + ix.weather.RandomDuration()
		}

		Broadcast()
	elseif (ix.weather.state.type != "clear") then
		ix.weather.Set("clear")
	end
end

function PLUGIN:StartTimer()
	timer.Create("ixWeather", 1, 0, function()
		ix.weather.Tick()
	end)
end

function PLUGIN:InitializedPlugins()
	if (ix.weather.state.endsAt == 0) then
		local now = CurTime()

		ix.weather.state = {
			type = "clear", previous = "clear", changedAt = now, transition = 0,
			endsAt = now + ix.weather.RandomDuration()
		}
	end

	self:StartTimer()
end

-- Times are saved relative to now, since CurTime starts again from zero after a restart.
function PLUGIN:SaveData()
	local state = ix.weather.state
	local now = CurTime()

	self:SetData({
		type = state.type,
		previous = state.previous,
		elapsed = now - state.changedAt,
		transition = state.transition,
		remaining = state.endsAt - now
	})
end

function PLUGIN:LoadData()
	local data = self:GetData()

	if (!istable(data) or !ix.weather.types[data.type]) then
		return
	end

	local now = CurTime()

	ix.weather.state = {
		type = data.type,
		previous = ix.weather.types[data.previous] and data.previous or data.type,
		changedAt = now - math.max(0, tonumber(data.elapsed) or 0),
		transition = math.max(0, tonumber(data.transition) or 0),
		endsAt = now + math.max(0, tonumber(data.remaining) or 0)
	}

	Broadcast()
end

function PLUGIN:PlayerInitialSpawn(client)
	if (!client:IsBot()) then
		Broadcast(client)
	end
end

-- Sent again with the character, in case the join message arrived before the client's Lua was ready.
function PLUGIN:PlayerLoadedCharacter(client)
	if (!client:IsBot()) then
		Broadcast(client)
	end
end

-- A Lua refresh keeps the state on ix.weather; restart the timer for this load's functions.
if (timer.Exists("ixWeather")) then
	PLUGIN:StartTimer()
end
