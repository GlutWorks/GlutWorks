local PLUGIN = PLUGIN

-- Everything else that painted over the screen during play: notices, the chat's frame, the area banner, the
-- death screen's text, the recognition menu, the engine's own HUD elements, the voice list and sandbox's hints.
-- The world shows state; what it cannot show is felt or said in one private line. All of it follows
-- immersionHideHUD except the chat's frame and the command list's trim, which are gone whatever the config.

-- A notice is a private line with a soft sound; one that refuses gets the refusal sound instead (interaction's
-- broken-off scuff, the same as a refused tap).
PLUGIN.noticeSound = {path = "garrysmod/ui_hover.wav", volume = 0.25}

-- Engine and base gamemode HUD elements hidden while the HUD is hidden, on top of the ones Helix always hides
-- (helix/gamemode/core/hooks/cl_hooks.lua). Closed captions, the net graph and CHudGMod (which runs every
-- HUDPaint) stay; so does CHudWeapon, which draws weapons' own overlays such as scopes, and CHudVoiceSelfStatus,
-- the small mark that tells a player their own microphone is open.
PLUGIN.hiddenElements = {
	CHudDamageIndicator = true,
	CHudDeathNotice = true,
	CHudHintDisplay = true,
	CHudMessage = true,
	CHudMenu = true,
	CHudTrain = true,
	CHudVehicle = true,
	CHudZoom = true,
	CHudSuitPower = true,
	CHudFlashlight = true,
	CHudLocator = true,
	CHudPosture = true,
	CHudVoiceStatus = true,
	CTargetID = true,
	CHudBonusProgress = true,
	CHudCommentary = true
}

-- Notices ---------------------------------------------------------------------------------------------------

-- Helix's client ix.util.Notify (its NotifyLocalized only calls it), kept across a Lua refresh of this file alone:
-- a refresh of the whole gamemode defines it again first.
ix.immersionNotify = ix.immersionNotify or {own = setmetatable({}, {__mode = "k"})}

local notices = ix.immersionNotify

if (!notices.own[ix.util.Notify]) then
	notices.Notify = ix.util.Notify
end

local function PlayRefusal()
	local interaction = ix.plugin.list.interaction

	if (interaction and interaction.PlayActionSound) then
		interaction:PlayActionSound("cancel")
	else
		surface.PlaySound("buttons/button10.wav")
	end
end

--- Whether a menu that hides the chat lines is up: Helix's Tab menu or the character menu (both fade the chat out,
-- helix/plugins/chatbox/derma/cl_chatbox.lua). They are exceptions to the no-HUD rule, and a notice shown while one
-- is up is Helix's own corner notice, or it would not be seen at all.
function PLUGIN:IsChatHidden()
	return IsValid(ix.gui.menu) or IsValid(ix.gui.characterMenu)
end

--- Shows a notice as Helix's corner notice (the stock way), whatever the chatNotices option says.
function PLUGIN:AddNoticeToast(text)
	if (IsValid(ix.gui.notices)) then
		ix.gui.notices:AddNotice(text)
	end

	MsgC(Color(0, 255, 255), text .. "\n")
end

--- Prints a notice as a private line in the notice colour and plays its sound. Called inside the chat class
-- "notice" (so the harness and the console see it as a notice). Every notice reaches the player: when the active
-- chat tab filters notices out, the line is put in that tab anyway, as the corner notices ignored tabs; the other
-- tabs keep their filters. While a menu hides the chat it is the corner notice instead.
function PLUGIN:AddNoticeLine(text, bRefusal)
	text = tostring(text)

	if (self:IsChatHidden()) then
		return self:AddNoticeToast(text)
	end

	chat.AddText(self.noticeColor, text)

	local chatbox = ix.gui.chat
	local tab = IsValid(chatbox) and chatbox.tabs and chatbox.tabs:GetActiveTab()

	if (IsValid(tab) and tab:GetFilter()["notice"]) then
		tab:AddLine({self.noticeColor, text}, true)
	end

	if (bRefusal) then
		PlayRefusal()
	else
		local info = self.noticeSound

		LocalPlayer():EmitSound(info.path, 0, math.random(96, 104), info.volume, CHAN_STATIC)
	end
end

--- Helix's "notice" chat class (Player:ChatNotify, the chatNotices option, and every notice here) prints the
-- muted private line instead of its icon and blue while the HUD is hidden. Helix registers the class when its chat
-- library loads (sh_chatbox.lua), before the plugins; registering it again (a Lua refresh of that file) makes a new
-- table, so this checks again whenever a notice is shown.
function PLUGIN:WrapNoticeClass()
	local class = ix.chat.classes.notice

	if (!class or class.ixImmersionOnChatAdd) then
		return class
	end

	class.ixImmersionOnChatAdd = class.OnChatAdd

	function class:OnChatAdd(speaker, text, bAnonymous, data)
		if (PLUGIN:IsHUDHidden(LocalPlayer())) then
			PLUGIN:AddNoticeLine(text, istable(data) and data.bError)
			return
		end

		return self:ixImmersionOnChatAdd(speaker, text, bAnonymous, data)
	end

	return class
