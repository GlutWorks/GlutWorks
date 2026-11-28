local PLUGIN = PLUGIN

PLUGIN.name = "Arriving"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "No intro and no character menu: a newcomer wakes on a train coming into the city, chooses who they are at their cabin's mirror, and gives their name aloud at the station's intake desk."
PLUGIN.readme = [[
Making a character is a scene, not a screen.

- Joining. Helix's intro and character menu never open. The client asks the server to arrive
  (`ixArrivingReady`) once its characters are synced, and the server decides: the player's most
  recently played character that may be used comes back where it was; with none, a nameless citizen
  is made (`ix.char.Create`, data `arrival = "cabin"`) and wakes in a cabin of the train. Clients can
  no longer make or choose characters themselves (`CanPlayerCreateCharacter`, `CanPlayerUseCharacter`).
- The train is a set (`sh_layout.lua`): a carriage of cabins off a corridor, built from box pieces
  (`ix_arriving_piece`) and props high in the map's open sky, where nobody can reach it, and sent only
  to the players aboard it (`SetPreventTransmit`); nobody else sees it or them. It lights itself
  (cabin lamps and the lights that pass the windows) instead of taking the map's daylight. The ride is
  the window, the sound and a sway; it pulls in `arrivingRideTime` seconds after the first passenger
  leaves their cabin, opens its side door and waits until nobody who has left a cabin is aboard.
  Stepping off through the side door fades to black and puts you on the station platform.
- The mirror (`ix_arriving_mirror`). Use turns the view round to look at you from the glass, as
  Fallout 4's does (a camera, not a reflection). Left and right try each body (the citizen faction's
  models, in the blue suit: every bodygroup 0), forward and back stand you taller or shorter (6%
  either way: the body and the eye, not the hull), reload makes you older or younger, and a line under
  the glass says how others will see you. Use keeps it: that line becomes the description, and the
  cabin door slides open.
- The intake desk (`ix_intake_clerk`). A nameless character who comes up is asked for their name;
  what they say aloud next (IC) is checked on the server (`sv_names.lua`): a first and a last name (a
  middle one allowed), letters only, not a living character's, nothing refused. The clerk refuses in
  words or stamps it: the name is set, a five-figure number is issued (data `cid`) and the papers (a
  `cid` item) handed over.
- Where it all is, per map: `/ArrivingSetPlatform`, `/ArrivingSetDesk`, `/ArrivingSetTrain`
  (superadmin) keep a spot in the plugin's map data; known maps have defaults in `PLUGIN.places`;
  elsewhere the train finds open sky over a spawn point and the platform is a spawn point.
  `/ArrivingSkip [name]` (superadmin) names a nameless character on the spot and puts them on the
  platform, for staff and for playtests of anything else.

Not yet: switching characters by leaving on a train (and the list shown only then), an officer
player at the desk, and a train that really pulls into a station on the map.
]]

ix.config.Add("arrivingRideTime", 60, "Seconds the train takes to pull in once its first passenger has left their cabin.", nil, {
	data = {min = 5, max = 600},
	category = "Arriving"
})

-- What a character's `arrival` data says about where they are in arriving: nil once named (in the city).
PLUGIN.states = {
	cabin = "cabin", -- woken in a cabin, choosing who they are at its mirror
	aboard = "aboard", -- out of their cabin, on the train
	station = "station" -- off the train, nameless till the intake desk takes their name
}

-- How long the train brakes before it stands at the platform (seconds).
PLUGIN.brakeTime = 9

-- Heights at the mirror: how much taller than its model a body is drawn, and the eye raised with it.
PLUGIN.statures = {0.94, 0.96, 0.98, 1, 1.02, 1.04, 1.06}
PLUGIN.middleStature = 4

-- Ages at the mirror, as they're said.
PLUGIN.ages = {"young", "middle-aged", "older"}
PLUGIN.middleAge = 2

-- The bodies a newcomer can be: the citizen faction's models, in the order the faction lists them.
function PLUGIN:GetBodies()
	local faction = ix.faction.indices[FACTION_CITIZEN]
	local bodies = {}

	for _, model in ipairs(faction and faction.models or {}) do
		bodies[#bodies + 1] = istable(model) and model[1] or model
	end

	return bodies
end

-- Whether a model is a woman's body.
function PLUGIN:IsWoman(model)
	return isstring(model) and model:lower():find("female", 1, true) != nil
end

-- How tall someone looks, when it's marked: nothing for most.
function PLUGIN:HeightWord(stature)
	return ({"short", "a little short", nil, nil, nil, "a little tall", "tall"})[stature]
end

-- Someone, as a stranger who sees them would put it: "A tall young woman", "An older man, a little short".
function PLUGIN:Seen(model, stature, age)
	local who = self:IsWoman(model) and "woman" or "man"
	local ageWord = self.ages[age] or self.ages[self.middleAge]
	local height = self:HeightWord(stature)
	local words

	if (height == "tall" or height == "short") then
		words = height .. " " .. ageWord .. " " .. who
	elseif (height) then
		words = ageWord .. " " .. who .. ", " .. height
	else
		words = ageWord .. " " .. who
	end

	local article = words:find("^[aeiouAEIOU]") and "An " or "A "

	return article .. words
end

-- A character's arrival state, or nil once they're in the city.
function PLUGIN:GetState(character)
	return character and character:GetData("arrival") or nil
end

-- Whether a player is on the train (in a cabin or aboard).
function PLUGIN:IsAboard(client)
	local state = IsValid(client) and self:GetState(client:GetCharacter())

	return state == self.states.cabin or state == self.states.aboard
end

-- How much taller than its model a character's body is drawn.
function PLUGIN:GetScale(character)
	return self.statures[character and character:GetData("stature") or self.middleStature] or 1
end

-- The mirror a player is at, if any.
function PLUGIN:GetMirror(client)
	local mirror = IsValid(client) and client:GetNetVar("arrivingMirror")

	return IsValid(mirror) and mirror or nil
end

ix.util.Include("sh_layout.lua")
ix.util.Include("sv_names.lua")
ix.util.Include("sv_plugin.lua")
ix.util.Include("cl_plugin.lua")

-- The intake clerk's words, heard by those near the desk (the server picks them).
ix.chat.Register("intake", {
	color = Color(170, 190, 205),
	-- only the server speaks for the clerk, to the listeners it picks
	CanSay = function(self, speaker, text)
		return !IsValid(speaker)
	end,
	CanHear = function(self, speaker, listener)
		return true
	end,
	OnChatAdd = function(self, speaker, text)
		chat.AddText(self.color, "The clerk says \"" .. text .. "\"")
	end
})

-- A body's eye height follows its scale: the eye is raised, the hull stays.
function PLUGIN:ApplyScale(client, character)
	local scale = self:GetScale(character)

	client:SetModelScale(scale, 0)
	client:SetViewOffset(Vector(0, 0, 64 * scale))
	client:SetViewOffsetDucked(Vector(0, 0, 28 * scale))
end

-- Someone at a mirror is held still, facing it, while they choose.
function PLUGIN:StartCommand(client, command)
	local mirror = self:GetMirror(client)

	if (mirror) then
		local toward = mirror:GetPos() - client:GetPos()

		command:ClearMovement()
		command:ClearButtons()
		command:SetViewAngles(Angle(0, toward:Angle().y, 0))
	end
end
