local pad = ix.datapad
local W, H = 1024, 610
local colors = ix.body and ix.body.COLORS or {}
local amber = colors.amber or Color(240, 179, 89)
local bright, faint = Color(255, 218, 148), Color(177, 145, 92)
local ink, grid, glaze = Color(22, 22, 17), Color(83, 70, 43), Color(55, 48, 32)
local harm = colors.harm or Color(255, 111, 92)
local pale = colors.pale or Color(224, 215, 179)
local wet = colors.wet or Color(91, 206, 186)
local cold = colors.cold or Color(145, 203, 245)
local bruise = colors.bruise or Color(199, 155, 221)
local sick = colors.sick or Color(180, 212, 117)
local fonts = {tiny = 15, mono = 19, row = 21, title = 36}
for id, size in pairs(fonts) do
	surface.CreateFont("ixPad" .. id, {font = id == "title" and "Roboto" or "DejaVu Sans Mono",
		size = size, weight = id == "title" and 800 or 550, antialias = true, extended = true})
end

local function box(x, y, w, h, c)
	surface.SetDrawColor(c)
	surface.DrawRect(x, y, w, h)
end
local function line(x, y, x2, y2, c)
	surface.SetDrawColor(c)
	surface.DrawLine(x, y, x2, y2)
end
local function txt(text, x, y, font, color, align)
	draw.SimpleText(text, "ixPad" .. (font or "mono"), x, y, color or amber, align or TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end
local function fit(text, px, font)
	surface.SetFont("ixPad" .. (font or "mono"))
	if (surface.GetTextSize(text) <= px) then return text end
	local n = text:utf8len()
	while (n > 0 and surface.GetTextSize(text:utf8sub(1, n) .. "...") > px) do n = n - 1 end
	return text:utf8sub(1, n) .. "..."
end
local function inside(s, x, y, w, h)
	return s.mx >= x and s.mx < x + w and s.my >= y and s.my < y + h
end
local function hit(s, id, x, y, w, h, click, item, drop)
	local area = {id = id, click = click, item = item, drop = drop, x = x, y = y, w = w, h = h}
	s.hits[#s.hits + 1] = area
	if (inside(s, x, y, w, h)) then
		s.hot = area
		return true
	end
end
local function button(s, label, x, y, w, action, selected)
	local hover = hit(s, label .. x .. y, x, y, w, 29, action)
	box(x, y, w, 29, selected and amber or hover and grid or glaze)
	if (!selected) then line(x, y + 28, x + w, y + 28, hover and bright or grid) end
	txt(label, x + w / 2, y + 14, "tiny", selected and ink or hover and bright or amber, TEXT_ALIGN_CENTER)
end

local function chassis(combine, biomonitor)
	local isCombine = combine or biomonitor
	draw.RoundedBox(24, -30, -30, W + 60, H + 72, Color(24, 26, 24))
	draw.RoundedBox(21, -30, -36, W + 60, H + 72, isCombine and Color(82, 91, 90) or Color(110, 107, 83))
	draw.RoundedBox(18, -27, -33, W + 54, H + 65, isCombine and Color(53, 62, 62) or Color(73, 74, 61))
	draw.RoundedBox(11, -8, -8, W + 16, H + 16, Color(11, 12, 10))
	box(0, 0, W, H, ink)
	for _, x in ipairs({-17, W + 17}) do
		for _, y in ipairs({-21, H + 18}) do
			draw.RoundedBox(5, x - 5, y - 5, 10, 10, Color(36, 37, 31))
			line(x - 3, y + 2, x + 3, y - 2, faint)
		end
	end
	local title = biomonitor and "OVERWATCH   /   BIOMONITOR"
		or combine and "CIVIL PROTECTION   /   FIELD TERMINAL"
		or "CIVIL SUPPLY   /   PORTABLE TERMINAL"
	txt(title, 12, -21, "tiny", Color(207, 205, 174))
	txt("17-C", W - 12, -21, "tiny", Color(207, 205, 174), TEXT_ALIGN_RIGHT)
	for i = 0, 9 do box(W - 124 + i * 12, H + 14, 7, 5, Color(37, 39, 32)) end
	box(9, H + 14, 16, 4, amber)
end

local function itemStatus(item, place, body)
	if (item:GetData("spoiled") or item:GetData("contaminated")) then return "spoiled", sick end
	if (item:GetData("frozen")) then return "frozen", cold end
	local bodyWet = body and tonumber(body.wetness) or 0
	if (item:GetData("wet") or (place.region and bodyWet >= 60 and item:GetData("equip") and (item.outfitCategory or item.wearPart))) then
		return "soaked", wet
	end
	if (ix.wear and ix.wear.IsWearable(item)) then
		local level, word = ix.wear.GetLevel(item)
		if (level >= ix.wear.LEVEL_RUINED) then return L(word), harm end
		if (level >= 3) then return L(word), pale end
	end
	if (item.isWeapon and item.weaponCategory != "melee" and item.weaponCategory != "grenade" and !item:GetData("equip")
		and item:GetData("ammo", 0) == 0) then return "empty", pale end
end

local function placeCue(place)
	if (!place or place.key == "storage" or place.key == "worn" or place.wornRegion) then return nil end
	local delay = pad.GetAccessTime(place)
	if (place.maxKg != nil) then
		return string.format("bag · %.1fs", delay)
	elseif (delay > 0) then
		return string.format("hidden · %.1fs", delay)
	end
	return "quick"
end

local function list(s, groups, x, w, col)
	local external = col == "away"
	local foundIDs = external and s.storage and s.storage.foundIDs or nil
	local rows = {}
	local query = string.lower(s.query)
	for _, place in ipairs(groups) do
		if (foundIDs and (place.concealment or 0) >= pad.HIDDEN_THRESHOLD) then continue end
		local matches = {}
		for _, item in ipairs(place.items) do
			if (foundIDs and !foundIDs[item.id]) then continue end
			if (query == "" or string.find(string.lower(item:GetName() .. " " .. place.name), query, 1, true)) then matches[#matches + 1] = item end
		end
		if (#matches > 0 or (query == "" and (s.mode == "move" or s.pressed or #place.items > 0 or external or place.key == "pockets"))) then
			rows[#rows + 1] = {place = place}
			for _, item in ipairs(matches) do rows[#rows + 1] = {item = item, place = place} end
		end
	end
	local y, step, count = 152, 32, s.storage and 10 or 11
	if (inside(s, x, y - 4, w, count * step + 6)) then s.hoverColumn = col end
	local offset = math.Clamp(s.scroll[col] or 0, 0, math.max(0, #rows - count))
	s.scroll[col] = offset
	if (#rows == 0) then txt(query != "" and "No matching items" or "Empty", x + 12, y + 20, "row", faint) end
	for n = offset + 1, math.min(offset + count, #rows) do
		local r, top = rows[n], y + (n - offset - 1) * step
		local item, place = r.item, r.place
		if (!item) then
			local hot = pad.frisk and (external or s.witness) and pad.frisk.region == place.region
			line(x, top, x + w, top, hot and harm or grid)
			local jig = hot and !ix.option.Get("reduceMotionEffects", false) and math.sin(RealTime() * 26) * 2 or 0
			local cue = !external and placeCue(place) or nil
			txt(fit(string.upper(place.name), w - (cue and 178 or 102), "tiny"), x + 8 + jig, top + 15, "tiny", hot and harm or faint)
			if (cue) then
				txt(cue, x + w - 58, top + 15, "tiny", pad.GetAccessTime(place) > 0 and pale or faint, TEXT_ALIGN_RIGHT)
			end
			txt(place.limit and (place.used .. " / " .. place.limit) or tostring(#place.items), x + w - 8, top + 15, "tiny", faint, TEXT_ALIGN_RIGHT)
			hit(s, col .. place.key, x, top, w, step, nil, nil, external and "storage" or place.key)
		else
			local selected = s.selected == item.id
			local hover = hit(s, col .. item.id, x, top, w, step, function()
				s.selected, s.external, s.mode = item.id, external, nil
			end, item)
			local flag = pad.Contraband(item)
			local red = pad.frisk and ((flag and external) or (s.witness and (flag or (pad.frisk.foundIDs and pad.frisk.foundIDs[item.id]))))
			if (selected or hover) then box(x, top + 1, w, step - 2, selected and (red and harm or amber) or glaze) end
			local body = external and pad.frisk and pad.frisk.body or !external and s.body
			local state, stateColor = itemStatus(item, place, body)
			local color = selected and ink or red and harm or stateColor or amber
			local tag = red and flag and "restricted" or state or flag and "restricted" or item.category == "Medical" and "aid" or (item.restoredThirst or 0) > 0 and "drink" or nil
			local name = item:GetName()
			if (item.stackLimit) then name = name .. "  " .. ix.stack.Format(item, ix.stack.GetQuantity(item)) end
			txt(fit(name, w - (tag and 174 or 80), "row"), x + 12, top + 15, "row", color)
			if (tag) then txt(tag, x + w - 78, top + 15, "tiny", selected and ink or red and harm or stateColor or tag == "aid" and harm or tag == "drink" and pale or faint, TEXT_ALIGN_RIGHT) end
			txt(string.format("%.1f", pad.Weight(item, body and body.wetness)), x + w - 10, top + 15, "mono", color, TEXT_ALIGN_RIGHT)
		end
	end
	if (#rows > count) then
		local thumb = count * step * count / #rows
		box(x + w - 3, y + (count * step - thumb) * offset / (#rows - count), 3, thumb, faint)
	end
end

local hologram = pad.hologram
local function markColor(kind)
	return kind == "Bruise" and bruise or kind == "Poisoned" and sick or harm
end
local PAIRED = {arms = true, legs = true, feet = true}

local function scaled(c, k)
	return Color(c.r * k, c.g * k, c.b * k)
end

-- Where something wrong with a region sits in the body: the spot it was struck while the body
-- remembers it; else the middle of the region, or of each limb of a pair (fainter, since which of
-- the two is not known). Returns the places and how strongly to show them.
local function placesIn(entry, body, region)
	local point = body.points and body.points[region]
	local at = point and hologram.Strike(entry, point.bone, point.at)
	if (at) then return {at}, 1 end
	local places = {}
	for _, side in ipairs(PAIRED[region] and {-1, 1} or {0}) do
		places[#places + 1] = hologram.Middle(entry, region, side)
	end
	return places, PAIRED[region] and 0.6 or 1
end

-- Corner brackets round a part of the figure: what is selected, or where an item is carried.
local function brackets(view, region, c)
	local x, y, x2, y2 = hologram.Box(view, region)
	if (!x) then return end
	x, y, x2, y2 = x - 4, y - 4, x2 + 4, y2 + 4
	local arm = math.min(10, (x2 - x) / 3, (y2 - y) / 3)
	for _, corner in ipairs({{x, y, 1, 1}, {x2, y, -1, 1}, {x, y2, 1, -1}, {x2, y2, -1, -1}}) do
		local cx, cy, dx, dy = corner[1], corner[2], corner[3], corner[4]
		line(cx, cy, cx + arm * dx, cy, c)
		line(cx, cy, cx, cy + arm * dy, c)
	end
end

-- The currently visible conditions on this scan. The existing body snapshot determines
-- which wounds a viewer may see, including during a search.
local function figure(s, rect, body, region, selectPart, subject)
	local view, failed = hologram.View(s, subject, rect)
	if (!view) then
		txt(failed and "NO SCAN" or "SCANNING", rect.x + rect.w / 2, rect.y + rect.h / 2, "tiny", faint, TEXT_ALIGN_CENTER)
		return
	end
	local entry = view.entry
	local wounds = istable(body.wounds) and body.wounds or nil
	local coldLevel = ix.exposure and table.KeyFromValue(ix.exposure.COLD_WORDS, body.temperatureWord)
	-- An observer can infer cold from a shiver, without learning a hidden temperature band.
	coldLevel = coldLevel or (body.shivering and 2 or body.cold and 1 or 0)
	local isThirsty = body.thirsty == true or (isnumber(body.thirst) and body.thirst < 40)
	local frisking = s == pad.screen and pad.frisk and !s.witness
	local searched = pad.frisk and ix.body.IsRegion(pad.frisk.region) and pad.frisk.region == region and region or nil
	local effects = {}
	local previousWounds = view.wounds or {}
	view.wounds = {}
	for _, key in ipairs(ix.body.REGIONS) do
		local wound = wounds and wounds[key]
		local marked = !wound and body.mark and body.mark.part == key
		if (wound) then
			local point = body.points and body.points[key]
			local at = point and hologram.Strike(entry, point.bone, point.at)
			local bone = at and entry.map.index[point.bone]
			local dressed = wound.state == "dressed"
			local previous = previousWounds[key]
			local boundSince
			if (dressed and previous) then
				boundSince = previous.boundSince
				if (!previous.dressed) then boundSince = RealTime() end
			end
			view.wounds[key] = {kind = wound.kind, band = wound.severityWord, dressed = dressed, boundSince = boundSince,
				at = at, side = bone and entry.map.side[bone]}
		elseif (marked) then
			local places, strength = placesIn(entry, body, key)
			for _, at in ipairs(places) do
				effects[#effects + 1] = {kind = "core", pos = at, color = scaled(markColor(body.mark.kind), strength), size = 1.5}
			end
		end
		if (frisking) then
			for _, row in ipairs(pad.frisk.found) do
				if (row.flagged and row.region == key) then
					for _, at in ipairs((placesIn(entry, {}, key))) do
						effects[#effects + 1] = {kind = "core", pos = at, color = harm, size = 1.8}
					end
					break
				end
			end
		end
	end
	if (searched) then effects[#effects + 1] = {kind = "sweep", region = searched, color = harm} end
	view.clothingWord, view.coldLevel = body.clothingWord, coldLevel
	view.effects = effects
	view.shiver = body.shivering and (0.07 * coldLevel) or 0
	if (!hologram.Blit(view)) then
		txt("SCANNING", rect.x + rect.w / 2, rect.y + rect.h / 2, "tiny", faint, TEXT_ALIGN_CENTER)
		return
	end
	local revealed = hologram.RevealLine(view)
	if (!revealed) then
		if (region and !searched and ix.body.IsRegion(region)) then brackets(view, region, bright) end
		if (isThirsty) then
			-- Beside the head, not on it: a dry, cracked tick.
			local _, top, x2, bottom = hologram.Box(view, "head")
			if (x2) then
				local x, y = x2 + 6, top + (bottom - top) * 0.7
				line(x, y, x + 5, y + 2, pale)
				line(x + 5, y + 2, x + 9, y - 1, pale)
			end
		end
	end
	if (revealed) then line(rect.x + 8, revealed, rect.x + rect.w - 8, revealed, bright) end
	-- Pointing picks the region under the cursor; a drag across turns the body instead. With the
	-- cursor on it or near it, it holds still, so a thin limb can be clicked; it turns again a
	-- moment after the cursor leaves.
	local pointed = inside(s, rect.x, rect.y, rect.w, rect.h)
	if (inside(s, rect.x - 30, rect.y - 30, rect.w + 60, rect.h + 60)) then s.holoHeld = math.max(s.holoHeld or 0, RealTime()) end
	local over = selectPart and pointed and hologram.Pick(view, s.mx, s.my) or nil
	local drag = s.holoDrag
	if (s.pressed and s.pressed.id == "hologram") then
		if (!drag) then
			drag = {x = s.mx, yaw = s.holoYaw or 0}
			s.holoDrag = drag
		end
		if (math.abs(s.mx - drag.x) > 4) then drag.moved = true end
		if (drag.moved) then
			s.holoYaw = drag.yaw - (s.mx - drag.x) * 0.6
			s.holoHeld = RealTime()
		end
	elseif (drag) then
		s.holoDrag = nil
	end
	hit(s, "hologram", rect.x, rect.y, rect.w, rect.h, function()
		-- Picked again where the button came up, not where the cursor was a frame ago.
		local picked = selectPart and !(s.holoDrag and s.holoDrag.moved) and hologram.Pick(view, s.mx, s.my)
		if (picked) then s.part = picked end
	end)
	if (selectPart and over) then s.hoverPart = over end
end

local solid = Material("models/debug/debugwhite")
local scanRT = GetRenderTarget("ixDatapadSpecimen", 256, 256)
-- Added onto the screen as light, like the body's hologram: its black ground adds nothing, so only
-- the item shows, with no square behind it. (Not $translucent: that blends by the target's alpha,
-- which the model leaves low, dimming the item.)
local scanMat = CreateMaterial("ixDatapadScanLight", "UnlitGeneric", {["$basetexture"] = scanRT:GetName(), ["$additive"] = "1", ["$vertexcolor"] = "1"})
local wire = Material("models/wireframe")
hook.Add("PreRender", "ixDatapadScan", function()
	local s = pad.screen
	if (!s or s.storage or s.tab != "Carry" or !s.selected or s.mode or (s.nextScan or 0) > RealTime()) then return end
	s.nextScan = RealTime() + 0.09
	local _, item = pad.Locate(s.own or {}, s.selected)
	if (!item) then return end
	local model = item:GetModel()
	if (s.model != model) then
		if (IsValid(s.scan)) then s.scan:Remove() end
		s.model = model
		s.scan = ClientsideModel(model, RENDERGROUP_OTHER)
		if (IsValid(s.scan)) then s.scan:SetNoDraw(true) end
	end
	local ent = s.scan
	if (!IsValid(ent)) then return end
	local mins, maxs = ent:GetRenderBounds()
	local center = (mins + maxs) * 0.5
	local dist = math.max(3, (maxs - mins):Length() * 1.55)
	local yaw = ix.option.Get("reduceMotionEffects", false) and 35 or RealTime() * 12 % 360
	local dir = Angle(18, yaw, 0):Forward()
	ent:SetSkin(item:GetSkin() or 0)
	render.PushRenderTarget(scanRT)
	render.Clear(0, 0, 0, 255, true, true)
	cam.Start3D(center - dir * dist, dir:Angle(), 38, 0, 0, 256, 256, 0.1, dist * 3)
		render.SuppressEngineLighting(true)
		render.ResetModelLighting(0.35, 0.35, 0.35)
		render.SetModelLighting(4, 0.95, 0.95, 0.95)
		render.MaterialOverride(solid)
		render.SetColorModulation(0.96, 0.70, 0.36)
		ent:DrawModel()
		render.MaterialOverride(wire)
		render.SetBlend(0.23)
		ent:DrawModel()
		render.SetBlend(1)
		render.MaterialOverride(nil)
		render.SetColorModulation(1, 1, 1)
		render.ResetModelLighting(1, 1, 1)
		render.SuppressEngineLighting(false)
	cam.End3D()
	render.PopRenderTarget()
end)

local function action(s, item, key, fn, sub)
	item.player = LocalPlayer()
	local click = sub and sub.OnClick or fn.OnClick
	local send = !click or click(item) != false
	local sound = sub and sub.sound or fn.sound
	if (sound) then surface.PlaySound(sound) end
	item.player = nil
	if (send) then
		-- Send the inventory this item was picked from, not item.invID: when a consumed
		-- item's ID is recycled into another inventory, the client's copy can keep the
		-- old invID and the server would look for the item in the wrong inventory.
		local place = pad.Locate(s.own or {}, item.id) or pad.Locate(s.away or {}, item.id)
		local invID = place and place.inv and place.inv:GetID() or item.invID
		net.Start("ixInventoryAction")
			net.WriteString(key)
			net.WriteUInt(item.id, 32)
			net.WriteUInt(invID, 32)
			net.WriteTable(sub and sub.data or {})
		net.SendToServer()
	end
	s.mode = nil
end

local function choices(s, item, from)
	local options = {}
	if (s.mode == "move") then
		for _, place in ipairs(s.own) do
			if (place != from and pad.Fits(place, item)) then
				local cue = placeCue(place)
				local label = cue and (place.name .. "   [" .. cue .. "]") or place.name
				options[#options + 1] = {label, function() pad.SendMove(item.id, place.key) s.mode = nil end}
			end
		end
	elseif (s.mode == "combine") then
		for _, groups in ipairs({s.own, s.away}) do
			for _, place in ipairs(groups) do
				for _, other in ipairs(place.items) do
					if (other.id != item.id and (!item.functions.combine.OnCanRun or item.functions.combine.OnCanRun(item, {other.id}) != false)) then
						options[#options + 1] = {other:GetName() .. " / " .. place.name, function()
							action(s, item, "combine", item.functions.combine, {data = {other.id}})
						end}
					end
				end
			end
		end
	else
		item.player = LocalPlayer()
		for key, fn in SortedPairs(item.functions) do
			if (key == "take" or (key == "View" and item.isBag) or (key != "combine" and fn.OnCanRun and fn.OnCanRun(item) == false)) then continue end
			if (key == "combine") then
				options[#options + 1] = {"Combine with...", function() s.mode = "combine" end}
			elseif (fn.isMulti and fn.multiOptions) then
				local subs = isfunction(fn.multiOptions) and fn.multiOptions(item, LocalPlayer()) or fn.multiOptions
				for _, sub in ipairs(subs) do
					options[#options + 1] = {L(sub.name or key), function() action(s, item, key, fn, sub) end}
				end
			else
				options[#options + 1] = {L(fn.name or key), function() action(s, item, key, fn) end}
			end
		end
		item.player = nil
	end
	return options
end

local function readout(s, item, width)
	local tooltip = vgui.Create("ixTooltip")
	tooltip:SetVisible(false)
	ix.hud.PopulateItemTooltip(tooltip, item)
	local rows = {}
	for _, row in ipairs(tooltip:GetChildren()) do
		if (row.IsMinimal and row.id != "name" and row:GetText() != "") then
			rows[#rows + 1] = {order = row:GetZPos(), text = row:GetText()}
		end
	end
	FindMetaTable("Panel").Remove(tooltip)
	table.SortByMember(rows, "order", true)
	s.lines = {}
	for _, row in ipairs(rows) do
		for _, paragraph in ipairs(string.Explode("\n", row.text)) do
			table.Add(s.lines, ix.util.WrapText(paragraph, width, "ixPadmono"))
		end
	end
	s.scroll.options, s.mode = 0, "readout"
end

local function detail(s, x, w)
	local from, item = pad.Locate(s.external and s.away or s.own, s.selected)
	if (!item) then
		txt("No item selected", x + 15, 190, "row", faint)
		return
	end
	local detailBody = s.external and pad.frisk and pad.frisk.body or !s.external and s.body
	local cue = !s.external and placeCue(from) or nil
	local meta = from.name .. (cue and (" · " .. cue) or "") .. "   /   " .. string.format("%.2f kg", pad.Weight(item, detailBody and detailBody.wetness))
	txt(fit(item:GetName(), w - 32, "title"), x + 16, 179, "title", bright)
	txt(fit(meta, w - 32, "mono"), x + 17, 212, "mono", faint)
	if (s.mode == "readout") then
		s.hoverColumn = inside(s, x, 232, w, 260) and "options" or s.hoverColumn
		local offset = math.Clamp(s.scroll.options or 0, 0, math.max(0, #s.lines - 8))
		for i = offset + 1, math.min(offset + 8, #s.lines) do txt(s.lines[i], x+16, 253+(i-offset-1)*27) end
		button(s, "Back", x+16, 474, 90, function() s.mode = nil end)
		return
	end
	if (s.mode) then
		if (!s.choices or s.choices.mode != s.mode or s.choices.id != item.id) then
			s.choices = {mode = s.mode, id = item.id, options = choices(s, item, from)}
			s.scroll.options = 0
		end
		local options = s.choices.options
		txt(s.mode == "move" and "AVAILABLE PLACES" or s.mode == "combine" and "COMPATIBLE ITEMS" or "ITEM ACTIONS", x+16, 259, "tiny", faint)
		if (#options == 0) then txt("None available", x+16, 311, "row", faint) end
		local offset = math.Clamp(s.scroll.options or 0, 0, math.max(#options - 5, 0))
		if (inside(s, x, 245, w, 245)) then s.hoverColumn = "options" end
		for i = offset + 1, math.min(offset + 5, #options) do
			button(s, fit(options[i][1], w-52, "tiny"), x+16, 278+(i-offset-1)*35, w-32, options[i][2])
		end
		button(s, "Back", x+16, 474, 90, function() s.mode = nil end)
		return
	end
	s.choices = nil
	local center = x + w * 0.67
	for i = 0, 8 do line(x+17, 237+i*24, x+w-16, 237+i*24, glaze) end
	for i = -2, 2 do line(center+i*50, 237, center+i*50, 430, glaze) end
	figure(s, {x = x + w * 0.23 - 95, y = 236, w = 190, h = 190}, s.body, from.region, false, LocalPlayer())
	if (IsValid(s.scan) and s.model == item:GetModel()) then
		-- About as bright as the body's hologram beside it.
		surface.SetDrawColor(190, 190, 190)
		surface.SetMaterial(scanMat)
		surface.DrawTexturedRect(center-86, 246, 172, 172)
	end
	line(x+17, 237, x+55, 237, amber)
	line(x+17, 237, x+17, 250, amber)
	line(x+w-55, 429, x+w-17, 429, amber)
	txt("MODEL SCAN", x+23, 418, "tiny", faint)
	txt(string.format("%06d", item.id), x+w-24, 251, "tiny", faint, TEXT_ALIGN_RIGHT)
	local desc = item:GetDescription() or ""
	txt(fit(desc:gsub("%s+", " "), w-32, "tiny"), x+16, 450, "tiny", faint)
	button(s, "Readout", x+w-100, 476, 84, function() readout(s, item, w-32) end)
	if (!s.witness) then
		button(s, "Actions", x+16, 476, 104, function() s.mode = "actions" end)
		button(s, "Move to... [M]", x+129, 476, 145, function() s.mode = "move" end)
	end
end

local function landing(s, item)
	if (!item) then return end
	local groups = s.external and s.own or s.away
	local preference = s.external and s.char:GetData("carryPrefs", {})[item.category]
	local plan = pad.PlanTransfer(groups, item, preference)
	if (!plan) then return end
	local names = {}
	for _, merge in ipairs(plan.merges) do
		if (!table.HasValue(names, merge.place.name)) then names[#names + 1] = merge.place.name end
	end
	if (plan.place and !table.HasValue(names, plan.place.name)) then names[#names + 1] = plan.place.name end
	return table.concat(names, " + ")
end

local function carry(s)
	local split = s.storage and 506 or 554
	line(split, 109, split, 519, grid)
	txt(s.witness and "YOUR CARRY   /   UNDER SEARCH" or "CARRIED EQUIPMENT", 28, 123, "tiny", s.witness and harm or faint)
	txt("KG", split-20, 123, "tiny", faint, TEXT_ALIGN_RIGHT)
	list(s, s.own, 22, split-39, "own")
	if (s.storage and !s.mode) then
		txt(fit(string.upper(s.storage.name), 351, "mono"), split+19, 124, "mono", bright)
		txt("KG", W-32, 124, "tiny", faint, TEXT_ALIGN_RIGHT)
		list(s, s.away, split+12, W-split-33, "away")
		local _, item = pad.Locate(s.external and s.away or s.own, s.selected)
		local dest = landing(s, item)
		if (item) then
			for i = 29, 977, 13 do line(i, 482, i+7, 482, grid) end
			txt(fit(dest and ("To " .. dest .. "   /   " .. string.format("%.1f kg after transfer", pad.Total(s.own) + (s.external and 1 or -1)*pad.TransferWeight(item))) or "No room for this item", 580, "tiny"), 30, 501, "tiny", dest and faint or harm)
			button(s, s.external and "Take [T]" or "Store [T]", 650, 487, 131, function() pad.Transfer(s, false) end)
			button(s, "All of kind [Shift T]", 790, 487, 206, function() pad.Transfer(s, true) end)
		end
	else
		txt(s.mode == "move" and "STOWAGE" or "ITEM INSPECTION", split+16, 123, "tiny", faint)
		detail(s, split+3, W-split-17)
	end
	local kg = pad.Total(s.own)
	txt(string.format("LOAD   %.1f KG   /   %s", kg, string.upper(pad.LoadBand(kg))), 27, 546, "mono", bright)
	local w = 194
	box(380, 542, w, 7, glaze)
	box(380, 542, math.min(kg/30,1)*w, 7, amber)
	for _, cut in ipairs({12,22}) do box(380+w*cut/30,538,1,15,faint) end
	if (s.storage and s.storage.money != nil) then
		button(s, "Store " .. ix.currency.Get(s.char:GetMoney()), 601, 531, 192, function() pad.Money(s, false) end)
		button(s, "Take " .. ix.currency.Get(s.storage.money), 801, 531, 195, function() pad.Money(s, true) end)
	else
		txt(fit(ix.currency.Get(s.char:GetMoney()), 250, "mono"), W-28, 546, "mono", faint, TEXT_ALIGN_RIGHT)
	end
end

local function formatDressing(dressing)
	if (!dressing or !isstring(dressing.placeName)) then
		return "None carried", harm
	end
	local delay = tonumber(dressing.accessTime) or 0
	if (delay > 0) then
		return string.format("Bandage / %s (%.1fs)", dressing.placeName, delay), pale
	end
	return "Bandage / " .. dressing.placeName, amber
end

local function bodyScreen(s, frisk)
	local f = pad.frisk
	local body = frisk and f.body or s.body
	local isBio = body.biomonitor == true and istable(body.biometrics)
	local isObservable = body.observableOnly == true
	local subject = frisk and IsValid(f.target) and f.target or LocalPlayer()
	txt(frisk and "SUBJECT SCAN" or (isBio and "BIOMEDICAL SCAN" or "BODY SCAN"), 28, 124, "tiny", faint)
	for i = 0, 16 do
		local y = 153+i*21
		line(51, y, i%4 == 0 and 71 or 60, y, grid)
		if (i%4 == 0) then line(72, y, 408, y, glaze) end
	end
	s.hoverPart = nil
	local highlight = frisk and f.region or s.lastHoverPart or s.part
	figure(s, {x = 51, y = 140, w = 372, h = 372}, body, highlight, !frisk, subject)
	s.lastHoverPart = !frisk and s.hoverPart or nil
	local region = frisk and f.region or s.hoverPart or s.part
	local regionLabel = ix.body and ix.body.REGION_LABELS[region] or region
	txt(string.upper(regionLabel), 399, 516, "tiny", bright, TEXT_ALIGN_RIGHT)
	line(430, 110, 430, 526, grid)

	local rightHeader
	if (frisk) then
		local modeLabel = f.mode == "hasty" and "QUICK SEARCH" or "THOROUGH SEARCH"
		rightHeader = modeLabel .. "   /   " .. (isBio and "BIOMEDICAL TELEMETRY" or "OBSERVABLE SIGNS")
	elseif (isBio) then
		rightHeader = "BIOMEDICAL TELEMETRY"
	else
		rightHeader = "CONDITION"
	end
	txt(rightHeader, 454, 124, "tiny", faint)

	local activeWounds, hasOpenWound = {}, false
	if (istable(body.wounds)) then
		for _, reg in ipairs(ix.body and ix.body.REGIONS or {"head", "chest", "waist", "arms", "legs", "feet"}) do
			local w = body.wounds[reg]
			if (istable(w)) then
				activeWounds[#activeWounds + 1] = {region = reg, wound = w}
				if (w.state == "open") then hasOpenWound = true end
			end
		end
	end

	local dressing = !frisk and ((ix.body and ix.body.FindDressing and ix.body.FindDressing(LocalPlayer(), s.own)) or body.dressing) or nil
	if (!dressing and !frisk and s.storage and ix.body and ix.body.FindDressing) then
		dressing = ix.body.FindDressing(LocalPlayer(), s.away)
	end
	local readings = {}

	if (isBio) then
		local bio = body.biometrics
		readings[#readings + 1] = {"Vitality", string.format("%d%%", bio.vitality), bio.vitality < 40 and harm or bio.vitality < 75 and pale or amber}
		readings[#readings + 1] = {"Pulse", string.format("%d BPM", bio.pulse), bio.pulse >= 120 and harm or bio.pulse >= 95 and pale or amber}
		readings[#readings + 1] = {"Oxygen", string.format("%d%%", bio.oxygen), bio.oxygen < 35 and pale or amber}
		readings[#readings + 1] = {"Core Temp", string.format("%.1f C", bio.coreTemp), amber}
		readings[#readings + 1] = {"Suit Seal", bio.suitSeal, bio.suitSeal == "BREACHED" and harm or amber}
		if (body.thirstWord) then
			readings[#readings + 1] = {"Hydration", body.thirstWord, body.thirsty and pale or amber}
			readings[#readings + 1] = {"Appetite", body.hungerWord, body.hungry and pale or amber}
		end
	elseif (isObservable) then
		local mark = body.mark
		local woundText = hasOpenWound and "Open bleeding"
			or #activeWounds > 0 and "Bandaged"
			or mark and (mark.kind .. " / " .. mark.part)
			or "None visible"
		local woundCol = hasOpenWound and harm
			or #activeWounds > 0 and amber
			or (mark and markColor(mark.kind))
			or amber
		local clothWord = body.clothingWord or "Dry"
		readings[#readings + 1] = {"Wounds", woundText, woundCol}
		readings[#readings + 1] = {"Clothing", clothWord, (clothWord == "Soaked" or clothWord == "Damp") and wet or amber}
		if (body.shivering) then readings[#readings + 1] = {"Posture", "Shivering", cold} end
		if (body.limping) then readings[#readings + 1] = {"Gait", "Limping", harm} end
		if (body.armInjured) then readings[#readings + 1] = {"Arms", "Favouring arm", harm} end
		if (body.breathingWord) then readings[#readings + 1] = {"Breathing", body.breathingWord, pale} end
	else
		local feeling = body.healthWord or (hasOpenWound and "Wounded" or #activeWounds > 0 and "Recovering" or "Steady")
		local feelingCol = (hasOpenWound or feeling == "Hurting" or feeling == "Badly hurt" or feeling == "Barely standing") and harm
			or (feeling == "Sore" and pale)
			or amber
		local breathWord = body.breathingWord or "Even"
		local clothWord = body.clothingWord or "Dry"
		readings[#readings + 1] = {"Feeling", feeling, feelingCol}
		readings[#readings + 1] = {"Breathing", breathWord, breathWord != "Even" and pale or amber}
		readings[#readings + 1] = {"Clothing", clothWord, (clothWord == "Soaked" or clothWord == "Damp") and wet or amber}
		if (body.thirstWord) then
			readings[#readings + 1] = {"Hydration", body.thirstWord, body.thirsty and pale or amber}
			readings[#readings + 1] = {"Appetite", body.hungerWord, body.hungry and pale or amber}
		end
		local tempWord = body.temperatureWord or body.temperature
		if (isstring(tempWord) and tempWord != "") then
			local label = tempWord:sub(1, 1):upper() .. tempWord:sub(2)
			readings[#readings + 1] = {"Temperature", label, body.cold and cold or body.hot and harm or amber}
		end
	end

	if (!frisk and hasOpenWound) then
		local dressText, dressCol = formatDressing(dressing)
		readings[#readings + 1] = {"Dressing", dressText, dressCol}
	end

	local compact = !frisk and (#activeWounds > 0 or #readings >= 6)
	local step = compact and (#readings >= 7 and 20 or 22) or 28
	local startY = compact and 138 or 146
	for i,r in ipairs(readings) do
		local top = startY + (i - 1) * step
		txt(r[1], 454, top + step * 0.45, "mono", faint)
		txt(fit(r[2], 395, compact and "mono" or "row"), 992, top + step * 0.45, compact and "mono" or "row", r[3] or amber, TEXT_ALIGN_RIGHT)
		line(454, top + step - 1, 994, top + step - 1, glaze)
	end
	local y = startY + #readings * step + (compact and 12 or 20)
	if (frisk) then
		txt(region == "complete" and "Search complete" or ("Searching " .. (f.label or region)), 454, y, "row", bright)
		box(454, y+19, 539, 4, glaze)
		box(454, y+19, 539*math.Clamp((CurTime()-f.start)/math.max(f.duration or 1, 0.01),0,1), 4, harm)
		local count = math.max(1, math.floor((511-y-38)/26))
		local offset = math.Clamp(s.scroll.found or 0, 0, math.max(0,#f.found-count))
		if (inside(s, 450, y, 545, 518-y)) then s.hoverColumn = "found" end
		for i = offset+1, math.min(#f.found,offset+count) do
			local r = f.found[i]
			txt(fit(r.name .. "  /  " .. r.place, 510, "mono"), 454, y+47+(i-offset-1)*26, "mono", r.flagged and harm or amber)
		end
		if (#f.found == 0) then txt("Nothing found yet", 454, y+52, "mono", faint) end
	else
		local selectedWound = istable(body.wounds) and body.wounds[region] or nil
		if (#activeWounds > 0) then
			local regionPanelH = selectedWound and 150 or 104
			local maxWoundsEnd = 556 - regionPanelH - 10
			local rowStep = 22
			local maxVisible = math.max(1, math.floor((maxWoundsEnd - (y + 14)) / rowStep))
			local visible = math.min(#activeWounds, maxVisible)
			txt("ACTIVE WOUNDS", 454, y, "tiny", faint)
			local listTop = y + 14
			if (inside(s, 450, listTop, 545, visible * rowStep)) then s.hoverColumn = "wounds" end
			local offset = math.Clamp(s.scroll.wounds or 0, 0, math.max(0, #activeWounds - visible))
			s.scroll.wounds = offset
			for i = offset + 1, math.min(#activeWounds, offset + visible) do
				local entry = activeWounds[i]
				local w = entry.wound
				local top = listTop + (i - offset - 1) * rowStep
				local isSelected = entry.region == region
				local hover = hit(s, "wound_" .. entry.region, 454, top, 540, rowStep, function() s.part = entry.region end)
				if (isSelected or hover) then box(454, top + 1, 540, rowStep - 2, glaze) end
				local wRegion = ix.body and ix.body.GetRegionLabel(entry.region) or entry.region
				local wKind = ix.body and ix.body.GetWoundKindLabel(w.kind) or tostring(w.kind)
				local wDetail = (isBio and isnumber(w.severity)) and (math.Round(w.severity) .. "%")
					or w.severityWord or (ix.body and ix.body.GetWoundSeverityWord(w.severity)) or ""
				local stateText = w.state == "dressed" and "Bound (healing)" or "Open"
				local stateCol = w.state == "dressed" and amber or harm
				txt(fit(wRegion .. "  /  " .. wKind .. " (" .. wDetail .. ")", 345, "mono"), 460, top + 11, "mono", isSelected and bright or amber)
				txt(stateText, 990, top + 11, "tiny", stateCol, TEXT_ALIGN_RIGHT)
				line(454, top + rowStep - 1, 994, top + rowStep - 1, glaze)
			end
			y = listTop + visible * rowStep + 14
		end

		txt("EQUIPMENT AT " .. string.upper(regionLabel), 454, y, "tiny", faint)
		local garmentNames = {}
		if (ix.body) then
			for _, item in ipairs(ix.body.GetCoveringGarments(LocalPlayer(), region)) do
				garmentNames[#garmentNames + 1] = item:GetName()
			end
		end
		local pocketNames, keys, jumpNames = {}, {}, {}
		for _, g in ipairs(s.own) do
			if (g.region == region) then
				keys[g.key] = true
				jumpNames[#jumpNames + 1] = g.name
				if (!g.wornRegion and g.key != "worn") then
					pocketNames[#pocketNames + 1] = g.name
				end
			end
		end
		local rowY = y + 14
		local rowH = selectedWound and 22 or 26
		txt("Garments", 454, rowY + rowH * 0.45, "mono", faint)
		txt(fit(#garmentNames > 0 and table.concat(garmentNames, " / ") or "Uncovered", 420, "mono"), 992, rowY + rowH * 0.45, "mono", #garmentNames > 0 and amber or faint, TEXT_ALIGN_RIGHT)
		line(454, rowY + rowH - 1, 994, rowY + rowH - 1, glaze)
		rowY = rowY + rowH
		txt("Pockets", 454, rowY + rowH * 0.45, "mono", faint)
		txt(fit(#pocketNames > 0 and table.concat(pocketNames, " / ") or "No stowage here", 420, "mono"), 992, rowY + rowH * 0.45, "mono", #pocketNames > 0 and amber or faint, TEXT_ALIGN_RIGHT)
		line(454, rowY + rowH - 1, 994, rowY + rowH - 1, glaze)
		rowY = rowY + rowH
		local bandageItem = dressing and dressing.item or nil
		if (selectedWound) then
			local wKind = ix.body and ix.body.GetWoundKindLabel(selectedWound.kind) or tostring(selectedWound.kind)
			local wDetail = (isBio and isnumber(selectedWound.severity)) and (math.Round(selectedWound.severity) .. "%")
				or selectedWound.severityWord or (ix.body and ix.body.GetWoundSeverityWord(selectedWound.severity)) or ""
			local stateText = selectedWound.state == "dressed" and "Bound (healing)" or "Open"
			local stateCol = selectedWound.state == "dressed" and amber or harm
			txt("Wound", 454, rowY + rowH * 0.45, "mono", faint)
			txt(fit(wKind .. " (" .. wDetail .. ")  /  " .. stateText, 430, "mono"), 992, rowY + rowH * 0.45, "mono", stateCol, TEXT_ALIGN_RIGHT)
			line(454, rowY + rowH - 1, 994, rowY + rowH - 1, glaze)
			rowY = rowY + rowH
			local dressText, dressCol = formatDressing(dressing)
			txt("Dressing", 454, rowY + rowH * 0.45, "mono", faint)
			txt(fit(dressText, 430, "mono"), 992, rowY + rowH * 0.45, "mono", dressCol, TEXT_ALIGN_RIGHT)
			line(454, rowY + rowH - 1, 994, rowY + rowH - 1, glaze)
			rowY = rowY + rowH
		end
		local btnX = 454
		local btnY = rowY + 8
		if (#jumpNames > 0) then
			button(s, "Open pockets", btnX, btnY, 158, function()
				pad.Tab(s, "Carry")
				s.query = pocketNames[1] or jumpNames[1]
				for _, g in ipairs(s.own) do
					if (keys[g.key] and g.items[1]) then s.query, s.selected, s.external = g.name, g.items[1].id, false break end
				end
			end)
			btnX = btnX + 168
		end
		if (selectedWound and selectedWound.state == "open" and bandageItem and bandageItem.functions and bandageItem.functions.Apply) then
			button(s, "Bind wound", btnX, btnY, 146, function()
				action(s, bandageItem, "Apply", bandageItem.functions.Apply, {data = {region = region}})
			end)
		end
	end
end

local function drawScreen(s)
	s.hot, s.hoverColumn, s.hits = nil, nil, {}
	local client = LocalPlayer()
	local isBio = ix.body and isfunction(ix.body.HasBiomonitor) and ix.body.HasBiomonitor(client)
	chassis(client:IsCombine(), isBio)
	txt(isBio and "BIOMONITOR" or "FIELD TERMINAL", 26, 34, "tiny", faint)
	txt(s.tab == "Body" and "Body" or s.tab == "Frisk" and "Frisk" or "Carry", 24, 71, "title", bright)
	local id = s.char:GetData("cid") or s.char:GetID()
	txt("UNIT 17-C    /    " .. tostring(id), W-27, 33, "tiny", faint, TEXT_ALIGN_RIGHT)
	if (s.own and s.body) then
		if (!s.witness) then
			if (!pad.frisk or s.storage) then button(s, "Carry", 188, 57, 87, function() pad.Tab(s,"Carry") end, s.tab=="Carry") end
			if (!pad.frisk) then button(s, "Body", 281,57,87,function() pad.Tab(s,"Body") end,s.tab=="Body")
			else button(s,"Frisk",281,57,87,function() pad.Tab(s,"Frisk") end,s.tab=="Frisk") end
		end
		if (s.tab == "Carry") then
			button(s, IsValid(s.entry) and ("Filter  " .. s.query .. "_") or s.query != "" and fit(s.query,164,"tiny") or "Filter items [F]", 584,57,192,function() pad.Search(s) end)
		end
		if (!s.witness) then button(s,"Tab menu",785,57,106,pad.Menu) end
		button(s,"Close",900,57,96,pad.Close)
		line(24, 101, 997, 101, grid)
		if (s.tab == "Carry") then carry(s) else bodyScreen(s, s.tab == "Frisk" and pad.frisk) end
		line(24, 568, 997, 568, grid)
		local rummaging = client:GetNetVar("datapadRummaging")
		local status = s.witness and ("SEARCH  /  " .. string.upper(pad.frisk.label or pad.frisk.region))
			or rummaging and ("REACHING INTO  " .. string.upper(rummaging) .. "...")
			or pad.receipt and pad.receipt.char == s.char and ("Filed   " .. pad.receipt.name .. "  /  " .. pad.receipt.place)
			or s.tab == "Body" and "Select a body part to inspect its equipment" or "Personal equipment register"
		txt(fit(status, 696,"tiny"), 26, 589,"tiny",(s.witness and harm) or (rummaging and bright) or faint)
		txt(os.date("%H:%M") .. "    /    LINK ACTIVE", 996,589,"tiny",faint,TEXT_ALIGN_RIGHT)
	end
end

local function pointer(s)
	local p = s.plane
	if (!p) then return end
	local mx, my = gui.MousePos()
	local point = util.IntersectRayWithPlane(p.eye, gui.ScreenToVector(mx, my), p.pos, p.normal)
	s.mx, s.my = -1, -1
	if (point) then s.mx, s.my = (point-p.pos):Dot(p.right)/p.scale, (point-p.pos):Dot(p.down)/p.scale end
end

function pad.HitAt(s)
	pointer(s)
	for i = #s.hits, 1, -1 do
		local a = s.hits[i]
		if (inside(s, a.x, a.y, a.w, a.h)) then return a end
	end
end

hook.Add("PostDrawTranslucentRenderables", "ixDatapadDisplay", function(depth, sky)
	local s = pad.screen
	if (!s or depth or sky or render.GetRenderTarget() != nil) then return end
	local view, eye = EyeAngles(), EyePos()
	local dist = 19
	local scale = dist * math.tan(math.rad(LocalPlayer():GetFOV() / 2)) * 1.89 / W
	-- Source's FOV is horizontal at 4:3. Bound the device by both axes for narrow or wide displays.
	scale = scale * math.min(1, (ScrW()/ScrH()) / (4/3))
	local axis = Angle(view.p+3,view.y-2,view.r-1)
	local center = eye+view:Forward()*dist-view:Up()*(0.6+math.max(0,1-(RealTime()-s.started)*4)*4)
	local right, down, normal = axis:Right(), -axis:Up(), -axis:Forward()
	local pos = center-right*W*scale*0.5-down*H*scale*0.5
	s.plane = {eye = eye, pos = pos, normal = normal, right = right, down = down, scale = scale}
	pointer(s)
	cam.Start3D2D(pos,right:AngleEx(normal),scale)
		cam.IgnoreZ(true)
		drawScreen(s)
		cam.IgnoreZ(false)
	cam.End3D2D()
end)

function PLUGIN:PreDrawViewModel()
	if (pad.screen and !pad.screen.witness) then return true end
end

if (pad.slungModels) then
	for k, ent in pairs(pad.slungModels) do
		if (IsValid(ent)) then ent:Remove() end
		pad.slungModels[k] = nil
	end
end
pad.slungModels = {}

local function clearSlungModel(client)
	local ent = pad.slungModels[client]
	if (IsValid(ent)) then ent:Remove() end
	pad.slungModels[client] = nil
end

local function clearAllSlungModels()
	for k, ent in pairs(pad.slungModels) do
		if (IsValid(ent)) then ent:Remove() end
		pad.slungModels[k] = nil
	end
end

local function drawSlungWeapon(client)
	if (!IsValid(client) or !client:Alive()) then
		clearSlungModel(client)
		return
	end
	local slung = client:GetNetVar("ixSlungWeapon")
	if (!istable(slung) or !isstring(slung.model) or slung.model == "") then
		clearSlungModel(client)
		return
	end
	local active = client:GetActiveWeapon()
	if (IsValid(active) and active:GetClass() == slung.class) then
		return
	end
	if (client == LocalPlayer() and !client:ShouldDrawLocalPlayer()) then
		return
	end

	local bone = client:LookupBone("ValveBiped.Bip01_Spine2")
	local matrix = bone and client:GetBoneMatrix(bone)
	if (!matrix) then return end

	local model = pad.slungModels[client]
	if (!IsValid(model) or model:GetModel() != slung.model) then
		clearSlungModel(client)
		model = ClientsideModel(slung.model, RENDERGROUP_OPAQUE)
		if (!IsValid(model)) then return end
		model:SetNoDraw(true)
		pad.slungModels[client] = model
	end

	local pos, ang = LocalToWorld(Vector(1.5, -5.5, -1.5), Angle(32, 0, 0), matrix:GetTranslation(), matrix:GetAngles())
	model:SetPos(pos)
	model:SetAngles(ang)
	model:SetupBones()
	model:DrawModel()
end

local function drawRaisedPad(client)
	if (!client:GetNetVar("datapadRaised") or (client == LocalPlayer() and pad.screen)) then return end
	local bone = client:LookupBone("ValveBiped.Bip01_L_Hand")
	local hand = bone and client:GetBoneMatrix(bone)
	if (!hand) then return end
	local view = Angle(50,client:EyeAngles().y,0)
	local right, down, normal = view:Right(), -view:Up(), -view:Forward()
	local center = hand:GetTranslation()+right*3
	local scale = 0.012
	render.SetColorMaterial()
	render.DrawBox(center-normal*0.45,right:AngleEx(normal),Vector(-6.6,-4.1,-0.55),Vector(6.6,4.1,0.3),Color(64,65,53))
	local origin = center-right*W*scale/2-down*H*scale/2
	cam.Start3D2D(origin,right:AngleEx(normal),scale)
		chassis(client:IsCombine(), ix.body and isfunction(ix.body.HasBiomonitor) and ix.body.HasBiomonitor(client))
		txt("FIELD TERMINAL", 40, 75, "title", amber)
		for i = 1,8 do box(44,108+i*42,420-i%3*67,8,grid) end
	cam.End3D2D()
	hologram.DrawWorld(client, origin + right*727*scale + down*520*scale + normal*0.6, right, -down, normal, 410*scale, amber)
end

-- The slung rifle on the back and the handheld enclosure are visible to people around the player.
function PLUGIN:PostPlayerDraw(client)
	drawSlungWeapon(client)
	drawRaisedPad(client)
end

function PLUGIN:EntityRemoved(entity)
	if (pad.slungModels[entity]) then
		clearSlungModel(entity)
	end
end

function PLUGIN:ShutDown()
	clearAllSlungModels()
end

function PLUGIN:PopulateCharacterInfo(client, _, tooltip)
	if (!IsValid(client) or !client:Alive()) then return end

	local slung = client:GetNetVar("ixSlungWeapon")
	if (istable(slung) and isstring(slung.name) and slung.name != "") then
		local active = client:GetActiveWeapon()
		if (!IsValid(active) or active:GetClass() != slung.class) then
			local row = tooltip:AddRowAfter("description", "ixSlungWeapon")
			row:SetText("Carrying a " .. slung.name .. " on a shoulder sling.")
			row:SetTextColor(amber)
			row:SizeToContents()
		end
	end

	if (client:GetNetVar("datapadRaised")) then
		local row = tooltip:AddRowAfter("description", "datapadRaised")
		row:SetText("Looking down at a field terminal.")
		row:SetTextColor(amber)
		row:SizeToContents()
	end

	if (client:GetNetVar("datapadRummaging")) then
		local row = tooltip:AddRowAfter("description", "datapadRummaging")
		row:SetText("Rummaging through gear.")
		row:SetTextColor(amber)
		row:SizeToContents()
	end
end
