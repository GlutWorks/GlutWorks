local playerMeta = FindMetaTable("Player")

function playerMeta:IsCombine()
	local faction = self:Team()
	return faction == FACTION_MPF or faction == FACTION_OTA
end

function playerMeta:IsDispatch()
	local name = self:Name()
	local faction = self:Team()
	local bStatus = faction == FACTION_OTA

	-- rank tokens come from the name, which only means something on a Civil Protection unit
	if (!bStatus and faction == FACTION_MPF) then
		for k, v in ipairs({ "SCN", "DvL", "SeC" }) do
			if (Schema:IsCombineRank(name, v)) then
				bStatus = true

				break
			end
		end
	end

	return bStatus
end
