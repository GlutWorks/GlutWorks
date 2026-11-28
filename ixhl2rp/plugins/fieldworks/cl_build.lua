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
	for _, key in ipairs({"frame", "boards", "metal", "roof"}) do
		local part = self.parts[key]
		local material = part.item == "wooden_scrap" and "wood" or "metal"
		rows[#rows + 1] = {label = part.name .. " (" .. part.cost .. " kg " .. material .. ")", kind = key}
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

function PLUGIN:StartPlacement(item, kind)
	Stop()
	LowerDatapad()
	if (!HasTools(item)) then return end
	local client = LocalPlayer()
	local part = self.parts[kind] or ix.item.list.workbench
	local ghost = ClientsideModel(part.model, RENDERGROUP_TRANSLUCENT)
	if (!IsValid(ghost)) then ix.util.Notify("The preview model could not be loaded.") return end
	ghost:SetNoDraw(true)
	ghost:SetMaterial(part.material or "")
	placing = {item = item, kind = kind, ghost = ghost, char = client:GetCharacter(),
		turn = math.Round(client:EyeAngles().y / 90) % 4, join = 0}
	local aim = kind == "roof" and "Aim at one of two parallel frames."
		or (kind == "boards" or kind == "metal") and "Aim at an open frame."
		or kind == "frame" and "Aim at the floor or at a frame to join it." or "Aim at the floor."
	ix.util.Notify(aim .. " Reload rotates or cycles joins. Hold Walk to pin. Primary places, secondary cancels.")
end

local function Update()
	local p, client = placing, LocalPlayer()
	if (!p) then return end
	if (!PLUGIN:CanWork(client) or client:GetCharacter() != p.char or !HasTools(p.item)
		or gui.IsGameUIVisible() or vgui.CursorVisible() or (ix.datapad and ix.datapad.screen)) then Stop() return end
	if (!client:KeyDown(IN_WALK) or !p.trace) then
		local eyes = client:GetShootPos()
		p.trace = util.TraceLine({start = eyes, endpos = eyes + client:GetAimVector() * 160, filter = client, mask = MASK_SOLID})
	end
	p.atWall = PLUGIN:IsWall(p.trace.Entity)
	p.step = p.atWall and p.join or p.turn
	p.pose, p.reason = PLUGIN:Layout(client, p.kind, p.trace, p.step)
end

function PLUGIN:Think()
	if (placing) then Update() end
end

function PLUGIN:PostDrawTranslucentRenderables(depth, sky)
	local p = placing
	if (depth or sky or !p or !p.pose or !IsValid(p.ghost)) then return end
	p.ghost:SetPos(p.pose.pos)
	p.ghost:SetAngles(p.pose.ang)
	p.ghost:SetupBones()
	render.SetBlend(0.63)
	if (p.reason) then render.SetColorModulation(1, 0.22, 0.14) else render.SetColorModulation(0.64, 1, 0.80) end
	p.ghost:DrawModel()
	render.SetColorModulation(1, 1, 1)
	render.SetBlend(1)
end

function PLUGIN:PlayerBindPress(_, bind, pressed)
	local p = placing
	if (!p) then return end
	bind = bind:lower()
	if (bind != "+attack" and bind != "+attack2" and bind != "+reload") then return end
	if (!pressed) then return true end
	if (bind == "+attack2") then
		Stop()
		if (p.kind != "workbench") then self:OpenTools(p.item) end
	elseif (bind == "+reload") then
		if (p.atWall) then
			local count = p.kind == "roof" and 2 or #self.joins
			p.join = (p.join + 1) % count
			if (p.kind == "frame") then ix.util.Notify(self.joins[p.join + 1]) end
		else
			p.turn = (p.turn + 1) % 4
		end
	else
		Update()
		if (!placing) then return true end
		if (p.reason or !p.pose) then ix.util.Notify(p.reason or "Choose a placement point.") return true end
		local hit = p.trace.HitPos
		net.Start("ixInventoryAction")
			net.WriteString(p.kind == "workbench" and "place" or "build")
			net.WriteUInt(p.item.id, 32)
			net.WriteUInt(p.item.invID, 32)
			net.WriteTable({kind = p.kind, step = p.step, x = hit.x, y = hit.y, z = hit.z, target = p.trace.Entity:EntIndex()})
		net.SendToServer()
	end
	return true
end

net.Receive("ixFieldPlaced", function()
	local id = net.ReadUInt(32)
	if (placing and placing.item.id == id and placing.kind == "workbench") then Stop() end
end)
