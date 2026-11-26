local PLUGIN = PLUGIN

-- Added after Helix's own base_weapons tooltip, which highlights equipped weapons.
function PLUGIN:PopulateItemTooltip(tooltip, item)
	if (!item.isWeapon or !item.id or item.weaponCategory == "melee" or item.weaponCategory == "grenade") then
		return
	end

	local row = tooltip:AddRow("ammoCount")
	row:SetText(L("ammoInMagazine", item:GetData("ammo", 0)))
	row:SetTextColor(Color(184, 184, 184))
	row:SizeToContents()
end

-- The weapons are TFA SWEPs; Helix has its own crosshair, inventory and context menu, so
-- TFA's are turned off. All of this is inert when TFA is not installed.
hook.Add("InitializedPlugins", "ixGlutWorksWeaponsTFA", function()
	hook.Remove("ContextMenuOpen", "TFAContextBlock")
	hook.Remove("Think", "TFAInspectionMenu")
end)

hook.Add("TFA_DrawCrosshair", "ixGlutWorksWeaponsTFA", function()
	return true
end)
