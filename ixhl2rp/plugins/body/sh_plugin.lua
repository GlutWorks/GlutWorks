
local PLUGIN = PLUGIN

PLUGIN.name = "Body"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Canonical body region map and persistent per-region wounds with felt effects and bandage treatment."
PLUGIN.readme = [[
Defines the single canonical body region vocabulary (`ix.body` in libs/sh_body.lua):
`head`, `chest`, `waist`, `arms`, `legs`, `feet`.

Hits (`ix.body.HitGroupToRegion`), garment coverage (`ITEM.regions`, `ITEM.regionWearShare`,
`ix.body.CoversRegion`, `ix.body.GetCoveringGarments`), garment pockets and concealment
(`ITEM.pockets`, `ix.body.GetItemPockets`, `ix.body.BASE_PLACES`), frisk order
(`ix.body.FRISK_ORDER`), and persistent regional wounds (`libs/sh_wounds.lua`, `sv_wounds.lua`,
`cl_wounds.lua`) all use the same region IDs with no translation between plugins.
]]

ix.config.Add("bodyWoundsEnabled", true, "Whether slash and gunshot hits leave persistent regional wounds with felt effects.", nil, {
	category = "Body"
})

ix.config.Add("bodyWoundHealTime", 180, "Seconds for a full-severity dressed wound to heal completely.", nil, {
	data = {min = 30, max = 1800},
	category = "Body"
})

-- Shared so client prediction and server movement agree without rubber-banding.
-- Scales movement speed and returns nothing so exposure, stamina and other hooks still run.
function PLUGIN:SetupMove(client, moveData)
	if (!ix.config.Get("bodyWoundsEnabled", true) or !IsValid(client) or !client:Alive()) then
		return
	end

	if (client:GetMoveType() == MOVETYPE_NOCLIP or client:GetObserverMode() != OBS_MODE_NONE) then
		return
	end

	local scale = ix.body.GetLegSpeedScale(client)

	if (scale < 1) then
		moveData:SetMaxClientSpeed(moveData:GetMaxClientSpeed() * scale)
		moveData:SetMaxSpeed(moveData:GetMaxSpeed() * scale)
	end
end

--- Combined stamina regeneration multiplier from survival needs and thermal exposure.
function ix.body.GetStaminaRegenScale(client)
	if (!IsValid(client)) then
		return 1
	end

	local character = client:GetCharacter()

	if (!character) then
		return 1
	end

	local scale = 1
	local survival = ix.plugin.Get("survivaladditions")

	if (survival and isfunction(survival.GetStaminaScale)) then
		scale = scale * survival:GetStaminaScale(character)
	end

	if (ix.exposure and isfunction(ix.exposure.GetStaminaRegenScale) and ix.exposure.Applies(client) and character.GetTemperature) then
		scale = scale * ix.exposure.GetStaminaRegenScale(character:GetTemperature())
	end

	return scale
end

-- Shared so client prediction and server stamina agree, and one hook combines all regen penalties.
function PLUGIN:AdjustStaminaOffset(client, offset)
	if (!isnumber(offset) or offset <= 0) then
		return
	end

	local scale = ix.body.GetStaminaRegenScale(client)

	if (scale < 1) then
		return offset * scale
	end
end

ix.util.Include("sv_wounds.lua")
ix.util.Include("cl_wounds.lua")

ix.command.Add("CharSetWound", {
	description = "@cmdCharSetWound",
	privilege = "Manage Character Attributes",
	adminOnly = true,
	arguments = {
		ix.type.character,
		ix.type.string,
		ix.type.string,
		ix.type.number
	},
	OnRun = function(self, client, target, region, kind, severity)
		region = string.lower(string.Trim(region or ""))
		kind = string.lower(string.Trim(kind or ""))

		if (!ix.body.IsRegion(region)) then
			return "@bodyInvalidRegion"
		end

		local amount = math.Round(tonumber(severity) or 0)
		local targetClient = target:GetPlayer()

		if (amount <= 0) then
			if (IsValid(targetClient)) then
				ix.body.RemoveWound(targetClient, region)
			else
				local wounds = target:GetData("wounds", {})
				wounds[region] = nil
				target:SetData("wounds", wounds)
			end

			for _, v in ipairs(player.GetAll()) do
				if (self:OnCheckAccess(v) or v == targetClient) then
					v:NotifyLocalized("bodyClearedRegionWound", client:GetName(), target:GetName(), region)
				end
			end

			return
		end

		if (!ix.body.IsWoundKind(kind)) then
			return "@bodyInvalidWoundKind"
		end

		amount = math.Clamp(amount, 1, 100)

		if (IsValid(targetClient)) then
			ix.body.SetWound(targetClient, region, kind, amount)
		else
			local wounds = target:GetData("wounds", {})
			wounds[region] = {
				kind = kind,
				region = region,
				severity = amount,
				state = "open",
				dressedAt = nil
			}
			target:SetData("wounds", wounds)
		end

		for _, v in ipairs(player.GetAll()) do
			if (self:OnCheckAccess(v) or v == targetClient) then
				v:NotifyLocalized("bodySetWound", client:GetName(), kind, amount, target:GetName(), region)
			end
		end
	end
})

ix.command.Add("CharClearWounds", {
	description = "@cmdCharClearWounds",
	privilege = "Manage Character Attributes",
	adminOnly = true,
	arguments = {
		ix.type.character
	},
	OnRun = function(self, client, target)
		local targetClient = target:GetPlayer()

		if (IsValid(targetClient)) then
			ix.body.ClearWounds(targetClient)
		else
			target:SetData("wounds", {})
		end

		for _, v in ipairs(player.GetAll()) do
			if (self:OnCheckAccess(v) or v == targetClient) then
				v:NotifyLocalized("bodyClearedWounds", client:GetName(), target:GetName())
			end
		end
	end
})
