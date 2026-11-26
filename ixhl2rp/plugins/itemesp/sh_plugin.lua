local PLUGIN = PLUGIN
PLUGIN.name = "Item ESP"
PLUGIN.author = "Huargenn/Oebelysk"
PLUGIN.description = "Adds an ESP that displays items on the server."

if (CLIENT) then
	ix.option.Add("observerItemESP", ix.type.bool, true, {
		category = "observer",
		hidden = function()
			return !CAMI.PlayerHasAccess(LocalPlayer(), "Helix - Observer", nil)
		end
	})

	local dimDistance = 1024

	function PLUGIN:HUDPaint()
		local client = LocalPlayer()

		if (ix.option.Get("observerESP", true) and client:GetMoveType() == MOVETYPE_NOCLIP and
			!client:InVehicle() and CAMI.PlayerHasAccess(client, "Helix - Observer", nil) and
			ix.option.Get("observerItemESP", true)) then
			for _, v in ipairs(ents.FindByClass("ix_item")) do
				local itemTable = v:GetItemTable()

				-- the item's ID can arrive a moment after the entity does
				if (!itemTable) then
					continue
				end

				local screenPosition = v:GetPos():ToScreen()
				local marginX, marginY = ScrH() * .1, ScrH() * .1
				local x, y = math.Clamp(screenPosition.x, marginX, ScrW() - marginX), math.Clamp(screenPosition.y, marginY, ScrH() - marginY)
				local distance = client:GetPos():Distance(v:GetPos())
				local factor = 1 - math.Clamp(distance / dimDistance, 0, 1)
				local size = math.max(5, 20 * factor)
				local alpha = math.max(255 * factor, 80)

				ix.util.DrawText("[" .. itemTable:GetName() .. "]", x, y - size, Color(60, 209, 199),
					TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, nil, alpha)
			end
		end
	end
end