end

--- Shows a notice: a private line while the HUD is hidden, Helix's own notice otherwise. `phrase` is the
-- language phrase it was sent as (nil for plain text); together with the text it decides whether it is a
-- refusal (PLUGIN:IsRefusalNotice). ShouldShowNotice can drop it.
function PLUGIN:ShowNotice(text, phrase)
	text = tostring(text)

	local client = LocalPlayer()
	local bRefusal = self:IsRefusalNotice(text, phrase)

	if (hook.Run("ShouldShowNotice", text, phrase, bRefusal) == false) then
		return
	end

	if (!IsValid(client) or !self:IsHUDHidden(client)) then
		return notices.Notify(text)
	end

	if (self:WrapNoticeClass()) then
		ix.chat.Send(client, "notice", text, false, {bError = bRefusal})
	else
		self:AddNoticeLine(text, bRefusal)
	end
end

local function Notify(message)
	PLUGIN:ShowNotice(message)
end

local function NotifyLocalized(phrase, ...)
	PLUGIN:ShowNotice(L(phrase, ...), phrase)
end

notices.own[Notify] = true
notices.own[NotifyLocalized] = true

-- Player:Notify, Player:NotifyLocalized and Helix's ixNotify/ixNotifyLocalized receivers all call these.
ix.util.Notify = Notify
ix.util.NotifyLocalized = NotifyLocalized

-- The chat --------------------------------------------------------------------------------------------------

-- Text chat stays, but not as a box on the screen. Idle, Helix's chatbox already shows only the lines, which fade.
-- While typing it drew a blurred, outlined frame with a coloured glow and a tab strip; now there is only the text
-- entry and, for a slash, the command list (its own panel). With one tab its name is not shown; with several, the
-- tab names are shown as plain words so they can still be clicked. The strip keeps its place, so dragging the
-- chat by it, right-clicking it for the tab menu and resizing from the corner all still work, unseen.
local TAB_ACTIVE = Color(235, 230, 215)
local TAB_INACTIVE = Color(150, 145, 135)
local TAB_UNREAD = Color(225, 190, 120)
local TAB_HIDDEN = Color(0, 0, 0, 0)

local function TabCount(button)
	local strip = button:GetParent()
	local tabs = IsValid(strip) and strip:GetParent()

	return (IsValid(tabs) and tabs.GetTabs) and table.Count(tabs:GetTabs()) or 1
end

function PLUGIN:QuietChatSkin()
	local skin = derma.GetNamedSkin("helix")

	if (!skin or skin.ixImmersionChat) then
		return
	end

	skin.ixImmersionChat = true

	function skin:PaintChatboxBackground(panel, width, height)
	end

	function skin:PaintChatboxTabs(panel, width, height)
	end

	function skin:PaintChatboxTabButton(panel, width, height)
		local color = TAB_HIDDEN

		if (TabCount(panel) > 1) then
			color = panel:GetActive() and TAB_ACTIVE or (panel:GetUnread() and TAB_UNREAD or TAB_INACTIVE)
		end

		if (panel.ixImmersionColor != color) then
			panel.ixImmersionColor = color
			panel:SetTextColor(color)
		end
	end

	function skin:PaintChatboxEntry(panel, width, height)
		surface.SetDrawColor(0, 0, 0, 110)
		surface.DrawRect(0, 0, width, height)

		panel:DrawTextEntryText(color_white, ix.config.Get("color"), color_white)
	end
end

PLUGIN:QuietChatSkin()

-- The command list under a slash keeps its dark backing, but only behind the commands it lists, not over the
-- whole chat area.
function PLUGIN:TrimAutocomplete()
	local PANEL = vgui.GetControlTable("ixChatboxAutocomplete")

	if (!PANEL or PANEL.ixImmersionPaint) then
		return
	end

	PANEL.ixImmersionPaint = PANEL.Paint

	function PANEL:Paint(width, height)
		local used = math.min(height, self:GetCanvas():GetTall())

		if (used > 0) then
			surface.SetDrawColor(0, 0, 0, 200)
			surface.DrawRect(0, 0, width, used)
		end
	end
end

PLUGIN:TrimAutocomplete()

-- The area banner --------------------------------------------------------------------------------------------

