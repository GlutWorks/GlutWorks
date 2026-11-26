
Schema.name = "HL2 RP"
Schema.author = "nebulous.cloud"
Schema.description = "A schema based on Half-Life 2."

-- Include netstream
ix.util.Include("libs/thirdparty/sh_netstream2.lua")

ix.util.Include("sh_configs.lua")
ix.util.Include("sh_commands.lua")

ix.util.Include("cl_schema.lua")
ix.util.Include("cl_hooks.lua")
ix.util.Include("sh_hooks.lua")
ix.util.Include("sh_voices.lua")
ix.util.Include("sv_schema.lua")
ix.util.Include("sv_hooks.lua")

ix.util.Include("meta/sh_player.lua")
ix.util.Include("meta/sv_player.lua")
ix.util.Include("meta/sh_character.lua")

ix.flag.Add("v", "flagLightBlackmarket")
ix.flag.Add("V", "flagHeavyBlackmarket")

ix.anim.SetModelClass("models/eliteghostcp.mdl", "metrocop")
ix.anim.SetModelClass("models/eliteshockcp.mdl", "metrocop")
ix.anim.SetModelClass("models/leet_police2.mdl", "metrocop")
ix.anim.SetModelClass("models/sect_police2.mdl", "metrocop")
ix.anim.SetModelClass("models/policetrench.mdl", "metrocop")

function Schema:ZeroNumber(number, length)
	local amount = math.max(0, length - string.len(number))
	return string.rep("0", amount)..tostring(number)
end

function Schema:IsCombineRank(text, rank)
	return string.find(text, "[%D+]"..rank.."[%D+]")
end

-- Civil Protection ranks with command authority (objectives, datafile management).
Schema.commandRanks = {"OfC", "EpU", "DvL", "SeC"}

function Schema:HasCommandRank(client)
	if (!IsValid(client) or client:Team() != FACTION_MPF) then
		return false
	end

	local name = client:Name()

	for _, v in ipairs(self.commandRanks) do
		if (self:IsCombineRank(name, v)) then
			return true
		end
	end

	return false
end

-- Returns the uniform model for a citizen model. Stock HL2 citizens swap their group folder;
-- other citizen models (the zelpa "extended" citizens every default character uses) have no
-- group folder, so they map to the stock HL2 model with the same gender and face number.
-- `group` is the HL2 folder of the uniform ("group03" rebels, "group03m" medics).
function Schema:GetUniformModel(model, group)
	model = string.lower(model or "")

	if (model:find("/group0%dm?/")) then
		local swapped = model:gsub("/group0%dm?/", "/" .. group .. "/")

		if (util.IsValidModel(swapped)) then
			return swapped
		end
	end

	local gender, face = model:match("/(f?e?male)_(%d%d)[^/]*%.mdl$")

	if (gender) then
		local candidate = string.format("models/humans/%s/%s_%s.mdl", group, gender, face)

		if (util.IsValidModel(candidate)) then
			return candidate
		end

		-- HL2 has fewer faces than some citizen packs
		return string.format("models/humans/%s/%s_01.mdl", group, gender)
	end

	return model
end

local function LoadoutWarning(text)
	MsgC(Color(255, 200, 0), "[HL2 RP] ", text, "\n")
end

-- Gives a faction's starting items. Items that come from plugins may not be loaded, so a
-- missing definition is logged and skipped instead of aborting character creation.
function Schema:GiveLoadout(character, loadout)
	local inventory = character:GetInventory()

	if (!inventory) then
		return
	end

	for _, entry in ipairs(loadout) do
		local uniqueID, quantity, data = entry[1], entry[2] or 1, entry[3]

		if (!ix.item.list[uniqueID]) then
			LoadoutWarning(string.format("loadout item '%s' for %s is not registered; skipping it",
				uniqueID, character:GetName()))
		else
			local bSuccess, err

			-- the stacking plugin owns quantities for stackable items
			if (ix.stack and !data and ix.stack.IsStackable(ix.item.list[uniqueID])) then
				bSuccess, err = ix.stack.Give(inventory, uniqueID, quantity)
			else
				bSuccess, err = inventory:Add(uniqueID, quantity, data)
			end

			if (!bSuccess) then
				LoadoutWarning(string.format("could not give loadout item '%s' to %s: %s",
					uniqueID, character:GetName(), tostring(err)))
			end
		end
	end
