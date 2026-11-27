-- Weapon items (glutworksweapons): the faction loadout weapons exist, tfa_support is gone, a weapon item whose
-- SWEP is missing equips without errors, and shotguns are marked for breaching doors.

local Lib = GWH.Lib
local ResetBot = Lib.ResetBot

GWH.Check("survival: weapon items work without their SWEPs", function(fail)
	local bot = GWH.Bot()
	if (!bot) then return fail("no bot") end

	for _, v in ipairs({"pistol", "stunstick", "ar2"}) do
		if (!ix.item.list[v]) then fail("faction loadout item " .. v .. " is missing") end
	end

	if (ix.plugin.list.tfa_support or ix.item.list.ammo_assault) then
		fail("tfa_support is still loaded")
	end

	local character = bot:GetCharacter()
	local inventory = character:GetInventory()
	local errors = #GWH.errors

	ResetBot(bot)

	-- pistol's SWEP is external content: equipping it must fail quietly
	inventory:Add("pistol")
	local item = inventory:HasItem("pistol")

	if (item) then
		ix.item.PerformInventoryAction(bot, "Equip", item:GetID(), inventory:GetID())

		if (item:GetData("equip")) then
			ix.item.PerformInventoryAction(bot, "EquipUn", item:GetID(), inventory:GetID())
		end

		item:Remove()
	end

	if (#GWH.errors > errors) then fail("equipping a weapon without its SWEP raised " .. GWH.errors[#GWH.errors].error) end

	for _, v in ipairs({"shotgun", "waterpipe"}) do
		if (ix.item.list[v] and !ix.item.list[v].isShotgun) then fail(v .. " is not marked isShotgun for breaching") end
	end
end)
