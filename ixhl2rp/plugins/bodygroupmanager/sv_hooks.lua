
util.AddNetworkString("ixBodygroupView")
util.AddNetworkString("ixBodygroupTableSet")

ix.log.AddType("bodygroupEditor", function(client, target)
	return string.format("%s has changed %s's bodygroups.", client:GetName(), target:GetName())
end)

net.Receive("ixBodygroupTableSet", function(length, client)
	if (!ix.command.HasAccess(client, "CharEditBodygroup")) then
		return
	end

	local target = net.ReadEntity()

	if (!IsValid(target) or !target:IsPlayer() or !target:GetCharacter()) then
		return
	end

	local groups = {}

	for k, v in pairs(net.ReadTable()) do
		k, v = tonumber(k), tonumber(v)

		-- only bodygroups and options the model really has, since these are saved with the character
		if (k and v and k % 1 == 0 and v % 1 == 0 and k >= 0 and k < target:GetNumBodyGroups() and
			v >= 0 and v < target:GetBodygroupCount(k)) then
			target:SetBodygroup(k, v)
			groups[k] = v
		end
	end

	target:GetCharacter():SetData("groups", groups)
	target:GetCharacter():Save()

	ix.log.Add(client, "bodygroupEditor", target)
end)
