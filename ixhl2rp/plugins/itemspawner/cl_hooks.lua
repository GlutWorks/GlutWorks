
local PLUGIN = PLUGIN

PLUGIN.positions = {}

net.Receive("ixItemSpawnerManager", function()
	local data = net.ReadTable()
	vgui.Create("ixItemSpawnerManager"):Populate(data)
	PLUGIN.positions = data
end)

net.Receive("ixItemSpawnerEdit", function()
	PLUGIN.positions = net.ReadTable()
end)

function PLUGIN:HUDPaint()
	local client = LocalPlayer()
	if (ix.option.Get("observerESP", true) and client:GetMoveType() == MOVETYPE_NOCLIP and !client:InVehicle() and CAMI.PlayerHasAccess(client, "Helix - Observer", nil)) then
		if (ix.option.Get("observerItemESP", true)) then
			for k, v in ipairs(PLUGIN.positions) do
				local screenPosition = v.position:ToScreen()
				local marginX, marginY = ScrH() * .1, ScrH() * .1
				local x, y = math.Clamp(screenPosition.x, marginX, ScrW() - marginX), math.Clamp(screenPosition.y, marginY, ScrH() - marginY)
				local distance = client:GetPos():Distance(v.position)
				local factor = 1 - math.Clamp(distance / 1024, 0, 1)
				local size = math.max(5, 20 * factor)
				local alpha = math.max(255 * factor, 80)
				surface.SetFont("ixGenericFont")
				ix.util.DrawText(L"["..v.title.."]", x, y - size, Color(221, 98, 61), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, nil, alpha)
				ix.util.DrawText(L"Rare Chance: ["..v.rarity.."]", x, y - size + 20, Color(221, 192, 61), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, nil, alpha)
			end
		end
	end
end
