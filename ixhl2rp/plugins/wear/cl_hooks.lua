
local PLUGIN = PLUGIN

-- Tooltip words for what an item still gives, from its effective warmth (degrees) and waterproofing (share).
PLUGIN.WARMTH_WORDS = {{8, "wearWarmthHigh"}, {3, "wearWarmthMid"}, {0.5, "wearWarmthLow"}}
PLUGIN.RAIN_WORDS = {{0.75, "wearRainHigh"}, {0.4, "wearRainMid"}, {0.15, "wearRainLow"}}

local function Pick(words, value)
	for _, entry in ipairs(words) do
		if (value >= entry[1]) then
			return entry[2]
		end
	end
end

local function AddRow(tooltip, id, text, color)
	local row = tooltip:AddRowAfter("description", id)
	row:SetText(text)

	if (color) then
		row:SetBackgroundColor(color)
	end

	row:SizeToContents()
end

function PLUGIN:PopulateItemTooltip(tooltip, item)
	if (!ix.wear.IsWearable(item)) then
		return
	end

	local level, phrase = ix.wear.GetLevel(item)
	local effectiveness = ix.wear.GetEffectiveness(item)
	local rawWarmth = tonumber(item.warmth) or 0
	local rawWaterproof = tonumber(item.waterproof) or 0
	local effRain = rawWaterproof * effectiveness
	local effWarmth = rawWarmth * effectiveness
	-- Below the lowest word band a garment can still shed a little rain or cold;
	-- "gone" is only said once there is effectively nothing left.
	local rain = Pick(self.RAIN_WORDS, effRain) or (effRain > 0.02 and "wearRainLow")
	local warmth = Pick(self.WARMTH_WORDS, effWarmth) or (effWarmth > 0.1 and "wearWarmthLow")

	local pocketCapacity = 0
	if (ix.body and isfunction(ix.body.GetItemPockets)) then
		for _, pocket in ipairs(ix.body.GetItemPockets(item)) do
			pocketCapacity = pocketCapacity + (tonumber(pocket.capacity) or 0)
		end
	end

	local weight = ix.wear.GetWeight(item)
	local dryWeight = ix.wear.GetWeight(item, 0)
	local weightText = weight > dryWeight + 0.05
		and L("wearWeightWet", string.format("%.1f", weight), string.format("%.1f", dryWeight))
		or L("wearWeight", string.format("%.1f", weight))

	-- Another player's wetness never replicates here, so a worn garment's weight would
	-- read dry (the datapad header already shows it with the subject's real wetness).
	local owner = isfunction(item.GetOwner) and item:GetOwner()
	local bOthersWorn = IsValid(owner) and owner != LocalPlayer() and item:GetData("equip")

	-- each row goes straight after the description, so they are added bottom first
	if (!bOthersWorn) then
		AddRow(tooltip, "wearWeight", weightText)
	end

	if (pocketCapacity > 0) then
		AddRow(tooltip, "wearPockets", L(level >= 3 and "wearPocketsWorn" or "wearPockets", pocketCapacity))
	end

	if (rain) then
		AddRow(tooltip, "wearRain", L(rain))
	elseif (rawWaterproof >= 0.15) then
		AddRow(tooltip, "wearRain", L("wearRainGone"))
	end

	if (warmth) then
		AddRow(tooltip, "wearWarmth", L(warmth))
	elseif (rawWarmth >= 0.5) then
		AddRow(tooltip, "wearWarmth", L("wearWarmthGone"))
	end

	local text = L(phrase)

	if (ix.wear.GetCeiling(item) < 100) then
		text = L("wearPatched", text)
	end

	local conditionColor

	if (level >= ix.wear.LEVEL_RUINED) then
		conditionColor = (ix.body and ix.body.COLORS and ix.body.COLORS.harm) or derma.GetColor("Warning", tooltip)
	elseif (level >= 3) then
		conditionColor = ix.body and ix.body.COLORS and ix.body.COLORS.pale
	end

	AddRow(tooltip, "wearCondition", text, conditionColor)
end