-- Entering a named area printed its name and the time at the top of the screen. The place is the place; staff
-- editing areas keep their overlay (the area plugin's own HUDPaint).
function PLUGIN:ShouldDisplayArea(id)
	if (self:IsHUDHidden(LocalPlayer())) then
		return false
	end
end

-- The death screen -------------------------------------------------------------------------------------------

-- Dying fades to black and back with the same timing (Helix's ixDeathScreen, driven by spawnTime), without
-- "You are dead" in the middle. The body feedback stops on its own: nothing is felt while dead (CanFeelBody).
function PLUGIN:QuietDeathScreen()
	local PANEL = vgui.GetControlTable("ixDeathScreen")

	if (!PANEL or PANEL.ixImmersionPaint) then
		return
	end

	PANEL.ixImmersionPaint = PANEL.Paint

	function PANEL:Paint(width, height)
		if (!PLUGIN:IsHUDHidden(LocalPlayer())) then
			return self:ixImmersionPaint(width, height)
		end

		derma.SkinFunc("PaintDeathScreenBackground", self, width, height, self.progress)
		derma.SkinFunc("PaintDeathScreen", self, width, height, self.progress)
	end
end

PLUGIN:QuietDeathScreen()

-- The recognition menu -----------------------------------------------------------------------------------------

-- Helix's recognition (F3, gm_showspare1) popped a menu up in the middle of the screen asking whom to introduce
-- yourself to. While the HUD is hidden the same four choices are held in front of the player on a world panel and
-- sent through Helix's own ixRecognize; with immersionHideHUD off, or without worldui, Helix's menu opens as before.
PLUGIN.recognizeRows = {
	{phrase = "rgnLookingAt", level = 0},
	{phrase = "rgnWhisper", level = 1},
	{phrase = "rgnTalk", level = 2},
	{phrase = "rgnYell", level = 3}
}

function PLUGIN:OpenRecognition()
	local rows = {}

	for _, v in ipairs(self.recognizeRows) do
		rows[#rows + 1] = {label = L(v.phrase), level = v.level}
	end

	return ix.worldui.Open({
		held = true,
		name = "recognize",
		rows = rows,
		OnSelect = function(panel, row)
			net.Start("ixRecognize")
				net.WriteUInt(row.level, 2)
			net.SendToServer()
		end
	})
end

function PLUGIN:WrapRecognition()
	local current = net.Receivers.ixrecognizemenu

	if (!current or current == self.recognizeReceiver) then
		return
	end

	self.stockRecognize = current
	self.recognizeReceiver = function(...)
		if (ix.worldui and PLUGIN:IsHUDHidden(LocalPlayer())) then
			PLUGIN:OpenRecognition()
			return
		end

		return PLUGIN.stockRecognize(...)
	end

	net.Receivers.ixrecognizemenu = self.recognizeReceiver
end

PLUGIN:WrapRecognition()

-- The engine's HUD, the voice list and hints ------------------------------------------------------------------

function PLUGIN:HUDShouldDraw(element)
	if (self.hiddenElements[element] and self:IsHUDHidden(LocalPlayer())) then
		return false
	end
end

-- The base gamemode lists everyone using their microphone at the side of the screen. Voice is heard in the world.
function PLUGIN:PlayerStartVoice(client)
	if (self:IsHUDHidden(LocalPlayer())) then
		return true
	end
end

-- Sandbox throws popup hints a while after joining ("press Q for the spawn menu" and others). The ones sandbox
-- queues as it loads are held (their timers paused) until the server's config reaches the client, then dropped
-- while the HUD is hidden or let run when it is not; a hint queued later is dropped while the HUD is hidden.
PLUGIN.queuedHints = {"OpeningMenu", "Annoy1", "Annoy2"}

local function ForQueuedHints(fn)
	for _, name in ipairs(PLUGIN.queuedHints) do
		local id = "HintSystem_" .. name

		if (timer.Exists(id)) then
			fn(id)
		end
	end
end

if (!ix.immersionHintsSettled) then
	ForQueuedHints(timer.Pause)
end

-- The server's config list arrived (Helix runs this hook with the list; its own load at startup passes nothing).
function PLUGIN:InitializedConfig(data)
	if (data == nil or ix.immersionHintsSettled) then
		return
	end

	ix.immersionHintsSettled = true
	ForQueuedHints(ix.config.Get("immersionHideHUD", true) and timer.Remove or timer.UnPause)
end

-- The wrappers this file has made, so a Lua refresh of it wraps the gamemode's own AddHint and not an old wrapper.
ix.immersionHintWrappers = ix.immersionHintWrappers or setmetatable({}, {__mode = "k"})

local function AddHint(self, name, delay)
	if (ix.config.Get("immersionHideHUD", true)) then
		return
	end

	return self:ixImmersionAddHint(name, delay)
end

ix.immersionHintWrappers[AddHint] = true

function PLUGIN:WrapHints()
	-- GM while the gamemode loads or reloads (registering it afterwards copies GM over GAMEMODE), GAMEMODE after
	local gamemode = GM or GAMEMODE

	if (!gamemode or !isfunction(gamemode.AddHint)) then
		return
	end

	if (!ix.immersionHintWrappers[gamemode.AddHint]) then
		gamemode.ixImmersionAddHint = gamemode.AddHint
	end

	gamemode.AddHint = AddHint
end

function PLUGIN:InitPostEntity()
	self:WrapHitmarkers()
	self:WrapNoticeClass()
	self:QuietChatSkin()
	self:TrimAutocomplete()
	self:QuietDeathScreen()
	self:WrapHints()
	self:WrapRecognition()
end
