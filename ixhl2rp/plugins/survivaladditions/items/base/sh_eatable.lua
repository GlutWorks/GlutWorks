
local PLUGIN = PLUGIN

ITEM.name = "Food"
ITEM.description = "Something to eat."
ITEM.category = "Food"
ITEM.model = Model("models/props_junk/garbage_takeoutcarton001a.mdl")

-- Effects of one serving; survivaladditions/sv_hooks.lua PLUGIN:Consume applies them.
ITEM.restoredHunger = 10
ITEM.restoredThirst = 0
ITEM.restoredHealth = 0
ITEM.restoredStamina = 0
-- Item IDs handed back after eating, such as an empty container.
ITEM.items = nil
ITEM.useSound = "npc/antlion_grub/squashed.wav"
ITEM.useSoundPitch = 150
-- Raw food splatters when eaten.
ITEM.bMessy = false

--- Override to restrict who may eat this.
function ITEM:CanConsume(client)
	return true
end

ITEM.functions.Eat = {
	icon = "icon16/cake.png",
	OnRun = function(item)
		return PLUGIN:Consume(item, item.player)
	end,
	OnCanRun = function(item)
		return item:CanConsume(item.player) != false
	end
}
