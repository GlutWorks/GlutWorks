
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

	local effectiveness = ix.wear.GetEffectiveness(item)
	local rain = Pick(self.RAIN_WORDS, (tonumber(item.waterproof) or 0) * effectiveness)
	local warmth = Pick(self.WARMTH_WORDS, (tonumber(item.warmth) or 0) * effectiveness)

	-- each row goes straight after the description, so they are added bottom first
	if (rain) then
		AddRow(tooltip, "wearRain", L(rain))
	end

	if (warmth) then
		AddRow(tooltip, "wearWarmth", L(warmth))
	end

	local level, phrase = ix.wear.GetLevel(item)
	local text = L(phrase)

	if (ix.wear.GetCeiling(item) < 100) then
		text = L("wearPatched", text)
	end

	AddRow(tooltip, "wearCondition", text, level >= 4 and derma.GetColor("Warning", tooltip) or nil)
end
