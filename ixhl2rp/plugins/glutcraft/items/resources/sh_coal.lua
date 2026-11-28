ITEM.name = "Coal"
ITEM.description = "A reliable source of energy, but not very useful for anything else."
ITEM.model = Model("models/willardnetworks/props/charcoal.mdl")
ITEM.type = "coal"
ITEM.price = 3
-- The model's bounds are far larger than the lump itself, so the default icon camera
-- shows it as a speck.
ITEM.iconCam = {
	pos = Vector(509.64, 427.61, 310.24),
	ang = Angle(25, 220, 0),
	fov = 0.75
}
