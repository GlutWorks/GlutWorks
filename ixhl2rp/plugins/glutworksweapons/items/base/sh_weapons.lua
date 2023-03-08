ITEM.category = "Weapons"

function ITEM:PopulateTooltip(tooltip)
    // don't show ammo count on grenades or melee weapons
    if (self.weaponCategory != "melee" and self.weaponCategory != "grenade") then
        local ammo = self:GetData("ammo")
        if (ammo == nil) then
            ammo = 0
        end
    
        local ammoCount = tooltip:AddRow("ammoCount")
        ammoCount:SetText("Ammunition in magazine: "..ammo)
        ammoCount:SetTextColor(Color(184, 184, 184))
        ammoCount:SizeToContents()
    end
end
