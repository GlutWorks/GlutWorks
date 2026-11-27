
local PLUGIN = PLUGIN

ITEM.name = "Drink"
ITEM.description = "Something to drink."
ITEM.category = "Drink"
ITEM.model = Model("models/props_junk/popcan01a.mdl")

-- Effects of one serving; survivaladditions/sv_hooks.lua PLUGIN:Consume applies them.
ITEM.restoredHunger = 0
ITEM.restoredThirst = 10
ITEM.restoredHealth = 0
ITEM.restoredStamina = 0
-- Item IDs handed back after drinking, such as an empty can.
ITEM.items = nil
ITEM.useSound = "npc/barnacle/barnacle_gulp2.wav"
ITEM.useSoundPitch = 90
ITEM.bMessy = false

--- Override to restrict who may drink this.
function ITEM:CanConsume(client)
	return true
end

ITEM.functions.Drink = {
	icon = "icon16/cup.png",
	OnRun = function(item)
		return PLUGIN:Consume(item, item.player)
	end,
	OnCanRun = function(item)
		return item:CanConsume(item.player) != false
	end
}
