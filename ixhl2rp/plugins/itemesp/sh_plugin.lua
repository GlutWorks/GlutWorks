local PLUGIN = PLUGIN
PLUGIN.name = "Item and Item Spawner ESP"
PLUGIN.author = "Huargenn/Oebelysk"
PLUGIN.desc = "Añade en el Observer el nombre de los items por el mapa"

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
		if (ix.option.Get("observerESP", true) and client:GetMoveType() == MOVETYPE_NOCLIP and !client:InVehicle() and CAMI.PlayerHasAccess(client, "Helix - Observer", nil)) then
			if (ix.option.Get("observerItemESP", true)) then
				for _, v in ipairs(ents.GetAll()) do
					if v:GetClass() == "ix_item" then
						local screenPosition = v:GetPos():ToScreen()
						local marginX, marginY = ScrH() * .1, ScrH() * .1
						local x, y = math.Clamp(screenPosition.x, marginX, ScrW() - marginX), math.Clamp(screenPosition.y, marginY, ScrH() - marginY)
						local distance = client:GetPos():Distance(v:GetPos())
						local factor = 1 - math.Clamp(distance / dimDistance, 0, 1)
						local size = math.max(5, 20 * factor)
						local alpha = math.max(255 * factor, 80)

						surface.SetFont("ixGenericFont")
						ix.util.DrawText(L"["..v:GetItemTable().name.."]", x, y - size, Color(60, 209, 199), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, nil, alpha)
					end
				end
			end
		end
	end
end
