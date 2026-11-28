--[[--
World-space panels.

A world panel is a short list of rows drawn on a surface in the world (cam.Start3D2D) beside an
entity or a position, square to the player's view. The row under the player's aim is highlighted.
There is no cursor and nothing is drawn on the HUD: the player keeps moving and looking freely.
The panel closes itself when the player looks well away, walks out of reach, dies, is knocked out
or tied, opens a menu, or the anchor is removed. Only one panel is open at a time.

While a panel is open, left click confirms the aimed row, right click closes the panel and the
mouse wheel scrolls a list longer than `maxRows` (the weapon switch is swallowed; see GuardBinds at
the end). A caller adds its own confirm key by calling `panel:Select()`.

	local panel = ix.worldui.Open({
		anchor = entity,                       -- an entity, or `position = Vector(...)` for a spot
		title = "Smelter",                     -- optional
		rows = {
			{label = "Add fuel", detail = "2 kg", icon = Material("icon16/fire.png")},
			{label = "Smelt", enabled = false},  -- shown greyed: can be aimed at, never chosen
			{label = "Ores", heading = true},    -- a section heading: never aimed at or chosen
			{label = "Examine", action = "examine"} -- other fields are kept for the callbacks
		},
		OnSelect = function(panel, row, index)
			print("chose " .. row.label)
		end,
		OnClose = function(panel, reason) end  -- reason: one of ix.worldui.reasons
	})

	panel:SetRows(rows)     -- replace the rows; the aimed row is kept by its label
	panel:GetAimed()        -- index, row of the aimed row, or nil
	panel:Select()          -- confirm the aimed row as a left click does; true if one was chosen
	panel:Scroll(1)         -- move the visible window by rows
	panel:Close()

Other options: `reach` (distance from the eye to the anchor before it closes, default 128),
`lookAway` (degrees the aim may leave both the panel and the anchor, default 50), `maxRows`
(rows shown at once, default 7) and `bKeepOpen` (stay open after a selection).
]]
-- @module ix.worldui

ix.worldui = ix.worldui or {}

local worldui = ix.worldui

--- Why a panel closed, as passed to OnClose.
worldui.reasons = {
	replaced = "replaced", -- another panel was opened
	selected = "selected", -- a row was chosen
	closed = "closed", -- panel:Close() or right click
	lookedAway = "lookedAway",
	reach = "reach", -- walked out of reach
	dead = "dead",
	incapacitated = "incapacitated", -- knocked out, ragdolled or tied
	anchor = "anchor", -- the anchor entity went away
	interrupted = "interrupted" -- a menu or window opened, or the character went away
}

local reasons = worldui.reasons

-- Sizes in panel units. A unit is one pixel of the panel's fonts at 1080p; the fonts are made at
-- the screen's resolution and the panel's world scale follows its distance from the eye, so the
-- panel covers the same part of the view at any resolution and distance.
local layout = {
	minWidth = 260,
	maxWidth = 620,
	padding = 16,
	titleHeight = 54,
	rowHeight = 52,
	iconSize = 26,
	iconGap = 12,
	detailGap = 28,
	arrowHeight = 16,
	radius = 6
}

-- Radians of view per panel unit: a 38 unit row font is about 2.8 degrees tall, about 34 pixels
-- at 720p and 100 at 2160p (glyphs are about two thirds of that).
local ANGLE_PER_UNIT = 0.0013
-- Distance from the eye the panel is drawn at, in world units, nearer than the anchor's surface.
local NEAREST, FARTHEST = 22, 46
local FADE_SPEED = 7 -- alpha per second
local GRACE = 0.3 -- seconds after opening before looking away can close it

-- opaque: drawn in the world pass, even slight transparency lets a bright floor show through strongly
local COLOR_BACK = Color(16, 16, 14, 255)
local COLOR_EDGE = Color(255, 255, 255, 22)
local COLOR_TITLE = Color(236, 230, 214)
local COLOR_TEXT = Color(212, 208, 198)
local COLOR_AIMED_TEXT = Color(255, 252, 244)
local COLOR_DISABLED = Color(120, 118, 112)
local COLOR_DETAIL = Color(156, 152, 142)
local COLOR_AIMED = Color(255, 255, 255, 26)
local COLOR_DIVIDER = Color(255, 255, 255, 18)
local UP = Vector(0, 0, 1)

