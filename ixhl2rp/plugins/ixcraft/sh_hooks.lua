
local PLUGIN = PLUGIN

-- Loads the recipes/ and stations/ folders of every plugin seen so far (DoPluginIncludes in
-- libs/sh_crafting.lua), each once per load. OnLoaded runs as soon as this plugin has loaded, before the
-- plugins after it, so their folders are picked up in InitializedPlugins.
function PLUGIN:LoadCraftingPaths()
	for _, path in ipairs(self.paths or {}) do
		if (!self.loadedPaths[path]) then
			self.loadedPaths[path] = true
			self.craft.LoadFromDir(path.."/recipes", "recipe")
			self.craft.LoadFromDir(path.."/stations", "station")
		end
	end
end

function PLUGIN:OnLoaded()
	self.loadedPaths = {}
	self:LoadCraftingPaths()
end

function PLUGIN:InitializedPlugins()
	self.loadedPaths = self.loadedPaths or {}
	self:LoadCraftingPaths()
end
