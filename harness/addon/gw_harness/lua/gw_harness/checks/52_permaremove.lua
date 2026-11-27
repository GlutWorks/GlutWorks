-- Map entity removal (permaremove): a removed map entity is recorded.

local Lib = GWH.Lib
local Scoped, Replace = Lib.Scoped, Lib.Replace

GWH.Check("hygiene: removed map entities are recorded", function(fail)
	return Scoped(function(defer)
		local client = GWH.Bot()
		local plugin = ix.plugin.list.permaremove
		local saved = plugin:GetData({})
		defer(function() plugin:SetData(saved) end)
		plugin:SetData({})

		local target

		for _, v in ipairs(ents.GetAll()) do
			if (v:CreatedByMap() and v:MapCreationID() != -1 and v:GetClass() == "env_soundscape") then
				target = v
				break
			end
		end

		if (!target) then return {skipped = "no map entity to remove"} end

		local index = target:MapCreationID()
		Replace(defer, FindMetaTable("Player"), "GetEyeTraceNoCursor", function() return {Entity = target} end)
		ix.command.list.mapentremove:OnRun(client)

		if (plugin:GetData({})[1] != index) then fail("the removal was not saved") end

		plugin:LoadData()
	end)
end)
