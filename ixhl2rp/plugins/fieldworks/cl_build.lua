local PLUGIN = PLUGIN
local placing

local function Stop()
	if (placing and IsValid(placing.ghost)) then placing.ghost:Remove() end
	placing = nil
end

local function LowerDatapad()
	if (ix.datapad and ix.datapad.screen) then ix.datapad.Close() end
	if (IsValid(ix.gui.menu)) then ix.gui.menu:Remove() end
end

local function HasTools(item)
	local char = LocalPlayer():GetCharacter()
	return char and char:GetInventory() and char:GetInventory():GetItemByID(item.id) != nil
end

function PLUGIN:OpenTools(item)
	Stop()
	LowerDatapad()
	if (!HasTools(item)) then return end
	local rows = {}
	for key, stock in SortedPairs(self.stock) do
		rows[#rows + 1] = {label = "Cut " .. stock.name:lower(), kind = key}
	end
	rows[#rows + 1] = {label = "Craft workbench kit (2 kg wood, 2 kg metal)", kind = "kit"}
	ix.worldui.Open({held = true, title = item.name, rows = rows, OnSelect = function(_, row)
		if (row.kind == "kit") then
			net.Start("ixCraftRecipe")
				net.WriteString("pack_workbench")
			net.SendToServer()
		else
			self:StartPlacement(item, row.kind)
		end
	end})
end

local nextMode = {surface = "upright", upright = "level", level = "span", span = "surface"}
local hints = {
	surface = "Cut along the surface.",
	upright = "Cut vertically across your view.",
	level = "Cut horizontally at the anchor height.",
	span = "Span three surface points."
}

local function resetCut(p)
	p.anchor, p.edge, p.width, p.pose, p.reason = nil, nil, nil, nil, nil
end

function PLUGIN:StartPlacement(item, kind)
	Stop()
	LowerDatapad()
	if (!HasTools(item)) then return end
	local client = LocalPlayer()
	placing = {item = item, kind = kind, char = client:GetCharacter(), mode = "surface",
		turn = math.Round(client:EyeAngles().y / 90) % 4}
	if (kind == "workbench") then
		local ghost = ClientsideModel(ix.item.list.workbench.model, RENDERGROUP_TRANSLUCENT)
		if (!IsValid(ghost)) then Stop() ix.util.Notify("The workbench preview could not be loaded.") return end
		ghost:SetNoDraw(true)
		placing.ghost = ghost
		ix.util.Notify("Aim at level floor. Reload turns the bench. Hold Walk to pin. Primary places, secondary cancels.")
	else
		ix.util.Notify("Primary marks the first corner. Reload changes the cutting plane. Hold Walk to snap to a cut edge.")
	end
end

local function aimPoint(p, eyes, aim)
	if (!p.plane) then
		if (p.trace.Hit and !p.trace.HitSky) then return PLUGIN:Contact(p.trace, LocalPlayer():KeyDown(IN_WALK)) end
		return
	end
	local dot = aim:Dot(p.plane)
	if (math.abs(dot) < 0.001) then return end
	local distance = (p.anchor - eyes):Dot(p.plane) / dot
	if (distance > 0 and distance <= PLUGIN.cutReach + 64) then
		return eyes + aim * distance
	end
end

local function Update()
	local p, client = placing, LocalPlayer()
	if (!p) then return end
	if (!PLUGIN:CanWork(client) or client:GetCharacter() != p.char or !HasTools(p.item)
		or gui.IsGameUIVisible() or vgui.CursorVisible() or (ix.datapad and ix.datapad.screen)) then Stop() return end
	local eyes, aim = client:GetShootPos(), client:GetAimVector()
	if (p.kind != "workbench" or !client:KeyDown(IN_WALK) or !p.trace) then
		p.trace = util.TraceLine({start = eyes, endpos = eyes + aim * PLUGIN.cutReach, filter = client, mask = MASK_SOLID})
	end
	if (p.kind == "workbench") then p.pose, p.reason = PLUGIN:BenchLayout(p.trace, p.turn) return end
	p.reason, p.pose, p.point = nil, nil, nil
	if (!p.anchor) then
		if (p.trace.Hit and !p.trace.HitSky and (p.trace.HitWorld or PLUGIN:IsBuildPiece(p.trace.Entity))) then
			p.point = PLUGIN:Contact(p.trace, client:KeyDown(IN_WALK))
		else
			p.reason = "Start on the map or a built piece within reach."
		end
		return
	end
	p.point = p.width or aimPoint(p, eyes, aim)
	if (!p.point) then p.reason = "Aim within reach of the cutting plane." return end
	if (!p.edge) then
		local length = p.point:Distance(p.anchor)
		if (length < 4 or length > PLUGIN.maxCut) then p.reason = "Mark an edge between 4 and 192 units long." end
		return
	end
	p.pose, p.reason = PLUGIN:CutPose(p.kind, p.anchor, p.edge, p.point, p.normal, p.plane)
	if (p.pose and PLUGIN:CutBlocked(p.pose)) then p.reason = "The cut intersects something. Adjust a mark." end
end

function PLUGIN:Think()
	if (placing) then Update() end
end

local clear, blocked = Color(155, 230, 181, 155), Color(237, 82, 54, 150)
local marker = Vector(1.2, 1.2, 1.2)

function PLUGIN:PostDrawTranslucentRenderables(depth, sky)
	local p = placing
	if (depth or sky or !p) then return end
	if (IsValid(p.ghost) and p.pose) then
		p.ghost:SetPos(p.pose.pos)
		p.ghost:SetAngles(p.pose.ang)
		p.ghost:SetupBones()
		render.SetBlend(0.63)
		if (p.reason) then render.SetColorModulation(1, 0.22, 0.14) else render.SetColorModulation(0.64, 1, 0.80) end
		p.ghost:DrawModel()
		render.SetColorModulation(1, 1, 1)
		render.SetBlend(1)
	elseif (p.kind != "workbench") then
		local tint = p.reason and blocked or clear
		render.SetColorMaterial()
		if (p.pose) then
			local half = p.pose.size / 2
			render.DrawBox(p.pose.pos, p.pose.ang, -half, half, tint)
			render.DrawWireframeBox(p.pose.pos, p.pose.ang, -half, half, tint)
		end
		if (p.point) then render.DrawBox(p.point, angle_zero, -marker, marker, tint) end
		if (p.anchor) then
			render.DrawBox(p.anchor, angle_zero, -marker, marker, clear)
			if (p.edge or p.point) then render.DrawLine(p.anchor, p.edge or p.point, clear, true) end
		end
	end
end

local function coords(point)
	return {x = point.x, y = point.y, z = point.z}
end

local function send(p)
	if ((p.sent or 0) > RealTime()) then return end
	p.sent = RealTime() + 0.5
	local bench = p.kind == "workbench"
	local data = coords(bench and p.trace.HitPos or p.hit)
	data.kind = p.kind
	if (bench) then
		data.target, data.step = p.trace.Entity:EntIndex(), p.turn
	else
		data.target, data.mode, data.snap, data.yaw = p.target, p.mode, p.snap, p.yaw
		data.edge, data.width = coords(p.edge), coords(p.width)
		data.cost = PLUGIN:StockCost(p.kind, p.pose.size)
	end
	net.Start("ixInventoryAction")
		net.WriteString(bench and "place" or "build")
		net.WriteUInt(p.item.id, 32)
		net.WriteUInt(p.item.invID, 32)
		net.WriteTable(data)
	net.SendToServer()
end

function PLUGIN:PlayerBindPress(_, bind, pressed)
	local p = placing
	if (!p) then return end
	bind = bind:lower()
	if (bind != "+attack" and bind != "+attack2" and bind != "+reload") then return end
	if (!pressed) then return true end
	Update()
	if (!placing) then return true end
	if (bind == "+attack2") then
		if (p.width) then p.width = nil
		elseif (p.edge) then p.edge = nil
		elseif (p.anchor) then resetCut(p)
		elseif (p.kind == "workbench") then Stop()
		else self:OpenTools(p.item) end
	elseif (bind == "+reload") then
		if (p.kind == "workbench") then
			p.turn = (p.turn + 1) % 4
		else
			p.mode = nextMode[p.mode]
			if (p.anchor) then
				p.plane = self:PlaneNormal(p.mode, p.normal, p.yaw)
				p.edge, p.width = nil, nil
			end
			ix.util.Notify(hints[p.mode])
		end
	elseif (p.reason) then
		ix.util.Notify(p.reason)
	elseif (p.kind == "workbench" or p.width) then
		send(p)
	elseif (!p.anchor) then
		p.anchor, p.hit, p.target, p.normal = p.point, p.trace.HitPos, p.trace.Entity:EntIndex(), p.trace.HitNormal
		p.snap, p.yaw = LocalPlayer():KeyDown(IN_WALK), LocalPlayer():EyeAngles().y
		p.plane = self:PlaneNormal(p.mode, p.normal, p.yaw)
		ix.util.Notify(hints[p.mode] .. " Mark the far end of the first edge. Secondary undoes a mark.")
	elseif (!p.edge) then
		p.edge = p.point
		ix.util.Notify("Move across the edge to set the width, then mark it.")
	elseif (p.pose) then
		p.width = p.point
		ix.util.Notify(string.format("%.1f kg of %s. Primary fastens this cut, secondary adjusts it.",
			self:StockCost(p.kind, p.pose.size), ix.item.list[self.stock[p.kind].item].name:lower()))
	end
	return true
end

net.Receive("ixFieldPlaced", function()
	local id = net.ReadUInt(32)
	if (!placing or placing.item.id != id) then return end
	if (placing.kind == "workbench") then Stop() return end
	resetCut(placing)
	ix.util.Notify("Fastened. Mark another corner or use secondary to change material.")
end)
