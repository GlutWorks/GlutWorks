
FACTION.name = "Citizen"
FACTION.description = "A regular human citizen enslaved by the Universal Union."
FACTION.color = Color(150, 125, 100, 255)
FACTION.isDefault = true

function FACTION:OnCharacterCreated(client, character)
	local id = Schema:ZeroNumber(math.random(1, 99999), 5)
	local inventory = character:GetInventory()

	character:SetData("cid", id)

	inventory:Add("suitcase", 1)
	inventory:Add("cid", 1, {
		name = character:GetName(),
		id = id
	})
end

FACTION_CITIZEN = FACTION.index

FACTION.models = {
	"models/player/zelpa/female_01_extended.mdl",
	"models/player/zelpa/female_02_extended.mdl",
	"models/player/zelpa/female_03_extended.mdl",
	"models/player/zelpa/female_04_extended.mdl",
	"models/player/zelpa/female_06_extended.mdl",
	"models/player/zelpa/female_07_extended.mdl",
	"models/player/zelpa/male_01_extended.mdl",
	"models/player/zelpa/male_02_extended.mdl",
	"models/player/zelpa/male_03_extended.mdl",
	"models/player/zelpa/male_04_extended.mdl",
	"models/player/zelpa/male_05_extended.mdl",
	"models/player/zelpa/male_06_extended.mdl",
	"models/player/zelpa/male_07_extended.mdl",
	"models/player/zelpa/male_08_extended.mdl",
	"models/player/zelpa/male_09_extended.mdl",
	"models/player/zelpa/male_10_extended.mdl",
	"models/player/zelpa/male_11_extended.mdl"
}
