ITEM.name = "Child"
ITEM.model = Model("models/props_c17/doll01.mdl")
ITEM.description = "An infant human, yearning to see the joys of life."
ITEM.items = {"meat_chunk", "infant_skull"}

ITEM.functions.Open = {
	OnRun = function(itemTable)
		local client = itemTable.player
		local character = client:GetCharacter()

		for k, v in ipairs(itemTable.items) do
			if (!character:GetInventory():Add(v)) then
				ix.item.Spawn(v, client)
			end
		end

		client:EmitSound("physics/flesh/flesh_squishy_impact_hard3.wav", 75, 80, 0.35)
	end
}
