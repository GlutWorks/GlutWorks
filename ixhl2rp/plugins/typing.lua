local PLUGIN = PLUGIN

-- Extends Helix's typing indicator (helix/plugins/typing.lua), which shares this ID and loads first into the same
-- table. The word above someone who is typing ("Typing...", "Yelling...") is the one social cue text roleplay
-- cannot do without, and it is in the world, so it stays; it is only made quiet: smaller, dim, with no outline,
-- and fading with distance as before. Who sees it, and when, is Helix's.

PLUGIN.description = "Shows a small, dim word above someone who is typing."

-- Text height (the font is drawn at 0.05 scale, so 64 is about 3 units) and colour at full strength.
PLUGIN.quietFontSize = 64
PLUGIN.quietColor = Color(215, 210, 196)
PLUGIN.quietAlpha = 150

if (CLIENT) then
	function PLUGIN:LoadFonts(font, genericFont)
		surface.CreateFont("ixTypingIndicator", {
			font = genericFont,
			size = self.quietFontSize,
			extended = true,
			weight = 500,
			antialias = true
		})
	end

	-- Helix's drawing loop, with the outline gone and the text smaller and dimmer.
	function PLUGIN:PostDrawTranslucentRenderables()
		local client = LocalPlayer()
		local position = client:GetPos()
		local bAnimation = !ix.option.Get("disableAnimations", false)

		for _, v in player.Iterator() do
			if (v == client or !IsValid(v) or !v:Alive()) then
				continue
			end

			local moveType = v:GetMoveType()

			if ((moveType != MOVETYPE_WALK and moveType != MOVETYPE_NONE) or !v.ixChatClassText or
				!v.ixChatClassRange) then
				continue
			end

			local distance = v:GetPos():DistToSqr(position)
			local range = v.ixChatClassRange

			if (distance >= range) then
				continue
			end

			local fraction = 1

			if (bAnimation) then
				local bComplete = v.ixChatClassTween and v.ixChatClassTween:update(FrameTime())

				if (bComplete and !v.ixChatStarted) then
					v.ixChatClassText = nil
					v.ixChatClassRange = nil

					continue
				end

				fraction = v.ixChatClassAnimation or 0
			end

			local alpha = self.quietAlpha * fraction * (bAnimation and (1 - math.min(distance, range) / range) or 1)

			if (alpha < 1) then
				continue
			end

			local angle = EyeAngles()
			angle:RotateAroundAxis(angle:Forward(), 90)
			angle:RotateAroundAxis(angle:Right(), 90)

			cam.Start3D2D(self:GetTypingIndicatorPosition(v), Angle(0, angle.y, 90), 0.05)
				surface.SetFont("ixTypingIndicator")

				local _, textHeight = surface.GetTextSize(v.ixChatClassText)

				draw.SimpleText(v.ixChatClassText, "ixTypingIndicator", 0, -textHeight * 0.5 * fraction,
					ColorAlpha(self.quietColor, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			cam.End3D2D()
		end
	end
end
