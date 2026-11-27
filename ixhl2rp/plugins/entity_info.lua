
local PLUGIN = PLUGIN

PLUGIN.name = "Physical Entity Info"
PLUGIN.author = "wowm0d"
PLUGIN.description = "Changes entity hover info drawing."
PLUGIN.license = [[
Copyright 2020 wowm0d
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]
PLUGIN.readme = [[
Makes entity hover info a physical point in the world to draw from.

Support for this plugin can be found here: https://discord.gg/mntpDMU
]]

if (CLIENT) then
	local handledClasses = {
		["ix_container"] = true,
		["ix_money"] = true,
		["ix_vendor"] = true,
		["ix_shipment"] = true
	}

	local drawInfo = {}

	local function IsHandled(entity)
		if (handledClasses[entity:GetClass()] or entity:IsPlayer()) then
			return true
		end

		return entity:IsRagdoll() and (entity:GetNetVar("player") != nil or entity:GetNetVar("isDeadPlayer") == true)
	end

	-- Helix keeps running the tooltip panel, so every populate hook and visibility check still applies; it is only
	-- stopped from painting.
	local function HideTooltip(tooltip)
		if (tooltip.bWorldInfo) then
			return
		end

		tooltip.bWorldInfo = true
		tooltip.Paint = function() end

		for _, v in ipairs(tooltip:GetChildren()) do
			v:SetPaintedManually(true)
		end
	end

	-- The text rows that Helix, the schema and plugins put in the tooltip, top to bottom.
	local function GetRows(tooltip)
		local rows = {}

		for _, v in ipairs(tooltip:GetChildren()) do
			-- other panels hold no text, and the "icon" row is the container lock glyph, which is drawn separately
			if (v.IsMinimal and v.id != "icon") then
				local text = v:GetText()

				if (text and text != "") then
					rows[#rows + 1] = {id = v.id, text = text, color = v.backgroundColor, order = v:GetZPos()}
				end
			end
		end

		table.sort(rows, function(a, b)
			return a.order < b.order
		end)

		return rows
	end

	local function MarkDeceased(ragdoll, rows)
		local owner = ragdoll:GetNetVar("player")

		if (!ragdoll:GetNetVar("isDeadPlayer") and !(IsValid(owner) and owner:IsPlayer() and !owner:Alive())) then
			return
		end

		-- injuries are read from the owner, who may have respawned since
		for i = #rows, 1, -1 do
			if (rows[i].id == "injureText") then
				table.remove(rows, i)
			end
		end

		local position = (rows[1] and rows[1].id == "name") and 2 or 1

		table.insert(rows, position, {id = "deceased", text = L("Seems deceased"), color = Color(83, 0, 0)})
	end

	local function UpdateFromTooltip()
		local tooltip = ix.gui.entityInfo

		if (!IsValid(tooltip)) then
			return
		end

		local entity = tooltip:GetEntity()

		if (!IsValid(entity) or !IsHandled(entity)) then
			return
		end

		HideTooltip(tooltip)

		-- a corpse whose owner has left gets a tooltip that closes itself at once, even while still being looked at
		if (tooltip.bClosing and !(entity:IsRagdoll() and !IsValid(entity:GetNetVar("player")))) then
			return
		end

		local rows = GetRows(tooltip)

		if (entity:IsRagdoll()) then
			MarkDeceased(entity, rows)
		end

		local info = drawInfo[entity] or {alpha = 0}
		info.time = CurTime()
		info.rows = rows

		drawInfo[entity] = info
	end

	local function DrawInfo(entity, info)
		local genericHeight = draw.GetFontHeight("ixGenericFont")
		local descHeight = draw.GetFontHeight("ixItemDescFont")
		local bone = entity:LookupBone("ValveBiped.Bip01_Spine4")
		local position = bone and entity:GetBonePosition(bone) or entity:LocalToWorld(entity:OBBCenter())
		local screenPosition = position:ToScreen()
		local x, y = screenPosition.x, screenPosition.y - genericHeight / 2
		local alpha = info.alpha * 255

		if (entity:GetClass() == "ix_container") then
			local bLocked = entity:GetLocked()
			local color = bLocked and Color(200, 38, 19) or Color(135, 211, 124)

			ix.util.DrawText(bLocked and "P" or "Q", x, y - draw.GetFontHeight("ixIconsSmall"),
				ColorAlpha(color, info.alpha * 200), 1, 1, "ixIconsSmall")
		end

		for _, row in ipairs(info.rows) do
			if (row.id == "name") then
				ix.util.DrawText(row.text, x, y, ColorAlpha(row.color or ix.config.Get("color"), alpha), 1, 1)
				y = y + descHeight
			else
				local color = ColorAlpha(row.color or color_white, alpha)

				for _, line in ipairs(ix.util.WrapText(row.text, 300, "ixItemDescFont")) do
					ix.util.DrawText(line, x, y, color, 1, 1, "ixItemDescFont")
					y = y + descHeight
				end
			end
		end
	end

	function PLUGIN:HUDPaint()
		UpdateFromTooltip()

		for entity, info in pairs(drawInfo) do
			-- info.time is refreshed on every frame the entity is looked at, so the fade runs on frame time:
			-- in while it is looked at, out once it has not been for half a second.
			local bLooking = CurTime() - info.time < 0.5

			info.alpha = math.Approach(info.alpha, bLooking and 1 or 0, FrameTime() * 4)

			if (!IsValid(entity) or (!bLooking and info.alpha == 0)) then
				drawInfo[entity] = nil
			else
				DrawInfo(entity, info)
			end
		end
	end
end
