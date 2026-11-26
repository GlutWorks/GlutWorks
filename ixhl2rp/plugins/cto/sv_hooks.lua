
local PLUGIN = PLUGIN

-- Yuck. No wonder Clockwork had low FPS, with plugins like these.
function PLUGIN:Tick()
	local curTime = CurTime()
	local networkedCameraData = {}
	
	if (!self.nextCameraTick or curTime >= self.nextCameraTick) then
		for combineCamera, data in pairs(self.cameraData) do
			if (!IsValid(combineCamera)) then
				self.cameraData[combineCamera] = nil
			elseif (self:isCameraEnabled(combineCamera)) then
				local camPos = combineCamera:GetPos()

				for client, _ in pairs(data) do
					if (!IsValid(client)) then
						data[client] = nil
					else
						if (camPos:Distance(client:GetPos()) > 450 or !combineCamera:IsLineOfSightClear(client)) then
							data[client] = nil
						elseif (#data[client] < 1) then
							local violations = {}
							local walkSpeed = ix.config.Get("walkSpeed")
							if (client:KeyDown(IN_SPEED) and client:GetVelocity():LengthSqr() >= (walkSpeed * walkSpeed)) then
								violations[#violations + 1] = self.VIOLATION_RUNNING
							end
							
							if (!client:OnGround() and client:WaterLevel() <= 0) then
								violations[#violations + 1] = self.VIOLATION_JUMPING
							end

							if (client:Crouching()) then
								violations[#violations + 1] = self.VIOLATION_CROUCHING
							end

							if (client:GetLocalVar("ragdoll")) then
								violations[#violations + 1] = self.VIOLATION_FALLEN_OVER
							end

							if (#violations > 0) then
								if (!client:IsCombine() and !client:GetNetVar("IsBiosignalGone")) then
									data[client] = violations

									combineCamera:Fire("SetIdle")
									combineCamera:Fire("SetAngry")

									Schema:AddCombineDisplayMessage("Movement violation(s) sighted by C-i" .. combineCamera:EntIndex() .. "...", Color(255, 128, 0, 255))
								end
							end
						end
					end
				end

				networkedCameraData[combineCamera:EntIndex()] = data
			else
				networkedCameraData[combineCamera:EntIndex()] = 0
			end
		end

		local receivers = self:GetBiosignalReceivers()
		local bHasCameras = next(networkedCameraData) != nil

		-- an empty table only needs sending once, to clear what clients last saw
		if (#receivers > 0 and (bHasCameras or self.bSentCameraData)) then
			net.Start("UpdateBiosignalCameraData")
				net.WriteTable(networkedCameraData)
			net.Send(receivers)

			self.bSentCameraData = bHasCameras
		end

		self.nextCameraTick = curTime + 1
	end

	-- this message also drives the clients' biosignal refresh, so it is sent periodically
	if (!self.nextBiosignalUpdate or curTime >= self.nextBiosignalUpdate) then
		local receivers = self:GetBiosignalReceivers()

		if (#receivers > 0) then
			self:SendHUDObjectives(receivers)
		end

		self.nextBiosignalUpdate = curTime + math.random(1, 3)
	end
end

function PLUGIN:PlayerSpawn(client)
	if (client:IsCombine()) then
		self:SendHUDObjectives(client)

		if (client:GetNetVar("IsBiosignalGone")) then
			if (ix.config.Get("useBiosignalSystem")) then
				client:Notify("Note: Your character currently has no biosignal.")
			else
				client:SetNetVar("IsBiosignalGone", false)
			end
		end
	end

	if (!self.fixedCameras) then
		for combineCamera, data in pairs(self.cameraData) do
			if (!combineCamera:HasSpawnFlags(SF_NPC_WAIT_FOR_SCRIPT)) then -- This is documented as the "Start Inactive" flag by Valve for combine cameras.
				combineCamera:Fire("Enable")
			end
		end

		self.fixedCameras = true
	end
end

function PLUGIN:OnCharacterFallover(client, entity, bFallenOver)
	if (client:IsCombine() and !client:GetNetVar("IsBiosignalGone")) then
		if (bFallenOver) then
			local location = client:GetArea() != "" and client:GetArea() or "unknown location"
			local digits = string.match(client:Name(), "%d%d%d%d?%d?") or 0

			Schema:AddCombineDisplayMessage("Downloading trauma packet...", Color(255, 255, 255, 255))
			Schema:AddCombineDisplayMessage("WARNING! Protection team unit " .. digits .. " lost consciousness at " .. location .. "...", Color(255, 0, 0, 255))
		end
	end
end

-- The schema's PlayerDeath still runs (scanner removal); this plugin replaces only its
-- biosignal announcement, with one that names the unit.
function PLUGIN:PlayerDeath(client, inflictor, attacker)
	-- remembered for CanHearCombineDeath, which runs after the biosignal is gone
	client.ixDiedWithBiosignal = client:IsCombine() and !client:GetNetVar("IsBiosignalGone")

	if (client.ixDiedWithBiosignal) then
		self:DoPostBiosignalLoss(client)
	end
end

function PLUGIN:ShouldAnnounceBiosignalLoss(client)
	return false
end

-- The schema picks the death sound (including the scanner ones) and plays it to the
-- Combine; units without a biosignal neither send nor receive it.
function PLUGIN:CanHearCombineDeath(listener, client)
	if (!client.ixDiedWithBiosignal or (listener != client and listener:GetNetVar("IsBiosignalGone"))) then
		return false
	end
end

function PLUGIN:PlayerLoadedCharacter(client, character)
	self:UpdateCIDTag(client)
end

function PLUGIN:PlayerCombineRequest(client, message)
	self:DispatchRequestSignal(client, message)
end

function PLUGIN:OnEntityCreated(entity)
	if (entity:GetClass() == "npc_combine_camera") then
		if (self.cameraData[entity] == nil) then
			self:SafelyPrepareCamera(entity)
		end
	end
end

function PLUGIN:SetupPlayerVisibility(client)
	for _, terminal in pairs(ents.FindByClass("ix_ctocameraterminal")) do
		local camera = terminal:GetNWEntity("camera")

		if (IsValid(camera) and client:IsLineOfSightClear(terminal)) then
			AddOriginToPVS(camera:GetPos() + Vector("0 0 -10"))
		end
	end
end
