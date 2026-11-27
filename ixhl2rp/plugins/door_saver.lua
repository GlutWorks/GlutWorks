
local PLUGIN = PLUGIN
PLUGIN.name = "DoorSaver"
PLUGIN.author = "Taxin2012"
PLUGIN.description = "Saves purchased by players doors."
PLUGIN.license = [[Copyright 2019 Taxin2012
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.]]

-- All keyed by the door's map creation ID.
PLUGIN.DOORS_BUFFER = PLUGIN.DOORS_BUFFER or {} -- owning character ID
PLUGIN.DOORS_ACCESS_BUFFER = PLUGIN.DOORS_ACCESS_BUFFER or {} -- {[character ID] = access level} for non-owners
PLUGIN.DOORS_TITLES_BUFFER = PLUGIN.DOORS_TITLES_BUFFER or {} -- title shown on the door


if (SERVER) then
	local DOORS_PL = ix.plugin.Get("doors")

	if (!DOORS_PL) then
		ErrorNoHalt("Error: No Doors plugin found!\n")
		return
	end

	local function GetSavedDoor(doorID)
		local door = ents.GetMapCreatedEntity(doorID)

		if (IsValid(door) and door:IsDoor() and !door:GetNetVar("disabled")) then
			return door
		end
	end

	local function SetOwnable(door, bOwnable)
		door:SetNetVar("ownable", bOwnable)

		DOORS_PL:CallOnDoorChildren(door, function(child)
			child:SetNetVar("ownable", bOwnable)
		end)
	end

	-- The live access list is keyed by player, so it is copied out by character ID while it still means something,
	-- which is only while the owning character is holding the door.
	function PLUGIN:CaptureDoorAccess(doorID, door)
		local owner = door:GetDTEntity(0)
		local ownerCharacter = IsValid(owner) and owner:IsPlayer() and owner:GetCharacter()

		if (!ownerCharacter or ownerCharacter:GetID() != self.DOORS_BUFFER[doorID]) then
			return
		end

		-- characters that are not being played right now keep what was saved for them
		local access = self.DOORS_ACCESS_BUFFER[doorID] or {}

		for client, level in pairs(door.ixAccess or {}) do
			local character = IsValid(client) and client != owner and client:GetCharacter()

			if (character) then
				access[character:GetID()] = level > DOOR_NONE and level or nil
			end
		end

		self.DOORS_ACCESS_BUFFER[doorID] = access
		self.DOORS_TITLES_BUFFER[doorID] = door:GetNetVar("title", door:GetNetVar("name", "Purchased"))
	end

	function PLUGIN:CaptureAccess()
		for doorID in pairs(self.DOORS_BUFFER) do
			local door = GetSavedDoor(doorID)

			if (door) then
				self:CaptureDoorAccess(doorID, door)
			end
		end
	end

	-- The door stays bought, but nobody is holding it, so nobody else may buy it.
	function PLUGIN:ReleaseDoor(door)
		door:RemoveDoorAccessData()
		SetOwnable(door, nil)
	end

	function PLUGIN:ClaimDoor(doorID, door, client, character)
		self:CaptureDoorAccess(doorID, door)

		SetOwnable(door, true)
		door:SetDTEntity(0, client)

		DOORS_PL:CallOnDoorChildren(door, function(child)
			child:SetDTEntity(0, client)
		end)

		local access = self.DOORS_ACCESS_BUFFER[doorID] or {}
		door.ixAccess = {[client] = DOOR_OWNER}

		for _, v in player.Iterator() do
			local other = v != client and v:GetCharacter()

			if (other) then
				door.ixAccess[v] = access[other:GetID()]
			end
		end

		-- the doors plugin releases the doors in this list when the character is left
		local doors = character:GetVar("doors") or {}

		if (!table.HasValue(doors, door)) then
			doors[#doors + 1] = door
		end

		character:SetVar("doors", doors, true)
	end

	-- Takes a player who is leaving a character off every saved door.
	function PLUGIN:DetachPlayer(client, character)
		self:CaptureAccess()

		local characterID = character and character:GetID()

		for doorID, ownerID in pairs(self.DOORS_BUFFER) do
			local door = GetSavedDoor(doorID)

			if (!door) then
				continue
			end

			if (ownerID == characterID or door:GetDTEntity(0) == client) then
				self:ReleaseDoor(door)
			elseif (door.ixAccess) then
				door.ixAccess[client] = nil
			end
		end
	end

	-- Gives a player the doors their character owns, and the access it holds on other owners' doors.
	function PLUGIN:RestoreDoors(client, character)
		local characterID = character:GetID()

		for doorID, ownerID in pairs(self.DOORS_BUFFER) do
			local door = GetSavedDoor(doorID)

			if (!door) then
				continue
			end

			if (ownerID == characterID) then
				self:ClaimDoor(doorID, door, client, character)
			elseif (door:GetDTEntity(0) == client) then
				-- still held by a character this player was kicked from, which nothing else cleans up
				self:ReleaseDoor(door)
			elseif (IsValid(door:GetDTEntity(0)) and door.ixAccess) then
				local access = self.DOORS_ACCESS_BUFFER[doorID]
				door.ixAccess[client] = access and access[characterID]
			end
		end
	end

	function PLUGIN:LoadData()
		local data = self:GetData() or {}
		local doors, access, titles = {}, {}, {}

		for doorID, characterID in pairs(data.doors_buff or {}) do
			doorID, characterID = tonumber(doorID), tonumber(characterID)

			if (doorID and characterID) then
				doors[doorID] = characterID
			end
		end

		-- Old saves hold access under "doors_acc_buff", keyed by player entities that no longer exist. It cannot be
		-- recovered, so it is not read.
		for doorID, list in pairs(data.charAccess or {}) do
			doorID = tonumber(doorID)

			if (doorID and doors[doorID] and istable(list)) then
				access[doorID] = {}

				for characterID, level in pairs(list) do
					characterID, level = tonumber(characterID), tonumber(level)

					if (characterID and level) then
						access[doorID][characterID] = level
					end
				end
			end
		end

		for doorID, title in pairs(data.titles or {}) do
			doorID = tonumber(doorID)

			if (doorID and doors[doorID]) then
				titles[doorID] = tostring(title)
			end
		end

		self.DOORS_BUFFER = doors
		self.DOORS_ACCESS_BUFFER = access
		self.DOORS_TITLES_BUFFER = titles
	end

	-- Waits for every LoadData, so the doors plugin has restored its door settings and parent/child links.
	function PLUGIN:PostLoadData()
		for doorID in pairs(self.DOORS_BUFFER) do
			local door = GetSavedDoor(doorID)

			if (door) then
				if (self.DOORS_TITLES_BUFFER[doorID]) then
					door:SetNetVar("title", self.DOORS_TITLES_BUFFER[doorID])
				end

				SetOwnable(door, nil)
				door:Fire("Lock")
			end
		end

		-- owners are still connected after a map cleanup
		for _, v in player.Iterator() do
			local character = v:GetCharacter()

			if (character) then
				self:RestoreDoors(v, character)
			end
		end
	end

	function PLUGIN:SaveDoors()
		self:SetData({
			doors_buff = self.DOORS_BUFFER,
			charAccess = self.DOORS_ACCESS_BUFFER,
			titles = self.DOORS_TITLES_BUFFER
		})
	end

	function PLUGIN:SaveData()
		self:CaptureAccess()
		self:SaveDoors()
	end

	-- ix_wipedb starts character IDs again from 1, so saved owners and access lists would pass
	-- to whichever new characters get the old IDs.
	function PLUGIN:OnWipeTables()
		self.DOORS_BUFFER = {}
		self.DOORS_ACCESS_BUFFER = {}
		self.DOORS_TITLES_BUFFER = {}
		self:SaveDoors()
	end

	function PLUGIN:OnPlayerPurchaseDoor(client, door, bBuying)
		local character = client:GetCharacter()
		local doorID = door:MapCreationID()

		-- doors spawned at runtime have no ID that survives a restart
		if (!character or doorID == -1) then
			return
		end

		self.DOORS_BUFFER[doorID] = bBuying and character:GetID() or nil
		self.DOORS_ACCESS_BUFFER[doorID] = nil
		self.DOORS_TITLES_BUFFER[doorID] = nil

		self:SaveDoors()
	end

	function PLUGIN:PrePlayerLoadedCharacter(client, character, lastCharacter)
		if (lastCharacter) then
			self:DetachPlayer(client, lastCharacter)
		end
	end

	function PLUGIN:PlayerLoadedCharacter(client, character)
		self:RestoreDoors(client, character)
		self:SaveDoors()
	end

	function PLUGIN:PlayerDisconnected(client)
		self:DetachPlayer(client, client:GetCharacter())
		self:SaveDoors()
	end

	function PLUGIN:CharacterDeleted(client, id)
		for doorID, ownerID in pairs(self.DOORS_BUFFER) do
			if (ownerID != id) then
				continue
			end

			self.DOORS_BUFFER[doorID] = nil
			self.DOORS_ACCESS_BUFFER[doorID] = nil
			self.DOORS_TITLES_BUFFER[doorID] = nil

			local door = GetSavedDoor(doorID)

			if (door) then
				door:RemoveDoorAccessData()
				door:SetNetVar("title", nil)
				SetOwnable(door, true)
			end
		end

		for _, access in pairs(self.DOORS_ACCESS_BUFFER) do
			access[id] = nil
		end

		self:SaveDoors()
	end

	-- Every path that strips a door's access goes through this method, including the doors plugin's own character
	-- switch and disconnect hooks, which may run before ours. Wrapping it is how the access is seen first.
	local entityMeta = FindMetaTable("Entity")
	entityMeta.ixRemoveDoorAccessData = entityMeta.ixRemoveDoorAccessData or entityMeta.RemoveDoorAccessData

	function entityMeta:RemoveDoorAccessData()
		local doorID = self:MapCreationID()

		if (PLUGIN.DOORS_BUFFER[doorID]) then
			PLUGIN:CaptureDoorAccess(doorID, self)
		end

		self:ixRemoveDoorAccessData()
	end
end
