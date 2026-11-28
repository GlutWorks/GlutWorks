local PLUGIN = PLUGIN

-- The focus outline: a thin additive rim. Three passes keep it visible on a bright floor; a dim
-- colour with fewer passes vanished there.
PLUGIN.highlightColor = Color(240, 232, 210)
PLUGIN.highlightPasses = 3

-- Sounds for a timed action: a quiet shuffle as it starts, a soft settle when it is done, and a scuff
-- when it is broken off, so the two endings feel different.
PLUGIN.actionSounds = {
	start = {"npc/combine_soldier/gear1.wav", "npc/combine_soldier/gear3.wav", "npc/combine_soldier/gear5.wav"},
	startVolume = 0.22,
	complete = {"physics/cardboard/cardboard_box_impact_soft1.wav", "physics/cardboard/cardboard_box_impact_soft2.wav"},
	completeVolume = 0.35,
	cancel = {"npc/zombie/foot_slide1.wav", "npc/zombie/foot_slide2.wav", "npc/zombie/foot_slide3.wav"},
	cancelVolume = 0.3
}

-- Options kept at the end of the list, before Examine: ones that take the thing away.
PLUGIN.lastOptions = {
	["Pick Up"] = true
}

local traceResult = {}
-- solid, as Helix's use trace and the server's check: grates and bars block a use
local traceData = {output = traceResult, mask = MASK_SOLID}
local focusList = {}

--- Whether the local player can use things now: alive, with a character, on their feet, untied, out
-- of a vehicle and with no menu or window open.
function PLUGIN:CanInteract(client)
	if (!IsValid(client) or !client:Alive() or !client:GetCharacter() or client:IsRestricted() or client:InVehicle()) then
		return false
	end

	if (IsValid(Entity(client:GetLocalVar("ragdoll", 0))) or client:GetViewEntity() != client) then
		return false
	end

	if ((IsValid(ix.gui.characterMenu) and !ix.gui.characterMenu:IsClosing()) or
		(IsValid(ix.gui.menu) and !ix.gui.menu.bClosing) or vgui.CursorVisible()) then
		return false
	end

	return true
end

--- Whether an entity takes part in the interaction grammar: anything with an entity menu or a tooltip,
-- players, player ragdolls, scavengeable props and the usable classes in sh_plugin.lua. Doors and
-- plain props are left to the engine.
function PLUGIN:IsInteractive(entity)
	if (!IsValid(entity) or entity:IsWorld()) then
		return false
	end

	if (entity.bInteractive != nil) then
		return entity.bInteractive
	end

	if (entity:IsPlayer()) then
		return entity:Alive() and entity:GetCharacter() != nil and !entity:GetNoDraw()
	end

	if (entity:IsRagdoll()) then
		return entity:GetNetVar("player") != nil or entity:GetNetVar("isDeadPlayer") == true
	end

	return isfunction(entity.GetEntityMenu) or entity.PopulateEntityInfo == true or
		isfunction(entity.OnPopulateEntityInfo) or entity.IsScavengeable == true or
		self.usableClasses[entity:GetClass()] == true
end

--- The obvious action an entity runs on the client, from its `ENT:GetInteractionTap(client)`: a label
-- and a function, or nil when it has none right now.
function PLUGIN:GetLocalTap(entity)
	if (isfunction(entity.GetInteractionTap)) then
		local label, callback = entity:GetInteractionTap(LocalPlayer())

		if (isstring(label) and isfunction(callback)) then
			return label, callback
		end
	end
end

--- Whether tapping Use on `entity` does its obvious action (its local tap, or its Use on the server),
-- rather than opening its options.
function PLUGIN:HasTapAction(entity)
	if (self:GetLocalTap(entity)) then
		return true
	end

	if (entity.interactionTap != nil) then
		return entity.interactionTap
	end

	if (entity:IsPlayer()) then
		-- untying is the only thing Use does to a player
		return entity:IsRestricted()
	end

	if (entity:IsRagdoll()) then
		-- a corpse is searched only when items drop into it
		return self:IsDeceased(entity) and ix.config.Get("dropItemsOnDeath", false)
	end

	if (entity:GetClass() == "ix_item") then
		return true
	end

	-- Helix refuses Use for anything else with an entity menu (GM:PlayerUse); ore nodes and
	-- scavengeable props are broken with a tool, not used
	if (isfunction(entity.GetEntityMenu) or entity.IsScavengeable or
		scripted_ents.IsBasedOn(entity:GetClass(), "ix_orenode") or entity:GetClass() == "ix_orenode") then
		return false
	end

	return true