worldui.drawing = worldui.drawing or {}

local resolution = 1

local function CreateFonts()
	resolution = math.Clamp(ScrH() / 1080, 0.6, 2.5)

	local title = ix.config.Get("font", "Roboto")
	local generic = ix.config.Get("genericFont", "Roboto")

	surface.CreateFont("ixWorldUITitle", {font = title, size = math.Round(40 * resolution), weight = 500, antialias = true, extended = true})
	surface.CreateFont("ixWorldUIRow", {font = generic, size = math.Round(38 * resolution), weight = 600, antialias = true, extended = true})
	surface.CreateFont("ixWorldUIDetail", {font = generic, size = math.Round(30 * resolution), weight = 500, antialias = true, extended = true})
end

CreateFonts()
hook.Add("LoadFonts", "ixWorldUI", CreateFonts)
hook.Add("OnScreenSizeChanged", "ixWorldUI", CreateFonts)

-- Text width in panel units.
local function TextWidth(font, text)
	surface.SetFont(font)

	return (surface.GetTextSize(text)) / resolution
end

-- Shortens text with an ellipsis until it fits `width` units.
local function Fit(font, text, width)
	if (TextWidth(font, text) <= width) then
		return text
	end

	local length = text:utf8len()

	while (length > 1 and TextWidth(font, text:utf8sub(1, length) .. "...") > width) do
		length = length - 1
	end

	return text:utf8sub(1, length) .. "..."
end

-- The view the world was last drawn from (the camera, which is behind the player in third person),
-- taken while the main view is drawn: a render target (a camera screen, a mirror) is skipped.
hook.Add("PostDrawOpaqueRenderables", "ixWorldUIView", function(bDepth, bSkybox)
	if (bDepth or bSkybox or render.GetRenderTarget() != nil) then
		return
	end

	worldui.viewOrigin = EyePos()
	worldui.viewAngles = EyeAngles()
end)

--- Where the player looks from and which way: the eye and aim in first person, the camera in third
-- person, where the mouse turns only the camera while standing still. Returns origin, angles.
function worldui.GetView(client)
	if (client:ShouldDrawLocalPlayer() and worldui.viewOrigin) then
		return worldui.viewOrigin, worldui.viewAngles
	end

	return client:EyePos(), client:GetAimVector():Angle()
end

local PANEL = {}
PANEL.__index = PANEL

