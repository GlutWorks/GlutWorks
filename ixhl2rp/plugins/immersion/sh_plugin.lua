
local PLUGIN = PLUGIN

PLUGIN.name = "Immersion"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Nothing is drawn over the screen during play: the body is felt, notices are private lines, and players check themselves and their magazine in words."

ix.config.Add("immersionHideHUD", true, "Hide the stock HUD: info bars, ammo box, crosshairs, hit markers, damage indicator, notices (they become private chat lines), the weapon list, area names, the death screen's text, the restrained text, door labels, the vendor bubble, the recognition menu (a world panel instead) and the engine's hints, voice list and other HUD elements.", function(oldValue, value)
	if (SERVER) then
		PLUGIN:UpdateRestraintText()
	end
end, {
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

-- Notices (ix.util.Notify, Player:Notify and their localized forms) become private lines in this colour, the
-- one Examine and the vendor and inventory panels use (cl_screen.lua).
PLUGIN.noticeColor = Color(175, 170, 152)

-- Phrases that say something was refused, besides any notice ending in "!" (Helix's own mark). A notice that
-- refuses gets the refusal sound; any other notice a softer one.
PLUGIN.refusalPhrases = {
	-- Helix
	notNow = true, notAllowed = true, noPerm = true, noFit = true, invalidArg = true, invalid = true,
	plyNoExist = true, plyNotValid = true, cmdNoExist = true, canNotAfford = true, tellAdmin = true,
	vendorNoTrade = true, vendorNoMoney = true, vendorNoStock = true, vendorMaxStock = true, itemOwned = true,
	storageInUse = true, wrongPassword = true, passwordAttemptLimit = true, oocDelay = true, loocDelay = true,
	businessTooFast = true, weaponSlotFilled = true, equippedBag = true, equippedWeapon = true, nestedBags = true,
	modelNoSeq = true, unknownError = true, dNotValid = true, invalidItem = true, invalidInventory = true,
	-- the schema and the project's plugins
	cantChangeClassRestrained = true, dataTooFast = true, objectivesTooFast = true, radioAlreadyOn = true,
	vendingNeedMoney = true, mynotesCooldown = true, stackInvalid = true, stackMismatch = true, stackFull = true,
	stackNoAccess = true, stackSplitInvalid = true, stackSplitStep = true, stackSplitTooLarge = true,
	stackSplitOverLimit = true, stackVendorTooLittle = true
}

-- Phrases that end in "!" without refusing anything: they get the soft sound.
PLUGIN.plainPhrases = {
	buyGood = true, vendorBye = true, mapRestarting = true, deleteConfirm = true
}

--- Whether a notice says something was refused: its phrase is one of `refusalPhrases`, or its text ends in "!"
-- and its phrase is not one of `plainPhrases`. `phrase` is the language phrase it was sent as, nil for a plain
-- notice.
function PLUGIN:IsRefusalNotice(text, phrase)
	if (isstring(phrase)) then
		if (self.refusalPhrases[phrase]) then
			return true
		elseif (self.plainPhrases[phrase]) then
			return false
		end
	end

	text = string.TrimRight(tostring(text or ""))

	return text:sub(-1) == "!"
end

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
ix.util.Include("cl_screen.lua")

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
