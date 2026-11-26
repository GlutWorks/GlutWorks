
local PLUGIN = PLUGIN

PLUGIN.name = "Context Menu Options"
PLUGIN.author = "Gary Tate"
PLUGIN.description = "Adds several context options on players."
PLUGIN.readme = [[
Adds several context options on players.

Support for this plugin can be found here: https://discord.gg/mntpDMU
]]
PLUGIN.license = [[
The MIT License (MIT)
Copyright (c) 2020 Gary Tate
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

local PRIVILEGE = "Helix - Admin Context Options"

CAMI.RegisterPrivilege({
	Name = PRIVILEGE,
	MinAccess = "admin"
})

local function CanEditPlayer(entity, client)
	return CAMI.PlayerHasAccess(client, PRIVILEGE, nil) and IsValid(entity) and entity:IsPlayer()
end

-- Filter only runs in the sender's own context menu, so every receiver has to repeat it on what it was sent.
local function ReadTarget(client)
	local entity = net.ReadEntity()

	if (CanEditPlayer(entity, client)) then
		return entity
	end
end

properties.Add("ixViewPlayerProperty", {
	MenuLabel = "#View Player",
	Order = 1,
	MenuIcon = "icon16/user.png",
	Format = "%s | %s\nHealth: %s\nArmor: %s",

	Filter = function(self, entity, client)
		return CanEditPlayer(entity, client)
	end,

	Action = function(self, entity)
		self:MsgStart()
			net.WriteEntity(entity)
		self:MsgEnd()
	end,

	Receive = function(self, length, client)
		local target = ReadTarget(client)

		if (target) then
			-- not NotifyLocalized: a "%" in the player's name would be treated as a format code
			client:Notify(string.format(self.Format, target:Nick(), target:SteamID(), target:Health(), target:Armor()))
		end
	end
})

properties.Add("ixSetHealthProperty", {
	MenuLabel = "#Health",
	Order = 2,
	MenuIcon = "icon16/heart.png",

	Filter = function(self, entity, client)
		return CanEditPlayer(entity, client)
	end,

	MenuOpen = function(self, option, entity, trace)
		local submenu = option:AddSubMenu()

		for i = 100, 0, -25 do
			submenu:AddOption(i, function() self:SetHealth(entity, i) end)
		end
	end,

	Action = function(self, entity)
		-- not used
	end,

	SetHealth = function(self, target, health)
		self:MsgStart()
			net.WriteEntity(target)
			net.WriteUInt(health, 8)
		self:MsgEnd()
	end,

	Receive = function(self, length, client)
		local target = ReadTarget(client)

		if (target and target:Alive()) then
			local health = math.min(net.ReadUInt(8), 100)

			target:SetHealth(health)

			if (health == 0) then
				target:Kill()
			end
		end
	end
})

properties.Add("ixSetArmorProperty", {
	MenuLabel = "#Armor",
	Order = 3,
	MenuIcon = "icon16/shield.png",

	Filter = function(self, entity, client)
		return CanEditPlayer(entity, client)
	end,

	MenuOpen = function(self, option, entity, trace)
		local submenu = option:AddSubMenu()

		for i = 100, 0, -25 do
			submenu:AddOption(i, function() self:SetArmor(entity, i) end)
		end
	end,

	Action = function(self, entity)
		-- not used
	end,

	SetArmor = function(self, target, armor)
		self:MsgStart()
			net.WriteEntity(target)
			net.WriteUInt(armor, 8)
		self:MsgEnd()
	end,

	Receive = function(self, length, client)
		local target = ReadTarget(client)

		if (target) then
			target:SetArmor(math.min(net.ReadUInt(8), 100))
		end
	end
})

properties.Add("ixSetDescriptionProperty", {
	MenuLabel = "#Edit Description",
	Order = 4,
	MenuIcon = "icon16/book_edit.png",

	Filter = function(self, entity, client)
		return CanEditPlayer(entity, client)
	end,

	Action = function(self, entity)
		self:MsgStart()
			net.WriteEntity(entity)
		self:MsgEnd()
	end,

	Receive = function(self, length, client)
		local target = ReadTarget(client)
		local character = target and target:GetCharacter()

		if (!character) then
			return
		end

		client:RequestString("Set the character's description.", "New Description", function(text)
			-- the target may have left or switched characters while this was being typed
			if (!IsValid(target) or target:GetCharacter() != character) then
				return
			end

			local result, fault, count = ix.char.vars.description:OnValidate(text)

			if (result == false) then
				client:NotifyLocalized(fault, count)
				return
			end

			character:SetDescription(result)
		end, character:GetDescription())
	end
})