end

-- The name of the obvious action, as the first row of the options.
function PLUGIN:GetTapLabel(entity)
	local class = entity:GetClass()

	if (class == "ix_item" or class == "ix_money") then
		return L("interactTake")
	elseif (class == "ix_container" or class == "ix_shipment") then
		return L("interactOpen")
	elseif (class == "ix_vendor") then
		return L("interactTalk")
	elseif (entity:IsRagdoll()) then
		return L("interactSearch")
	elseif (entity:IsPlayer()) then
		return L("interactUntie")
	end

	return L("interactUse")
end

--- The usable thing under the aim within reach, found this frame. Nil when there is none.
function PLUGIN:GetFocus()
	return self.focus
end

-- One line trace a frame, reusing its tables, along the view (ix.worldui.GetView): in third person
-- that is the camera's line, which Helix's third person turns the eyes toward. The thing must still
-- be within reach of the player's own eyes, as the server checks.
function PLUGIN:FindFocus(client)
	if (!self:CanInteract(client)) then
		return
	end

	local origin, angles = ix.worldui.GetView(client)
	local eye = client:EyePos()

	traceData.start = origin
	traceData.endpos = origin + angles:Forward() * (self.reach + origin:Distance(eye))
	traceData.filter = client

	util.TraceLine(traceData)

	local entity = traceResult.Entity

	if (self:IsInteractive(entity) and eye:DistToSqr(entity:NearestPoint(eye)) <= self.reach * self.reach) then
		return entity
	end
end

