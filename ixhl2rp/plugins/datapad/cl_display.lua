local pad = ix.datapad
local W, H = 1024, 610
local amber, bright, faint = Color(240, 179, 89), Color(255, 218, 148), Color(177, 145, 92)
local ink, grid, glaze = Color(22, 22, 17), Color(83, 70, 43), Color(55, 48, 32)
local hurt, dry, wet = Color(255, 111, 92), Color(224, 215, 179), Color(91, 206, 186)
local cold, bruise, sick, dressed = Color(145, 203, 245), Color(199, 155, 221), Color(180, 212, 117), Color(230, 165, 108)
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

local function chassis(combine)
	draw.RoundedBox(24, -30, -30, W + 60, H + 72, Color(24, 26, 24))
	draw.RoundedBox(21, -30, -36, W + 60, H + 72, combine and Color(82, 91, 90) or Color(110, 107, 83))
	draw.RoundedBox(18, -27, -33, W + 54, H + 65, combine and Color(53, 62, 62) or Color(73, 74, 61))
	draw.RoundedBox(11, -8, -8, W + 16, H + 16, Color(11, 12, 10))
	box(0, 0, W, H, ink)
	for _, x in ipairs({-17, W + 17}) do
		for _, y in ipairs({-21, H + 18}) do
			draw.RoundedBox(5, x - 5, y - 5, 10, 10, Color(36, 37, 31))
			line(x - 3, y + 2, x + 3, y - 2, faint)
		end
	end
	txt(combine and "CIVIL PROTECTION   /   BIOMONITOR" or "CIVIL SUPPLY   /   PORTABLE TERMINAL", 12, -21, "tiny", Color(207, 205, 174))
	txt("17-C", W - 12, -21, "tiny", Color(207, 205, 174), TEXT_ALIGN_RIGHT)
	for i = 0, 9 do box(W - 124 + i * 12, H + 14, 7, 5, Color(37, 39, 32)) end
	box(9, H + 14, 16, 4, amber)
end

