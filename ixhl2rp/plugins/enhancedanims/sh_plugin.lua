
local PLUGIN = PLUGIN

PLUGIN.name = "Enhanced Animations"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Animation classes for the extended citizen models and per-weapon hold types for every class."

ix.util.Include("sh_classes.lua")

-- Stock Helix collapses most hold types into a few (ar2 into smg, knife into melee, ...). The
-- extended citizens have a distinct player animation for each, so keep them apart.
HOLDTYPE_TRANSLATOR["ar2"] = "ar2"
HOLDTYPE_TRANSLATOR["crossbow"] = "crossbow"
HOLDTYPE_TRANSLATOR["rpg"] = "rpg"
HOLDTYPE_TRANSLATOR["slam"] = "grenade"
HOLDTYPE_TRANSLATOR["fist"] = "fist"
HOLDTYPE_TRANSLATOR["melee2"] = "melee2"
HOLDTYPE_TRANSLATOR["knife"] = "knife"
HOLDTYPE_TRANSLATOR["revolver"] = "revolver"

PLAYER_HOLDTYPE_TRANSLATOR["rpg"] = "normal"

-- Every hold type a weapon can report (see Weapon:SetHoldType).
PLUGIN.holdTypes = {
	"", "normal", "pistol", "smg", "grenade", "ar2", "shotgun", "rpg", "physgun", "crossbow", "melee",
	"slam", "fist", "melee2", "passive", "knife", "duel", "camera", "magic", "revolver"
}

-- Which table a class falls back to when it has none for a hold type. The first seven are the
-- collapses stock Helix does, so classes without the extra tables animate exactly as before.
PLUGIN.holdTypeFallback = {
	ar2 = "smg",
	crossbow = "shotgun",
	rpg = "shotgun",
	fist = "normal",
	melee2 = "melee",
	knife = "melee",
	revolver = "pistol",
	shotgun = "smg",
	smg = "normal",
	pistol = "normal",
	grenade = "normal",
	melee = "normal"
}

--- Whether an `ix.anim` entry is a model class whose per-hold-type tables the translator uses.
-- `player` animates through its own path and the zombie entries are flat activity maps.
function PLUGIN:IsHoldTypeClass(name, class)
	return name != "player" and istable(class) and istable(class.normal)
end

--- Gives every animation class a table for every hold type the translator can produce.
function PLUGIN:FillHoldTypes()
	for name, class in pairs(ix.anim) do
		if (self:IsHoldTypeClass(name, class)) then
			for _, holdType in ipairs(self.holdTypes) do
				holdType = HOLDTYPE_TRANSLATOR[holdType] or holdType

				local source = holdType

				while (!class[source] and source != "normal") do
					source = self.holdTypeFallback[source] or "normal"
				end

				class[holdType] = class[source]
			end
		end
	end
end

-- Again once every plugin has loaded, for classes other plugins add.
PLUGIN:FillHoldTypes()

function PLUGIN:InitializedPlugins()
	self:FillHoldTypes()
end

-- The extended citizen models live under models/player/, which stock Helix would treat as
-- plain player models. Unknown models keep the stock classes.
for i = 1, 11 do
	ix.anim.SetModelClass(string.format("models/player/zelpa/male_%02d_extended.mdl", i), "citizen_male_enhanced")
end

for i = 1, 7 do
	ix.anim.SetModelClass(string.format("models/player/zelpa/female_%02d_extended.mdl", i), "citizen_female_enhanced")
end

ix.anim.SetModelClass("models/police_nemez.mdl", "metrocop")

-- The extended citizens have every citizen sequence, so they get the same acts.
hook.Add("SetupActs", "ixEnhancedAnims", function()
	for _, classes in pairs(ix.act.stored) do
		classes.citizen_male_enhanced = classes.citizen_male_enhanced or classes.citizen_male
		classes.citizen_female_enhanced = classes.citizen_female_enhanced or classes.citizen_female
	end
end)

if (CLIENT) then
	-- The bundled receiver indexes actEnterAngle unguarded, but ixActEnter is sent when the enter
	-- sequence finishes, by which time the player may already have left the act.
	net.Receive("ixActEnter", function()
		local act = ix.plugin.Get("act")
		local angle = LocalPlayer():GetNetVar("actEnterAngle")

		act.bIdle = net.ReadBool()

		if (angle) then
			act.forward = angle:Forward()
			act.cameraTween = ix.tween.new(2, act, {
				cameraFraction = 1
			}, "outQuint")
		end
	end)
end