--- The rows Helix and every plugin would have put in this entity's look-at tooltip, top to bottom, as
-- {id, text}. Built in a tooltip panel that is never shown, through the same calls Helix makes.
function PLUGIN:GetTooltipRows(entity)
	local tooltip = vgui.Create("ixTooltip")
	tooltip:SetVisible(false)

	local owner = entity:GetNetVar("player")

	-- a player ragdoll describes its player, as Helix's tooltip did
	if (IsValid(owner) and owner:IsPlayer()) then
		tooltip:SetEntity(owner)
		tooltip.entity = entity
	else
		tooltip:SetEntity(entity)
	end

	local rows = {}

	for _, v in ipairs(tooltip:GetChildren()) do
		-- other panels hold no text, and the "icon" row is the container lock glyph
		if (v.IsMinimal and v.id != "icon") then
			local text = v:GetText()

			if (text and text != "") then
				rows[#rows + 1] = {id = v.id, text = text, order = v:GetZPos()}
			end
		end
	end

	-- the tooltip's own Remove waits for a closing animation
	FindMetaTable("Panel").Remove(tooltip)

	table.SortByMember(rows, "order", true)

	return rows
end

--- Describes an entity in words, as Examine prints it.
function PLUGIN:DescribeEntity(entity)
	local rows = self:GetTooltipRows(entity)
	local info = {extra = {}}

	if (entity:IsRagdoll()) then
		info.bDeceased = self:IsDeceased(entity)

		local owner = entity:GetNetVar("player")
		info.bUnconscious = !info.bDeceased and IsValid(owner) and owner:IsPlayer()
	end

	if (entity:GetClass() == "ix_container" and entity.GetLocked) then
		info.bLocked = entity:GetLocked()
	end

	-- something with no tooltip at all is at least named
	if (#rows == 0 and !entity:IsRagdoll() and !entity:IsPlayer()) then
		local name = entity.PrintName

		if (isstring(name) and name != "") then
			rows[1] = {id = "name", text = L(name)}
		end
	end

	if (entity.IsScavengeable) then
		info.extra[#info.extra + 1] = L("examineScavenge")
	end

	return self:ComposeExamine(rows, info)
end

--- Whether the tooltip would have shown for this entity: the player alive and on their feet, and
-- every ShouldPopulateEntityInfo rule (this plugin's own refusal, which only hides the tooltip panel,
-- is set aside while asking).
function PLUGIN:CanExamine(entity)
	local client = LocalPlayer()

	if (!client:Alive() or IsValid(Entity(client:GetLocalVar("ragdoll", 0)))) then
		return false
	end

	if (!IsValid(entity) or entity:IsWorld()) then
		return true
	end

	self.bAskingTooltip = true
	local bShould = hook.Run("ShouldPopulateEntityInfo", entity)
	self.bAskingTooltip = nil

	return bShould != false
end

--- Prints the Examine line for an entity, or says there is nothing to examine. Prints nothing while
-- dead or knocked out.
function PLUGIN:Examine(entity)
	if (!self:CanExamine(entity)) then
		return
	end

	local text = IsValid(entity) and !entity:IsWorld() and self:DescribeEntity(entity) or L("examineNothing")

	ix.chat.Send(LocalPlayer(), "examine", text)

	return text
end

-- What /Examine looks at: whatever is under the aim (the view's line, as for the focus), as far
-- from the eyes as the tooltip reached.
function PLUGIN:GetExamineTarget(client)
	local origin, angles = ix.worldui.GetView(client)

	return util.TraceLine({
		start = origin,
		endpos = origin + angles:Forward() * (self.examineReach + origin:Distance(client:EyePos())),
		filter = client,
		mask = MASK_SHOT
	}).Entity
end

net.Receive("ixInteractionExamine", function()
	local client = LocalPlayer()

	if (IsValid(client)) then
		PLUGIN:Examine(PLUGIN:GetExamineTarget(client))
	end
end)

-- The server refused a tap, or it changed nothing: say so with the broken-off sound, no text.
net.Receive("ixInteractionRefused", function()
	if (IsValid(LocalPlayer())) then
		PLUGIN:PlayActionSound("cancel")
	end
end)

function PLUGIN:RequestUse(entity)
	net.Start("ixInteractionUse")
		net.WriteEntity(entity)
	net.SendToServer()
end

--- The option rows for an entity: its obvious action, then what its entity menu offers (or `options`
-- when given, as ix.menu.Open passes them) sorted by name with PLUGIN.lastOptions last, then Examine.
function PLUGIN:BuildRows(entity, options)
	local rows = {}
	local tapLabel

	if (!options) then
		local label, callback = self:GetLocalTap(entity)

		if (label) then
			rows[1] = {label = label, action = "tap", callback = callback}
			tapLabel = label
		elseif (self:HasTapAction(entity)) then
			rows[1] = {label = self:GetTapLabel(entity), action = "use"}
		end

		options = isfunction(entity.GetEntityMenu) and entity:GetEntityMenu(LocalPlayer())
		options = istable(options) and options or {}

		hook.Run("PopulateInteractionOptions", entity, LocalPlayer(), options)
	end

	if (istable(options)) then
		local last = {}

		for label, callback in SortedPairs(options) do
			-- the tap row already does this one
			if (label == tapLabel) then
				continue
			end

			local row = {label = label, action = "option", callback = callback}

			if (self.lastOptions[label]) then
				last[#last + 1] = row
			else
				rows[#rows + 1] = row
			end
		end

		for _, row in ipairs(last) do
			rows[#rows + 1] = row
		end
	end

	rows[#rows + 1] = {label = L("interactExamine"), action = "examine"}

	return rows
end

--- Runs a chosen row. Entity menu options go to the server exactly as Helix's menu button sent them.
function PLUGIN:Choose(entity, row)
	if (!IsValid(entity)) then
		return
	end

	if (row.action == "use") then
		self:RequestUse(entity)
	elseif (row.action == "tap") then
		row.callback()
	elseif (row.action == "examine") then
		self:Examine(entity)
	elseif (row.action == "option") then
		local status = true

		if (isfunction(row.callback)) then
			status = row.callback()
		end

		if (status != false) then
			ix.menu.NetworkChoice(entity, row.label, status)
		end
	end
end

local function Labels(rows)
	local labels = {}

	for i, row in ipairs(rows) do
		labels[i] = row.label
	end

	return table.concat(labels, "\n")
end

--- Opens the options for an entity as a world panel beside it. `options` is a fixed set from
-- ix.menu.Open; otherwise the rows are rebuilt while the panel is open, so they follow the entity
-- and the player's inventory.
function PLUGIN:OpenOptions(entity, options)
	if (!IsValid(entity)) then
		return
	end

	local rows = self:BuildRows(entity, options)
	local title

	for _, row in ipairs(self:GetTooltipRows(entity)) do
		if (row.id == "name" and row.text != L("unknown")) then
			title = row.text
			break
		end
	end

	local panel = ix.worldui.Open({
		anchor = entity,
		title = title,
		rows = rows,
		reach = self.reach + 40,
		OnSelect = function(_, row)
			self:Choose(entity, row)
		end
	})

	panel.interactionEntity = entity
	panel.interactionOptions = options
	panel.interactionLabels = Labels(rows)
	panel.interactionRefresh = RealTime() + 0.25

	self.panel = panel

	return panel
end

-- The panel this plugin opened, while it is open.
function PLUGIN:GetPanel()
	local panel = self.panel

	if (panel and panel:IsOpen()) then
		return panel
	end
end

function PLUGIN:Tap(entity)
	local _, callback = self:GetLocalTap(entity)

	if (callback) then
		callback()
		return
	end

	if (self:HasTapAction(entity)) then
		self:RequestUse(entity)
		return
	end

	local rows = self:BuildRows(entity)

	-- with nothing to do but look, tapping looks
	if (#rows == 1) then
		self:Examine(entity)
	else
		self:OpenOptions(entity)
	end
end

-- The button a +use press came from: the one PlayerBindPress names, else the first bound key.
local function UseButton(code)
	if (isnumber(code) and code > 0) then
		return code
	end

	local binding = input.LookupBinding("+use")
	code = binding and input.GetKeyCode(binding)

	return (code and code > 0) and code or KEY_E
end

-- Use on something interactive is answered here instead of reaching the server as +use: the obvious
-- action waits for the release, so holding can open the options instead. Anything else (doors,
-- plain props, vehicles) gets +use as before.
function PLUGIN:PlayerBindPress(client, bind, bPressed, code)
	if (!bPressed or !bind:find("+use", 1, true)) then
		return
	end

	-- key repeat while held
	if (self.hold) then
		return true
	end

	-- a panel opened by a tap stays open (this plugin's, or a station's or a vendor's): Use chooses
	-- the aimed row, or closes it on none
	local panel = ix.worldui.GetOpen()

	if (panel) then
		-- a greyed row, a heading or the title under the aim keeps the panel; only an aim off it closes it
		if (!panel:Select() and !panel:IsAimedAt()) then
			panel:Close()
		end

		return true
	end

	local entity = self.focus

	if (!IsValid(entity)) then
		return
	end

	-- a wheel notch cannot be held: it is a tap
	if (code == MOUSE_WHEEL_UP or code == MOUSE_WHEEL_DOWN) then
		self:Tap(entity)
		return true
	end

	-- each press follows its own button, so a second key bound to +use holds as well as the first
	self.hold = {entity = entity, start = RealTime(), button = UseButton(code)}

	return true
end

function PLUGIN:UpdateHold()
	local hold = self.hold

	if (!hold) then
		return
	end

	if (!input.IsButtonDown(hold.button)) then
		self.hold = nil

		if (hold.bOpened) then
			-- release on an option chooses it; anywhere else cancels
			local panel = self:GetPanel()

			if (panel and !panel:Select()) then
				panel:Close()
			end
		elseif (IsValid(hold.entity) and hold.entity == self.focus) then
			self:Tap(hold.entity)
		end
	elseif (!hold.bOpened and RealTime() - hold.start >= self.holdTime) then
		hold.bOpened = true

		if (IsValid(hold.entity) and hold.entity == self.focus) then
			self:OpenOptions(hold.entity)
		end
	end
end

function PLUGIN:RefreshPanel()
	local panel = self:GetPanel()

	if (!panel or panel.interactionOptions or RealTime() < panel.interactionRefresh) then
		return
	end

	panel.interactionRefresh = RealTime() + 0.25

	local entity = panel.interactionEntity

	if (!IsValid(entity)) then
		return
	end

	local rows = self:BuildRows(entity)
	local labels = Labels(rows)

	if (labels != panel.interactionLabels) then
		panel.interactionLabels = labels
		panel:SetRows(rows)
	end
end

-- A timed action (SetAction, often with DoStaredAction) used to draw a bar. Now it is felt: the
-- immersion plugin's concentrating feel and a sound when it starts, ends and is broken off.
local action = {bActive = false, finish = 0}

function PLUGIN:PlayActionSound(kind)
	local sounds = self.actionSounds
	local list = sounds[kind]

	LocalPlayer():EmitSound(list[math.random(#list)], 0, math.random(95, 105), sounds[kind .. "Volume"], CHAN_STATIC)
end

function PLUGIN:UpdateAction()
	local finish = ix.bar.actionEnd or 0
	local now = CurTime()
	local immersion = ix.plugin.Get("immersion")
	local client = LocalPlayer()

	if (finish > now) then
		if (!action.bActive) then
			action.bActive = true

			if (client:Alive()) then
				PLUGIN:PlayActionSound("start")
			end

			if (immersion) then
				immersion:SetConcentrating(true)
			end
		end

		action.finish = finish
	elseif (action.bActive) then
		action.bActive = false

		-- a reset before the end is a cancel; reaching the end (or a reset right at it) is completion
		local bBroken = finish == 0 and now < action.finish - 0.1

		if (client:Alive()) then
			PLUGIN:PlayActionSound(bBroken and "cancel" or "complete")
		end

		if (immersion) then
			immersion:SetConcentrating(false, bBroken)
		end
	end
end

function PLUGIN:Think()
	local client = LocalPlayer()

	if (!IsValid(client)) then
		return
	end

	self.focus = self:FindFocus(client)

	if (self.hold and !self:CanInteract(client)) then
		self.hold = nil
	end

	self:UpdateHold()
	self:RefreshPanel()
	self:UpdateAction()
end

function PLUGIN:PreDrawHalos()
	local entity = self.focus

	if (!IsValid(entity) or !ix.config.Get("interactionHighlight", true)) then
		return
	end

	focusList[1] = entity
	halo.Add(focusList, self.highlightColor, 1, 1, self.highlightPasses, true, false)
end

-- No look-at tooltip: Examine reads the same rows in words instead.
function PLUGIN:ShouldPopulateEntityInfo(entity)
	if (!self.bAskingTooltip) then
		return false
	end
end

-- Helix opens its menu from here on releasing +use when +use reaches it (a held IN_USE from a
-- script); the world panel answers instead.
function PLUGIN:ShowEntityMenu(entity)
	self:OpenOptions(entity)

	return true
end

-- Helix's own drawing of a timed action and of the hold-to-pick-up ring: nothing on screen now.
ix.bar.DrawAction = function() end
ix.hud.DrawItemPickup = function() end

-- Anything else that opens Helix's entity menu gets the world panel instead; the radial menu never
-- appears.
ix.menu.ixOpen = ix.menu.ixOpen or ix.menu.Open
ix.menu.ixIsOpen = ix.menu.ixIsOpen or ix.menu.IsOpen

function ix.menu.Open(options, entity)
	if (!IsValid(entity) or !istable(options)) then
		return false
	end

	return PLUGIN:OpenOptions(entity, options) != nil
end

function ix.menu.IsOpen()
	return PLUGIN:GetPanel() != nil or ix.menu.ixIsOpen()
end

if (IsValid(ix.gui.entityInfo)) then
	ix.gui.entityInfo:Remove()
end