local function itemStatus(item, place, body)
	if (item:GetData("spoiled") or item:GetData("contaminated")) then return "spoiled", sick end
	if (item:GetData("frozen")) then return "frozen", cold end
	if (item:GetData("wet") or (place.region and body and body.wetness >= 60 and item:GetData("equip") and (item.outfitCategory or item.wearPart))) then
		return "soaked", wet
	end
	if (ix.wear and ix.wear.IsWearable(item)) then
		local level, word = ix.wear.GetLevel(item)
		if (level >= 3) then return L(word), dry end
	end
	if (item.isWeapon and item.weaponCategory != "melee" and item.weaponCategory != "grenade" and !item:GetData("equip")
		and item:GetData("ammo", 0) == 0) then return "empty", dry end
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
			line(x, top, x + w, top, hot and hurt or grid)
			local jig = hot and !ix.option.Get("reduceMotionEffects", false) and math.sin(RealTime() * 26) * 2 or 0
			local cue = !external and placeCue(place) or nil
			txt(fit(string.upper(place.name), w - (cue and 178 or 102), "tiny"), x + 8 + jig, top + 15, "tiny", hot and hurt or faint)
			if (cue) then
				txt(cue, x + w - 58, top + 15, "tiny", pad.GetAccessTime(place) > 0 and dry or faint, TEXT_ALIGN_RIGHT)
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
			if (selected or hover) then box(x, top + 1, w, step - 2, selected and (red and hurt or amber) or glaze) end
			local body = external and pad.frisk and pad.frisk.body or !external and s.body
			local state, stateColor = itemStatus(item, place, body)
			local color = selected and ink or red and hurt or stateColor or amber
			local tag = red and flag and "restricted" or state or flag and "restricted" or item.category == "Medical" and "aid" or (item.restoredThirst or 0) > 0 and "drink" or nil
			local name = item:GetName()
			if (item.stackLimit) then name = name .. "  " .. ix.stack.Format(item, ix.stack.GetQuantity(item)) end
			txt(fit(name, w - (tag and 174 or 80), "row"), x + 12, top + 15, "row", color)
			if (tag) then txt(tag, x + w - 78, top + 15, "tiny", selected and ink or red and hurt or stateColor or tag == "aid" and hurt or tag == "drink" and dry or faint, TEXT_ALIGN_RIGHT) end
			txt(string.format("%.1f", pad.Weight(item, body and body.wetness)), x + w - 10, top + 15, "mono", color, TEXT_ALIGN_RIGHT)
		end
	end
	if (#rows > count) then
		local thumb = count * step * count / #rows
		box(x + w - 3, y + (count * step - thumb) * offset / (#rows - count), 3, thumb, faint)
	end
end

local parts = {
	{key = "head", x = 0, y = 0, rings = {{0,7},{5,15},{16,18},{30,14},{37,7}}},
	{key = "chest", x = 0, y = 37, rings = {{0,7},{7,9},{13,29},{20,34},{44,28},{65,21},{78,23}}},
	{key = "waist", x = 0, y = 114, rings = {{0,23},{7,25},{21,26},{26,16}}},
	{key = "arms", x = -35, y = 53, tilt = -0.20, rings = {{0,5},{7,9},{24,8},{42,5},{47,7},{68,4},{75,5},{83,3}}},
	{key = "arms", x = 35, y = 53, tilt = 0.20, rings = {{0,5},{7,9},{24,8},{42,5},{47,7},{68,4},{75,5},{83,3}}},
	{key = "legs", x = -14, y = 137, rings = {{0,12},{10,13},{43,9},{52,7},{62,8},{86,5},{105,4}}},
	{key = "legs", x = 14, y = 137, rings = {{0,12},{10,13},{43,9},{52,7},{62,8},{86,5},{105,4}}},
	{key = "feet", x = -15, y = 241, rings = {{0,4},{6,6},{11,10},{15,10}}},
	{key = "feet", x = 15, y = 241, rings = {{0,4},{6,6},{11,10},{15,10}}}
}
local function markColor(kind)
	return kind == "Bruise" and bruise or kind == "Poisoned" and sick or hurt
end
local function figure(s, x, y, scale, body, region, selectPart)
	local phase = ix.option.Get("reduceMotionEffects", false) and 0 or RealTime()
	local wounds = istable(body.wounds) and body.wounds or nil
	for _, part in ipairs(parts) do
		local focus = part.key == region
		local wound = wounds and wounds[part.key]
		local woundColor = wound and (wound.state == "dressed" and dressed or hurt) or nil
		local marked = !wound and body.mark and body.mark.part == part.key
		local caught = false
		if (s == pad.screen and pad.frisk and !s.witness) then
			for _, row in ipairs(pad.frisk.found) do
				if (row.flagged and part.key == row.region) then caught = true break end
			end
		end
		local c = woundColor or (marked and markColor(body.mark.kind)) or caught and hurt or focus and (pad.frisk and hurt or bright)
			or body.cold and (part.key == "feet" or part.key == "arms") and cold
			or body.wetness >= 25 and (part.key == "feet" or body.wetness >= 60) and wet or amber
		local dx = ((focus and pad.frisk) or caught or c == cold) and math.sin(phase * 23) * 1.1 or 0
		local ox, oy = x + part.x * scale + dx, y + part.y * scale
		for i = 2, #part.rings do
			local a, b = part.rings[i - 1], part.rings[i]
			local t = part.tilt or 0
			for h = a[1], b[1] - 0.01, 3 do
				local r = Lerp((h - a[1]) / (b[1] - a[1]), a[2], b[2])
				line(ox + (h*t-r)*scale, oy+h*scale, ox+(h*t+r)*scale, oy+h*scale, (focus or wound) and c or grid)
			end
			for _, sign in ipairs({-1,1}) do
				line(ox+(a[1]*t+sign*a[2])*scale, oy+a[1]*scale, ox+(b[1]*t+sign*b[2])*scale, oy+b[1]*scale,c)
			end
		end
		local h = part.rings[#part.rings][1]
		if (c == wet) then
			for j = 1, 3 do
				local drop = (phase * 19 + j * 13) % math.max(h - 5, 1)
				line(ox+(j-2)*3, oy+drop*scale, ox+(j-2)*3, oy+(drop+4)*scale, wet)
			end
		elseif (c == cold) then
			line(ox-3, oy+7*scale, ox+3, oy+13*scale, cold)
			line(ox+3, oy+7*scale, ox-3, oy+13*scale, cold)
		end
		if (body.thirst and body.thirst < 40 and part.key == "head") then
			line(ox-5, oy+22*scale, ox, oy+24*scale, dry)
			line(ox, oy+24*scale, ox+4, oy+21*scale, dry)
		end
		if (wound) then
			local cy = oy + h * scale * 0.5
			local m = math.max(4, math.Round(5 * scale))
			if (wound.kind == "gunshot") then
				surface.DrawCircle(ox, cy, m, woundColor)
			else
				line(ox - m, cy + m, ox + m, cy - m, woundColor)
			end
			if (wound.state == "dressed") then
				line(ox - m - 1, cy, ox + m + 1, cy, bright)
				line(ox - m - 1, cy + 1, ox + m + 1, cy + 1, bright)
			end
		elseif (marked) then
			local cy = oy + h * scale * 0.5
			if (body.mark.kind == "Gunshot") then surface.DrawCircle(ox, cy, 7, c)
			elseif (body.mark.kind == "Cut") then line(ox-6,cy+7,ox+6,cy-7,c)
			elseif (body.mark.kind == "Burn") then
				for j = -6, 6, 3 do line(ox+j,cy-6,ox+j+5,cy+6,c) end
			else draw.RoundedBox(6, ox-7, cy-5, 14, 10, c) end
		end
		if (selectPart and hit(s, part.key, ox-14*scale, oy, 28*scale, h*scale, function() s.part = part.key end)) then
			s.hoverPart = part.key
		end
	end
end

local solid = Material("models/debug/debugwhite")
local scanRT = GetRenderTarget("ixDatapadSpecimen", 256, 256)
local scanMat = CreateMaterial("ixDatapadScan", "UnlitGeneric", {["$basetexture"] = scanRT:GetName(), ["$translucent"] = "1"})
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
	render.Clear(22, 22, 17, 255, true, true)
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
	figure(s, x+w*0.23, 251, 0.60, s.body, from.region, false)
	if (IsValid(s.scan) and s.model == item:GetModel()) then
		surface.SetDrawColor(255,255,255)
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
	txt(s.witness and "YOUR CARRY   /   UNDER SEARCH" or "CARRIED EQUIPMENT", 28, 123, "tiny", s.witness and hurt or faint)
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
			txt(fit(dest and ("To " .. dest .. "   /   " .. string.format("%.1f kg after transfer", pad.Total(s.own) + (s.external and 1 or -1)*pad.TransferWeight(item))) or "No room for this item", 580, "tiny"), 30, 501, "tiny", dest and faint or hurt)
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

local function findCarriedBandage(groups)
	for _, place in ipairs(groups or {}) do
		for _, item in ipairs(place.items) do
			if (item.uniqueID == "bandage") then
				return place, item
			end
		end
	end
end

local function bodyScreen(s, frisk)
	local f = pad.frisk
	local body = frisk and f.body or s.body
	local diagramX = 237
	txt(frisk and "SUBJECT SCAN" or "BODY SCAN", 28, 124, "tiny", faint)
	for i = 0, 16 do
		local y = 153+i*21
		line(51, y, i%4 == 0 and 71 or 60, y, grid)
		if (i%4 == 0) then line(72, y, 408, y, glaze) end
	end
	s.hoverPart = nil
	local highlight = frisk and f.region or s.lastHoverPart or s.part
	figure(s, diagramX, 148, 1.42, body, highlight, !frisk)
	s.lastHoverPart = !frisk and s.hoverPart or nil
	local region = frisk and f.region or s.hoverPart or s.part
	local regionLabel = ix.body and ix.body.REGION_LABELS[region] or region
	txt(string.upper(regionLabel), 399, 516, "tiny", bright, TEXT_ALIGN_RIGHT)
	line(430, 110, 430, 526, grid)
	txt(frisk and (f.mode == "hasty" and "QUICK SEARCH" or "THOROUGH SEARCH") or "CONDITION", 454, 124, "tiny", faint)
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
	local mark = body.mark
	local healthText = hasOpenWound and "Wounded"
		or #activeWounds > 0 and "Recovering"
		or mark and (mark.kind .. " / " .. mark.part)
		or body.health < 100 and "Hurt"
		or "Steady"
	local healthColor = hasOpenWound and hurt
		or #activeWounds > 0 and dressed
		or (body.health < 100 and (mark and markColor(mark.kind) or hurt))
	local readings = {
		{"Health", healthText, healthColor},
		{"Breathing", body.stamina < 35 and "Winded" or "Even", body.stamina < 35 and dry},
		{"Clothing", body.wetness >= 60 and "Soaked" or body.wetness >= 25 and "Damp" or "Dry", body.wetness >= 25 and wet}
	}
	if (body.thirst) then
		readings[#readings+1] = {"Hydration", body.thirst < 40 and "Thirsty" or "Sufficient", body.thirst < 40 and dry}
		readings[#readings+1] = {"Appetite", body.hunger < 40 and "Hungry" or "Sated", body.hunger < 40 and dry}
	end
	if (body.temperature) then readings[#readings+1] = {"Temperature", body.temperature, body.cold and cold or body.hot and hurt} end
	local compact = !frisk and #activeWounds > 0
	local step = compact and 24 or 28
	local startY = compact and 140 or 146
	for i,r in ipairs(readings) do
		local top = startY + (i - 1) * step
		txt(r[1], 454, top + step * 0.45, "mono", faint)
		txt(r[2], 992, top + step * 0.45, compact and "mono" or "row", r[3] or amber, TEXT_ALIGN_RIGHT)
		line(454, top + step - 1, 994, top + step - 1, glaze)
	end
	local y = startY + #readings * step + (compact and 14 or 20)
	if (frisk) then
		txt(region == "complete" and "Search complete" or ("Searching " .. (f.label or region)), 454, y, "row", bright)
		box(454, y+19, 539, 4, glaze)
		box(454, y+19, 539*math.Clamp((CurTime()-f.start)/math.max(f.duration or 1, 0.01),0,1), 4, hurt)
		local count = math.max(1, math.floor((511-y-38)/26))
		local offset = math.Clamp(s.scroll.found or 0, 0, math.max(0,#f.found-count))
		if (inside(s, 450, y, 545, 518-y)) then s.hoverColumn = "found" end
		for i = offset+1, math.min(#f.found,offset+count) do
			local r = f.found[i]
			txt(fit(r.name .. "  /  " .. r.place, 510, "mono"), 454, y+47+(i-offset-1)*26, "mono", r.flagged and hurt or amber)
		end
		if (#f.found == 0) then txt("Nothing found yet", 454, y+52, "mono", faint) end
	else
		local selectedWound = istable(body.wounds) and body.wounds[region] or nil
		if (#activeWounds > 0) then
			local regionPanelH = selectedWound and 156 or 106
			local maxWoundsEnd = 556 - regionPanelH - 12
			local rowStep = 23
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
				local wWord = ix.body and ix.body.GetWoundSeverityWord(w.severity) or ""
				local stateText = w.state == "dressed" and "Dressed (healing)" or "Open"
				local stateCol = w.state == "dressed" and dressed or hurt
				txt(fit(wRegion .. "  /  " .. wKind .. " (" .. wWord .. ")", 345, "mono"), 460, top + 11, "mono", isSelected and bright or amber)
				txt(stateText, 990, top + 11, "tiny", stateCol, TEXT_ALIGN_RIGHT)
				line(454, top + rowStep - 1, 994, top + rowStep - 1, glaze)
			end
			y = listTop + visible * rowStep + 16
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
		local rowH = selectedWound and 24 or 28
		txt("Garments", 454, rowY + rowH * 0.45, "mono", faint)
		txt(fit(#garmentNames > 0 and table.concat(garmentNames, " / ") or "Uncovered", 420, "mono"), 992, rowY + rowH * 0.45, "mono", #garmentNames > 0 and amber or faint, TEXT_ALIGN_RIGHT)
		line(454, rowY + rowH - 1, 994, rowY + rowH - 1, glaze)
		rowY = rowY + rowH
		txt("Pockets", 454, rowY + rowH * 0.45, "mono", faint)
		txt(fit(#pocketNames > 0 and table.concat(pocketNames, " / ") or "No stowage here", 420, "mono"), 992, rowY + rowH * 0.45, "mono", #pocketNames > 0 and amber or faint, TEXT_ALIGN_RIGHT)
		line(454, rowY + rowH - 1, 994, rowY + rowH - 1, glaze)
		rowY = rowY + rowH
		local bandagePlace, bandageItem
		if (selectedWound) then
			local wKind = ix.body and ix.body.GetWoundKindLabel(selectedWound.kind) or tostring(selectedWound.kind)
			local wWord = ix.body and ix.body.GetWoundSeverityWord(selectedWound.severity) or ""
			local stateText = selectedWound.state == "dressed" and "Dressed (healing)" or "Open"
			local stateCol = selectedWound.state == "dressed" and dressed or hurt
			txt("Wound", 454, rowY + rowH * 0.45, "mono", faint)
			txt(fit(wKind .. " (" .. wWord .. ")  /  " .. stateText, 430, "mono"), 992, rowY + rowH * 0.45, "mono", stateCol, TEXT_ALIGN_RIGHT)
			line(454, rowY + rowH - 1, 994, rowY + rowH - 1, glaze)
			rowY = rowY + rowH
			bandagePlace, bandageItem = findCarriedBandage(s.own)
			local bandageWhere = bandagePlace and ("Carried  /  " .. bandagePlace.name)
			if (!bandageItem and s.storage) then
				bandagePlace, bandageItem = findCarriedBandage(s.away)
				if (bandageItem) then bandageWhere = "In reach  /  " .. bandagePlace.name end
			end
			txt("Bandage", 454, rowY + rowH * 0.45, "mono", faint)
			txt(fit(bandageWhere or "None carried", 430, "mono"), 992, rowY + rowH * 0.45, "mono", bandagePlace and bright or hurt, TEXT_ALIGN_RIGHT)
			line(454, rowY + rowH - 1, 994, rowY + rowH - 1, glaze)
			rowY = rowY + rowH
		end
		local btnX = 454
		local btnY = rowY + 10
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
	chassis(LocalPlayer():IsCombine())
	txt("FIELD TERMINAL", 26, 34, "tiny", faint)
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
		local rummaging = LocalPlayer():GetNetVar("datapadRummaging")
		local status = s.witness and ("SEARCH  /  " .. string.upper(pad.frisk.label or pad.frisk.region))
			or rummaging and ("REACHING INTO  " .. string.upper(rummaging) .. "...")
			or pad.receipt and pad.receipt.char == s.char and ("Filed   " .. pad.receipt.name .. "  /  " .. pad.receipt.place)
			or s.tab == "Body" and "Select a body part to inspect its equipment" or "Personal equipment register"
		txt(fit(status, 696,"tiny"), 26, 589,"tiny",(s.witness and hurt) or (rummaging and bright) or faint)
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
	cam.Start3D2D(center-right*W*scale/2-down*H*scale/2,right:AngleEx(normal),scale)
		chassis(client:IsCombine())
		txt("FIELD TERMINAL", 40, 75, "title", amber)
		for i = 1,8 do box(44,108+i*42,420-i%3*67,8,grid) end
		figure({}, 727, 102, 1.65, {wetness=0}, "", false)
	cam.End3D2D()
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
	if (!istable(slung) or !isstring(slung.name) or slung.name == "") then return end
	local active = client:GetActiveWeapon()
	if (IsValid(active) and active:GetClass() == slung.class) then return end
	local row = tooltip:AddRowAfter("description", "ixSlungWeapon")
	row:SetText("Carrying a " .. slung.name .. " on a shoulder sling.")
	row:SizeToContents()
end
