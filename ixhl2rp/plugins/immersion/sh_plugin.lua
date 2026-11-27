
local PLUGIN = PLUGIN

PLUGIN.name = "Immersion"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Replaces the always-on HUD with body feedback, and lets players check themselves and their magazine."

ix.config.Add("immersionHideHUD", true, "Hide the info bars, ammo box, crosshairs, hit markers and damage indicator.", nil, {
	category = "Immersion"
})

ix.option.Add("reduceMotionEffects", ix.type.bool, false, {
	category = "immersion"
})

-- Private lines for /Feel and checking a magazine: only the player it is sent to sees it, with
-- no name in front of it.
ix.chat.Register("feel", {
	color = Color(165, 160, 145),
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

--- Whether the always-on HUD is hidden for this player right now.
function PLUGIN:IsHUDHidden(client)
	return ix.config.Get("immersionHideHUD", true) and IsValid(client) and client:GetCharacter() != nil
end

--- A weapon whose magazine can be checked: it has a clip and fires ammunition.
function PLUGIN:HasMagazine(weapon)
	return IsValid(weapon) and weapon:GetMaxClip1() > 0 and weapon:GetPrimaryAmmoType() >= 0
end

ix.util.Include("sv_plugin.lua")
ix.util.Include("cl_plugin.lua")

ix.command.Add("Feel", {
	description = "@cmdFeel",
	OnRun = function(self, client)
		PLUGIN:SendFeeling(client)
	end
})

ix.command.Add("CheckAmmo", {
	description = "@cmdCheckAmmo",
	OnRun = function(self, client)
		PLUGIN:CheckMagazine(client, true)
	end
})
