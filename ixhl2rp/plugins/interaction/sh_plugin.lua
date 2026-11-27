local PLUGIN = PLUGIN

PLUGIN.name = "Interaction"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "One way to use anything: a faint outline on what you can use, tap Use for the obvious action, hold it for the options beside the thing, and Examine to read it in words."
PLUGIN.readme = [[
Replaces Helix's look-at tooltips, the blurred radial entity menu and the action progress bar.

- The usable thing under the aim within reach gets a faint outline (config `interactionHighlight`).
- Tapping Use does the obvious thing (take an item, open a container, talk to a vendor) through the
  entity's own Use on the server, or the entity's own tap on the client (a workbench opens what can be
  made there). A thing with no single obvious action opens its options.
- Holding Use for `holdTime` seconds opens the options as a world panel (ix.worldui) beside the thing:
  the obvious action, then what GetEntityMenu returns and what PopulateInteractionOptions adds, sorted,
  then Examine. Aim at one and release Use, or left click, to choose
  it; release while aiming at none, or look away, to cancel. Options go through ix.menu.NetworkChoice
  and item actions exactly as the old menu sent them.
- Examine, and /Examine, describe the thing in a private chat line built from the rows its tooltip
  would have shown, so every PopulateEntityInfo / PopulateCharacterInfo / PopulateItemTooltip
  contributor still counts.
- Timed actions draw nothing; the immersion plugin's concentrating feel and a soft sound stand in.

While any world panel is open, Use chooses its aimed row, or closes it when the aim is off the rows.

An entity can set `ENT.bInteractive` (false to opt out, true to opt in) and `ENT.interactionTap`
(true when tapping Use should run its Use, false when it should open the options), or define
`ENT:GetInteractionTap(client)` on the client returning a label and a function: the tap runs that
function, and the label heads the options (an entity menu option of the same label is dropped).
]]

ix.config.Add("interactionHighlight", true, "Outline the usable thing the player is looking at within reach.", nil, {
	category = "Immersion"
})

-- Units from the eye to the entity's surface within which it can be used, as Helix's use trace.
PLUGIN.reach = 96
-- Seconds Use must be held before the options open.
PLUGIN.holdTime = 0.35
-- /Examine reaches as far as the look-at tooltip did.
PLUGIN.examineReach = 160

-- Scripted entities with no tooltip or menu whose Use is the obvious action.
PLUGIN.usableClasses = {
	ix_rationdispenser = true,
	ix_vendingmachine = true,
	ix_childdispenser = true,
	ix_applicationterminal = true,
	ix_combinelock = true
}

-- Private lines for Examine: only the player it is for sees it, with no name in front of it, in the
-- same style as the immersion plugin's feel lines.
ix.chat.Register("examine", {
	color = Color(175, 170, 152),
	deadCanChat = true,
	CanHear = function(self, speaker, listener)
		return speaker == listener
	end,
	CanSay = function(self, speaker, text)
		return true
	end,
	OnChatAdd = function(self, speaker, text)
		chat.AddText(self.color, text)
	end
})

--- Whether a ragdoll is a dead player's body: a corpse left behind, or the ragdoll of a player who
-- has died since. The same rule the old world tooltip used to say "Seems deceased".
function PLUGIN:IsDeceased(entity)
	if (!IsValid(entity) or !entity:IsRagdoll()) then
		return false
	end

	local owner = entity:GetNetVar("player")

	return entity:GetNetVar("isDeadPlayer") == true or (IsValid(owner) and owner:IsPlayer() and !owner:Alive())
end

-- Ends a row with a full stop unless it already ends a sentence.
local function Sentence(text)
	text = string.Trim((text:gsub("%s+", " ")))

	if (text == "") then
		return
	end

	if (!text:find("[%.!%?]$") and !text:find("%.%.%.$")) then
		text = text .. "."
	end

	return text
end

