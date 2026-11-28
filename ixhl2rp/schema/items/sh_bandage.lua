
ITEM.name = "Bandage"
ITEM.model = Model("models/props_wasteland/prison_toiletchunk01f.mdl")
ITEM.description = "A small roll of hand-made gauze."
ITEM.category = "Medical"
ITEM.price = 18

ITEM.functions.Apply = {
	sound = "items/medshot4.wav",
	OnRun = function(itemTable, data)
		local client = itemTable.player

		if (ix.body and ix.config.Get("bodyWoundsEnabled", true) and ix.body.HasOpenWound(client)) then
			local region = istable(data) and isstring(data.region) and ix.body.IsRegion(data.region) and data.region or nil

			ix.body.StartTreatWound(client, itemTable, region)
			return false
		end

		client:SetHealth(math.min(client:Health() + 20, client:GetMaxHealth()))
	end
}
