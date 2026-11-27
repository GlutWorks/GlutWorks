local PLUGIN = PLUGIN
PLUGIN.name = "Fancy /Me"
PLUGIN.description = "Distance based /me and /it commands/"
PLUGIN.author = "liquid"

ix.config.Add("chatActionYRange", 1000, "The maximum distance a yelling (/MeY, /ItY) action can go.", nil, {
	data = {min = 10, max = 5000, decimals = 1},
	category = "chat"
})

ix.config.Add("chatActionWRange", 75, "The maximum distance a whispering (/MeW, /ItW) action can go.", nil, {
	data = {min = 10, max = 5000, decimals = 1},
	category = "chat"
})

-- The range is read on every message, not once here. Helix turns a numeric CanHear into a
-- range fixed at registration, so a config change would otherwise need a restart.
local function WithinRange(configKey, default)
	return function(self, speaker, listener)
		local range = ix.config.Get(configKey, default)
		return speaker:GetPos():DistToSqr(listener:GetPos()) <= range * range
	end
end

-- Fonts are built from the server's configured font, like Helix's ixChatFont.
function PLUGIN:LoadFonts(font, genericFont)
	local size = math.max(ScreenScale(7), 17) * ix.option.Get("chatFontScale", 1)

	surface.CreateFont("ixChatFontYell", {
		font = font,
		size = size * 1.25,
		extended = true,
		weight = 600,
		antialias = true
	})

	surface.CreateFont("ixChatFontWhisper", {
		font = font,
		size = size * 0.85,
		extended = true,
		weight = 600,
		antialias = true,
		italic = true
	})
end

-- y
-- w
-- l

function PLUGIN:InitializedChatClasses()
    ix.chat.Register("mey", {
        format = "*** %s %s",
        GetColor = ix.chat.classes.ic.GetColor,
        CanHear = WithinRange("chatActionYRange", 1000),
        prefix = {"/MeY"},
        description = "Perform a physical action (YELLING DISTANCE).",
        indicator = "chatPerforming",
        deadCanChat = true,
        font = "ixChatFontYell"
    })

    -- Actions and such.
    ix.chat.Register("ity", {
        OnChatAdd = function(self, speaker, text)
            chat.AddText(ix.config.Get("chatColor"), "*** "..text)
        end,
        CanHear = WithinRange("chatActionYRange", 1000),
        prefix = {"/ItY"},
        description = "Make something around you perform an action (YELLING DISTANCE).",
        indicator = "chatPerforming",
        deadCanChat = true,
        font = "ixChatFontYell"
    })

    ix.chat.Register("mew", {
        format = "* %s %s",
        GetColor = ix.chat.classes.ic.GetColor,
        CanHear = WithinRange("chatActionWRange", 75),
        prefix = {"/MeW"},
        description = "Perform a physical action (WHISPERING DISTANCE).",
        indicator = "chatPerforming",
        deadCanChat = true,
        font = "ixChatFontWhisper"
    })

    -- Actions and such.
    ix.chat.Register("itw", {
        OnChatAdd = function(self, speaker, text)
            chat.AddText(ix.config.Get("chatColor"), "* "..text)
        end,
        CanHear = WithinRange("chatActionWRange", 75),
        prefix = {"/ItW"},
        description = "Make something around you perform an action (WHISPERING DISTANCE).",
        indicator = "chatPerforming",
        deadCanChat = true,
        font = "ixChatFontWhisper"
    })

    local function CanSay(self, speaker, text)
        local tr = speaker:GetEyeTrace()
        
        if IsValid(tr.Entity) and tr.Entity:IsPlayer()
        and speaker:GetPos():Distance(tr.Entity:GetPos()) < ix.config.Get("chatRange", 280) * .2 then
            tr.Entity.ixChatActionPlayer = speaker
            return true
        end

        return false
    end

    local function CanHear(self, speaker, listener)
        if speaker == listener then return true end

        if listener.ixChatActionPlayer == speaker then
            listener.ixChatActionPlayer = nil
            return true
        end

        return false
    end

    ix.chat.Register("mel", {
        format = "* %s %s",
        GetColor = function() return Color(205, 238, 174) end,
        CanSay = CanSay,
        CanHear = CanHear,
        prefix = {"/MeL"},
        description =  "Perform a physical action (LOOKING AT PLAYER ONLY).",
        indicator = "chatPerforming",
        deadCanChat = true,
        font = "ixChatFontWhisper"
    })

    -- Actions and such.
    ix.chat.Register("itl", {
        OnChatAdd = function(self, speaker, text)
            chat.AddText(ix.config.Get("chatColor"), "* "..text)
        end,
        CanSay = CanSay,
        CanHear = CanHear,
        GetColor = function() return Color(205, 238, 174) end,
        prefix = {"/ItL"},
        description = "Make something around you perform an action (TO LOOKING AT PLAYER).",
        indicator = "chatPerforming",
        deadCanChat = true,
        font = "ixChatFontWhisper"
    })
end