--- Turns the rows a tooltip would have shown into a sentence or two, in `client`'s language.
-- `rows` is an ordered list of {id = row id, text = row text}. `info` may hold:
-- - `bDeceased`: a dead player's body. Injury rows are dropped (they are read from the owner, who
--   may have respawned) and "Seems deceased" follows the name, or a stranger's description.
-- - `bUnconscious`: the ragdoll of a living player.
-- - `bLocked`: true or false for something that locks, such as a container.
-- - `extra`: a list of further sentences, added at the end.
-- A name row reading "Unknown" (an unrecognised character) is left out, so a stranger is described
-- by their description alone.
function PLUGIN:ComposeExamine(rows, info, client)
	info = info or {}

	local unknown = L("unknown", client)
	local sentences = {}
	local bIntroduced = false

	-- a stranger is introduced by what they look like, before anything else about them
	for i, row in ipairs(rows) do
		if (row.id == "name" and row.text == unknown) then
			for j, other in ipairs(rows) do
				if (other.id == "description") then
					rows = table.Copy(rows)
					table.insert(rows, i, table.remove(rows, j))
					break
				end
			end

			break
		end
	end

	for _, row in ipairs(rows) do
		local id = row.id

		if (id == "icon" or (info.bDeceased and id == "injureText") or (id == "name" and row.text == unknown)) then
			continue
		end

		local text = Sentence(tostring(row.text or ""))

		if (text) then
			sentences[#sentences + 1] = text

			-- whoever it was is introduced by their name, or a stranger by their description
			if (!bIntroduced and (id == "name" or id == "description")) then
				bIntroduced = true

				if (info.bDeceased) then
					sentences[#sentences + 1] = L("examineDeceased", client)
				end
			end
		end
	end

	if (info.bDeceased and !bIntroduced) then
		table.insert(sentences, 1, L("examineDeceased", client))
		table.insert(sentences, 1, L("examineBody", client))
	end

	if (info.bUnconscious) then
		sentences[#sentences + 1] = L("examineUnconscious", client)
	end

	if (info.bLocked != nil) then
		sentences[#sentences + 1] = L(info.bLocked and "examineLocked" or "examineUnlocked", client)
	end

	for _, v in ipairs(info.extra or {}) do
		sentences[#sentences + 1] = v
	end

	if (#sentences == 0) then
		return L("examineNothing", client)
	end

	return table.concat(sentences, " ")
end

-- A phrase in `client`'s language on the server, in the local player's on the client (where L takes no player).
local function Phrase(key, client, ...)
	if (SERVER) then
		return L(key, client, ...)
	end

	return L(key, ...)
end

--- What a door's label (Helix's doors plugin) said, as one line in `client`'s language: its title, or "Unowned
-- Door" / "Purchased Door", then who owns it or whether it can be bought. Examine says this now that the label is
-- not drawn. A door staff never labelled, or hid (`visible` off), had no label and is "A door."
function PLUGIN:DescribeDoor(door, client)
	if (!door:GetNetVar("visible")) then
		return Phrase("examineDoor", client)
	end

	local owner = door:GetDTEntity(0)
	owner = IsValid(owner) and owner or nil

	local name = door:GetNetVar("title", door:GetNetVar("name", Phrase(owner and "dTitleOwned" or "dTitle", client)))
	local description = Phrase(door:GetNetVar("ownable") and "dIsOwnable" or "dIsNotOwnable", client)
	local class = door:GetNetVar("class")
	local faction = door:GetNetVar("faction")
	local group

	if (class and ix.class.list[class]) then
		group = ix.class.list[class].name
	elseif (faction and ix.faction.indices[faction]) then
		group = ix.faction.indices[faction].name
	end

	if (owner) then
		description = Phrase("dOwnedBy", client, owner:GetName())
	elseif (group) then
		local translated = SERVER and L2(group, client) or (CLIENT and L2(group))

		description = Phrase("dOwnedBy", client, translated or group)
	end

	return self:ComposeExamine({{id = "name", text = name}, {id = "description", text = description}}, {}, client)
end

ix.util.Include("sv_plugin.lua")
ix.util.Include("cl_plugin.lua")

ix.command.Add("Examine", {
	description = "@cmdExamine",
	OnRun = function(self, client)
		PLUGIN:RequestExamine(client)
	end
})