end

do
	local CLASS = {}
	CLASS.color = Color(150, 100, 100)
	CLASS.format = "Dispatch broadcasts \"%s\""

	function CLASS:CanSay(speaker, text)
		if (!speaker:IsDispatch()) then
			speaker:NotifyLocalized("notAllowed")

			return false
		end
	end

	function CLASS:OnChatAdd(speaker, text)
		chat.AddText(self.color, string.format(self.format, text))
	end

	ix.chat.Register("dispatch", CLASS)
end

do
	local CLASS = {}
	CLASS.color = Color(75, 150, 50)
	CLASS.format = "%s radios in \"%s\""

	function CLASS:CanHear(speaker, listener)
		local character = listener:GetCharacter()
		local inventory = character:GetInventory()
		local bHasRadio = false

		for k, v in pairs(inventory:GetItemsByUniqueID("handheld_radio", true)) do
			if (v:GetData("enabled", false) and speaker:GetCharacter():GetData("frequency") == character:GetData("frequency")) then
				bHasRadio = true
				break
			end
		end

		return bHasRadio
	end

	function CLASS:OnChatAdd(speaker, text)
		text = speaker:IsCombine() and string.format("<:: %s ::>", text) or text
		chat.AddText(self.color, string.format(self.format, speaker:Name(), text))
	end

	ix.chat.Register("radio", CLASS)
end

do
	local CLASS = {}
	CLASS.color = Color(255, 255, 175)
	CLASS.format = "%s radios in \"%s\""

	function CLASS:GetColor(speaker, text)
		if (LocalPlayer():GetEyeTrace().Entity == speaker) then
			return Color(175, 255, 175)
		end

		return self.color
	end

	function CLASS:CanHear(speaker, listener)
		if (ix.chat.classes.radio:CanHear(speaker, listener)) then
			return false
		end

		local chatRange = ix.config.Get("chatRange", 280)

		return (speaker:GetPos() - listener:GetPos()):LengthSqr() <= (chatRange * chatRange)
	end

	function CLASS:OnChatAdd(speaker, text)
		text = speaker:IsCombine() and string.format("<:: %s ::>", text) or text
		chat.AddText(self.color, string.format(self.format, speaker:Name(), text))
	end

	ix.chat.Register("radio_eavesdrop", CLASS)
end

do
	local CLASS = {}
	CLASS.color = Color(175, 125, 100)
	CLASS.format = "%s requests \"%s\""

	function CLASS:CanHear(speaker, listener)
		return listener:IsCombine() or speaker:Team() == FACTION_ADMIN
	end

	function CLASS:OnChatAdd(speaker, text)
		chat.AddText(self.color, string.format(self.format, speaker:Name(), text))
	end

	ix.chat.Register("request", CLASS)
end

do
	local CLASS = {}
	CLASS.color = Color(175, 125, 100)
	CLASS.format = "%s requests \"%s\""

	function CLASS:CanHear(speaker, listener)
		if (ix.chat.classes.request:CanHear(speaker, listener)) then
			return false
		end

		local chatRange = ix.config.Get("chatRange", 280)

		return (speaker:Team() == FACTION_CITIZEN and listener:Team() == FACTION_CITIZEN)
		and (speaker:GetPos() - listener:GetPos()):LengthSqr() <= (chatRange * chatRange)
	end

	function CLASS:OnChatAdd(speaker, text)
		chat.AddText(self.color, string.format(self.format, speaker:Name(), text))
	end

	ix.chat.Register("request_eavesdrop", CLASS)
end

do
	local CLASS = {}
	CLASS.color = Color(150, 125, 175)
	CLASS.format = "%s broadcasts \"%s\""

	function CLASS:CanSay(speaker, text)
		if (speaker:Team() != FACTION_ADMIN) then
			speaker:NotifyLocalized("notAllowed")

			return false
		end
	end

	function CLASS:OnChatAdd(speaker, text)
		chat.AddText(self.color, string.format(self.format, speaker:Name(), text))
	end

	ix.chat.Register("broadcast", CLASS)
end