--- Opens a world panel, closing the one already open. See the top of this file.
-- @realm client
-- @tab info Anchor, rows, callbacks and options
-- @treturn table The panel
function worldui.Open(info)
	if (!istable(info) or (info.anchor == nil and !isvector(info.position))) then
		error("ix.worldui.Open needs an `anchor` entity or a `position` vector", 2)
	end

	if (worldui.panel) then
		worldui.panel:Close(reasons.replaced)
	end

	local panel = setmetatable({
		info = info,
		anchor = info.anchor,
		position = info.position,
		title = info.title,
		reach = info.reach or 128,
		lookAway = math.cos(math.rad(info.lookAway or 50)),
		maxRows = info.maxRows or 7,
		scroll = 0,
		alpha = 0,
		openedAt = RealTime(),
		bClosing = false
	}, PANEL)

	panel:SetRows(info.rows or {})
	panel:Update(LocalPlayer())

	worldui.panel = panel
	worldui.drawing[#worldui.drawing + 1] = panel

	return panel
end

--- The open panel, or nil.
function worldui.GetOpen()
	return worldui.panel
end

function worldui.IsOpen()
	return worldui.panel != nil
end

--- Closes the open panel, if any.
function worldui.Close(reason)
	if (worldui.panel) then
		worldui.panel:Close(reason or reasons.closed)
	end
end

function PANEL:IsOpen()
	return !self.bClosing
end

function PANEL:GetRows()
	return self.rows
end

--- Replaces the rows. The row that was aimed at stays aimed if a row with its label remains.
function PANEL:SetRows(rows)
	local aimedLabel = self.aimed and self.rows and self.rows[self.aimed] and self.rows[self.aimed].label

	self.rows = rows
	self.lines = {}

	local contentWidth = self.title and TextWidth("ixWorldUITitle", self.title) or 0
	local bIcons = false

	for _, row in ipairs(rows) do
		if (row.icon) then
			bIcons = true
			break
		end
	end

	local iconWidth = bIcons and (layout.iconSize + layout.iconGap) or 0
	local available = layout.maxWidth - layout.padding * 2

	for i, row in ipairs(rows) do
		local font = row.heading and "ixWorldUIDetail" or "ixWorldUIRow"
		local label = tostring(row.label or "")
		local detail = row.detail and tostring(row.detail) or nil
		local detailWidth = detail and math.min(TextWidth("ixWorldUIDetail", detail), available * 0.4) or 0
		local labelSpace = available - (row.heading and 0 or iconWidth) - (detail and detailWidth + layout.detailGap or 0)

		if (detail) then
			detail = Fit("ixWorldUIDetail", detail, detailWidth)
		end

		label = Fit(font, label, labelSpace)

		self.lines[i] = {label = label, detail = detail, font = font}

		contentWidth = math.max(contentWidth, (row.heading and 0 or iconWidth) + TextWidth(font, label) +
			(detail and detailWidth + layout.detailGap or 0))
	end

	if (self.title) then
		self.titleText = Fit("ixWorldUITitle", self.title, available)
	end

	self.iconWidth = iconWidth
	self.width = math.Clamp(contentWidth + layout.padding * 2, layout.minWidth, layout.maxWidth)
	self.visible = math.min(#rows, self.maxRows)
	self.bScrolls = #rows > self.maxRows
	self.rowsTop = layout.padding + (self.title and layout.titleHeight or 0) + (self.bScrolls and layout.arrowHeight or 0)
	self.height = self.rowsTop + self.visible * layout.rowHeight + (self.bScrolls and layout.arrowHeight or 0) +
		layout.padding
	self.scroll = math.Clamp(self.scroll or 0, 0, math.max(#rows - self.visible, 0))
	self.aimed = nil

	if (aimedLabel) then
		for i, row in ipairs(rows) do
			if (row.label == aimedLabel) then
				self.aimed = i
				break
			end
		end
	end
end

--- Moves the visible window by `delta` rows.
function PANEL:Scroll(delta)
	local limit = math.max(#self.rows - self.visible, 0)
	local scroll = math.Clamp(self.scroll + delta, 0, limit)

	if (scroll != self.scroll) then
		self.scroll = scroll
		surface.PlaySound("ui/buttonrollover.wav")
	end
end

--- The aimed row: index, row. Nil when the aim is off the rows, on a heading or the panel closes.
function PANEL:GetAimed()
	if (self.bClosing or !self.aimed) then
		return
	end

	return self.aimed, self.rows[self.aimed]
end

--- The world position of a row's centre, scrolling it into view first. For tests and tools that
-- need to aim at a row the way a player would.
function PANEL:GetRowPos(index)
	if (!self.rows[index] or !self.pos) then
		return
	end

	if (index <= self.scroll) then
		self.scroll = index - 1
	elseif (index > self.scroll + self.visible) then
		self.scroll = index - self.visible
	end

	local x = 0
	local y = self.rowsTop + (index - self.scroll - 0.5) * layout.rowHeight - self.height * 0.5

	return self.pos + self.xAxis * (x * self.scale * resolution) + self.yAxis * (y * self.scale * resolution)
end

--- Confirms the aimed row. Headings, disabled rows and an aim off the rows choose nothing.
-- @treturn bool Whether a row was chosen
function PANEL:Select()
	local index, row = self:GetAimed()

	if (!row or row.heading or row.enabled == false) then
		return false
	end

	if (self.info.OnSelect) then
		self.info.OnSelect(self, row, index)
	end

	if (!self.info.bKeepOpen) then
		self:Close(reasons.selected)
	end

	return true
end

function PANEL:Close(reason)
	if (self.bClosing) then
		return
	end

	self.bClosing = true
	self.closeReason = reason or reasons.closed
	self.aimed = nil

	if (worldui.panel == self) then
		worldui.panel = nil
	end

	if (self.info.OnClose) then
		self.info.OnClose(self, self.closeReason)
	end
end

function PANEL:GetAnchorPos()
	if (self.anchor != nil) then
		if (IsValid(self.anchor)) then
			self.lastCenter = self.anchor:WorldSpaceCenter()
		end

		return self.lastCenter
	end

	return self.position
end

-- Places the panel for this frame: beside the anchor as seen from the eye, nearer than the
-- anchor's surface so it never sinks into the model or the wall behind it, square to the view.
function PANEL:Update(client)
	local center = self:GetAnchorPos()

	if (!center) then
		return
	end

	local eye, view = worldui.GetView(client)
	local toAnchor = center - eye
	local distance = math.max(toAnchor:Length(), 1)
	local direction = toAnchor / distance
	local right = direction:Cross(UP)

	if (right:LengthSqr() < 0.01) then
		right = view:Right()
	end

	right:Normalize()

	local radius = IsValid(self.anchor) and math.min(self.anchor:BoundingRadius(), 48) or 4
	local panelDistance = math.Clamp(distance - radius, NEAREST, FARTHEST)
	local scale = panelDistance * ANGLE_PER_UNIT / resolution
	local halfWidth = self.width * resolution * scale * 0.5
	-- the anchor's half size, capped so a large anchor close up does not push the panel off the
	-- screen, then the panel's own half width and a small gap
	local angle = math.min(math.atan(radius / distance), math.rad(16)) + math.atan(halfWidth / panelDistance) +
		math.rad(3)
	local panelDirection = direction * math.cos(angle) + right * math.sin(angle)
	-- square to the view rather than turned toward the eye: a panel off to the side and below the
	-- eye line otherwise shows its text slanted
	local forward, xAxis = view:Forward(), view:Right()

	self.pos = eye + panelDirection * panelDistance
	self.normal = -forward
	self.xAxis = xAxis
	self.yAxis = -view:Up() -- down the panel
	self.angles = xAxis:AngleEx(self.normal)
	self.scale = scale
end

-- Where the aim crosses the panel, in panel units from its top left, or nil.
function PANEL:AimPoint(client)
	if (!self.pos) then
		return
	end

	local origin, view = worldui.GetView(client)
	local aim = view:Forward()
	local denominator = aim:Dot(self.normal)

	if (denominator > -0.0001) then
		return
	end

	local distance = (self.pos - origin):Dot(self.normal) / denominator

	if (distance <= 0) then
		return
	end

	local offset = origin + aim * distance - self.pos
	local unit = self.scale * resolution

	return offset:Dot(self.xAxis) / unit + self.width * 0.5, offset:Dot(self.yAxis) / unit + self.height * 0.5
end

function PANEL:UpdateAim(client)
	local x, y = self:AimPoint(client)
	local aimed

	if (x and x >= 0 and x <= self.width and y >= self.rowsTop and y < self.rowsTop + self.visible * layout.rowHeight) then
		local index = self.scroll + math.floor((y - self.rowsTop) / layout.rowHeight) + 1
		local row = self.rows[index]

		if (row and !row.heading) then
			aimed = index
		end
	end

	self.aimed = aimed
end

-- The reason the panel should close now, or nil.
function PANEL:ShouldClose(client)
	if (self.anchor != nil and !IsValid(self.anchor)) then
		return reasons.anchor
	end

	if (!client:Alive()) then
		return reasons.dead
	end

	if (IsValid(Entity(client:GetLocalVar("ragdoll", 0))) or client:IsRestricted()) then
		return reasons.incapacitated
	end

	if (!client:GetCharacter() or (IsValid(ix.gui.characterMenu) and !ix.gui.characterMenu:IsClosing()) or
		(IsValid(ix.gui.menu) and !ix.gui.menu.bClosing) or vgui.CursorVisible() or gui.IsGameUIVisible()) then
		return reasons.interrupted
	end

	-- reach is measured from the body, looking away from the view
	local eye = client:EyePos()
	local nearest = IsValid(self.anchor) and self.anchor:NearestPoint(eye) or self:GetAnchorPos()

	if (nearest and eye:DistToSqr(nearest) > self.reach * self.reach) then
		return reasons.reach
	end

	if (RealTime() - self.openedAt > GRACE) then
		local origin, view = worldui.GetView(client)
		local aim = view:Forward()
		local toPanel = (self.pos - origin):GetNormalized()
		local toAnchor = (self:GetAnchorPos() - origin):GetNormalized()

		if (aim:Dot(toPanel) < self.lookAway and aim:Dot(toAnchor) < self.lookAway) then
			return reasons.lookedAway
		end
	end
end

hook.Add("Think", "ixWorldUI", function()
	local drawing = worldui.drawing

	if (#drawing == 0) then
		return
	end

	local client = LocalPlayer()

	if (!IsValid(client)) then
		return
	end

	local step = RealFrameTime() * FADE_SPEED

	for i = #drawing, 1, -1 do
		local panel = drawing[i]

		if (!panel.bClosing) then
			local reason = panel:ShouldClose(client)

			if (reason) then
				panel:Close(reason)
			end
		end

		panel:Update(client)

		if (panel.bClosing) then
			panel.alpha = math.max(panel.alpha - step, 0)

			if (panel.alpha <= 0) then
				table.remove(drawing, i)
			end
		else
			panel.alpha = math.min(panel.alpha + step, 1)
			panel:UpdateAim(client)
		end
	end
end)

local function DrawArrow(x, y, size, bUp)
	local half = size * 0.5

	draw.NoTexture()
	surface.SetDrawColor(COLOR_DETAIL)

	if (bUp) then
		surface.DrawPoly({{x = x, y = y - half}, {x = x + size, y = y + half}, {x = x - size, y = y + half}})
	else
		surface.DrawPoly({{x = x - size, y = y - half}, {x = x + size, y = y - half}, {x = x, y = y + half}})
	end
end

function PANEL:Draw()
	local r = resolution
	local width, height = self.width * r, self.height * r
	local left, top = -width * 0.5, -height * 0.5
	local padding = layout.padding * r
	local rowHeight = layout.rowHeight * r

	draw.RoundedBox(layout.radius * r, left, top, width, height, COLOR_BACK)
	surface.SetDrawColor(COLOR_EDGE)
	surface.DrawOutlinedRect(left, top, width, height, math.max(math.Round(r), 1))

	if (self.titleText) then
		local titleBottom = top + padding + layout.titleHeight * r

		draw.SimpleText(self.titleText, "ixWorldUITitle", left + padding, titleBottom - layout.titleHeight * r * 0.5 - 2 * r,
			COLOR_TITLE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		surface.SetDrawColor(COLOR_DIVIDER)
		surface.DrawRect(left + padding, titleBottom - 4 * r, width - padding * 2, math.max(math.Round(r), 1))
	end

	local rowsTop = top + self.rowsTop * r
	local accent = ix.config.Get("color")

	for i = 1, self.visible do
		local index = self.scroll + i
		local row, line = self.rows[index], self.lines[index]

		if (!row) then
			break
		end

		local y = rowsTop + (i - 1) * rowHeight
		local middle = y + rowHeight * 0.5
		local bEnabled = row.enabled != false
		local bAimed = self.aimed == index
		local x = left + padding

		if (row.heading) then
			draw.SimpleText(line.label:utf8upper(), line.font, x, middle + 4 * r, COLOR_DETAIL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		else
			if (bAimed) then
				surface.SetDrawColor(bEnabled and COLOR_AIMED or COLOR_DIVIDER)
				surface.DrawRect(left + padding * 0.5, y + 2 * r, width - padding, rowHeight - 4 * r)

				if (bEnabled) then
					surface.SetDrawColor(accent.r, accent.g, accent.b, 220)
					surface.DrawRect(left + padding * 0.5, y + 2 * r, 4 * r, rowHeight - 4 * r)
				end
			end

			if (row.icon) then
				local size = layout.iconSize * r

				surface.SetMaterial(row.icon)
				surface.SetDrawColor(255, 255, 255, bEnabled and 230 or 90)
				surface.DrawTexturedRect(x, middle - size * 0.5, size, size)
			end

			local color = !bEnabled and COLOR_DISABLED or (bAimed and COLOR_AIMED_TEXT or COLOR_TEXT)

			draw.SimpleText(line.label, line.font, x + self.iconWidth * r, middle, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

			if (line.detail) then
				draw.SimpleText(line.detail, "ixWorldUIDetail", left + width - padding, middle, COLOR_DETAIL,
					TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
		end
	end

	if (self.bScrolls) then
		local arrow = layout.arrowHeight * r * 0.5

		if (self.scroll > 0) then
			DrawArrow(0, rowsTop - arrow, arrow, true)
		end

		if (self.scroll < #self.rows - self.visible) then
			DrawArrow(0, rowsTop + self.visible * rowHeight + arrow, arrow, false)
		end
	end
end

hook.Add("PostDrawTranslucentRenderables", "ixWorldUI", function(bDepth, bSkybox)
	local drawing = worldui.drawing

	if (bDepth or bSkybox or #drawing == 0) then
		return
	end

	for i = 1, #drawing do
		local panel = drawing[i]

		if (panel.pos and panel.alpha > 0) then
			cam.Start3D2D(panel.pos, panel.angles, panel.scale)
				-- drawn over everything: it is nearer than the anchor's surface anyway, and must not be
				-- hidden by a wall the anchor stands against or the viewmodel
				cam.IgnoreZ(true)
				surface.SetAlphaMultiplier(panel.alpha)
					panel:Draw()
				surface.SetAlphaMultiplier(1)
				cam.IgnoreZ(false)
			cam.End3D2D()
		end
	end
end)

--- Binds the open panel answers before anything else: the wheel scrolls, left click confirms the
-- aimed row and right click closes. Returns nil for binds it leaves alone.
function worldui.PlayerBindPress(client, bind, bPressed)
	local panel = worldui.panel

	if (!panel or !bPressed) then
		return
	end

	if (bind:find("invnext", 1, true)) then
		panel:Scroll(1)
		return true
	elseif (bind:find("invprev", 1, true)) then
		panel:Scroll(-1)
		return true
	elseif (bind:find("+attack2", 1, true)) then
		panel:Close(reasons.closed)
		return true
	elseif (bind:find("+attack", 1, true)) then
		panel:Select()
		return true
	end
end

-- Helix runs plugin hooks in no fixed order, and its weapon selector takes the wheel and attack
-- binds for itself. So that an open panel gets those binds whatever the order, every other plugin's
-- PlayerBindPress is wrapped to skip a bind the panel wants. `owner` is the plugin whose own
-- PlayerBindPress calls worldui.PlayerBindPress. Run again after plugins (re)load, since that
-- rebuilds Helix's hook cache.
worldui.guardedBinds = worldui.guardedBinds or setmetatable({}, {__mode = "k"})

local function WantsBind(bind, bPressed)
	return worldui.panel != nil and bPressed and (bind:find("invnext", 1, true) or bind:find("invprev", 1, true) or
		bind:find("+attack", 1, true)) != nil
end

function worldui.GuardBinds(owner)
	local cache = HOOKS_CACHE and HOOKS_CACHE.PlayerBindPress

	if (!cache) then
		return
	end

	for plugin, callback in pairs(cache) do
		if (plugin != owner and !worldui.guardedBinds[callback]) then
			local guarded = function(self, client, bind, bPressed, ...)
				if (WantsBind(bind, bPressed)) then
					return
				end

				return callback(self, client, bind, bPressed, ...)
			end

			worldui.guardedBinds[guarded] = true
			cache[plugin] = guarded
		end
	end
end
