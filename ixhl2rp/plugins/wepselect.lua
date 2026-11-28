local PLUGIN = PLUGIN

-- Extends Helix's wepselect (helix/plugins/wepselect.lua), which shares this ID and loads first into the same
-- table. While the immersion plugin hides the HUD there is no list of weapon names: the wheel and the slot keys
-- switch straight to a weapon, which the engine draws with its own animation, and a soft sound plays. With the
-- HUD shown (immersionHideHUD off) Helix's carousel is back as it was.

PLUGIN.description = "Switch weapons with the wheel or the slot keys, straight away and with nothing drawn."

-- A cloth-and-gear rustle as the hand goes to the next thing. WeaponSelectSound (Helix's hook) can replace it.
PLUGIN.switchSounds = {"npc/combine_soldier/gear2.wav", "npc/combine_soldier/gear4.wav", "npc/combine_soldier/gear6.wav"}
PLUGIN.switchVolume = 0.25

--- The weapon a press of `bind` switches to, with nothing drawn, and whether the press is taken.
-- The wheel steps through the carried weapons in the order Helix's list had them (`invprev`, wheel up, to the
-- next, `invnext` to the previous), wrapping round since there is no list to show an end; `slotN` picks the
-- Nth carried weapon (the last when there are fewer), as the list did. The rules the list kept still apply:
-- in a vehicle, with the physgun's trigger held (its wheel moves the held thing) and with a tool that scrolls,
-- the press is left alone (nil, false). A press that lands on the weapon already in hand, or a player with no
-- weapons (dead, or tied: Helix takes a tied player's weapons), is taken without a switch (nil, true). Any other
-- bind: nil, false. `from` is the weapon to step from when it is not the one in hand yet (a switch asked for that a
-- weapon's holster animation is still delaying); the weapon in hand by default.
function PLUGIN:GetDirectSwitch(client, bind, from)
	bind = string.lower(bind or "")

	local bNext = bind:find("invnext", 1, true) != nil
	local bPrevious = bind:find("invprev", 1, true) != nil
	local slot = tonumber(bind:match("slot(%d+)"))

	if (!bNext and !bPrevious and !slot) then
		return nil, false
	end

	if (!IsValid(client) or client:InVehicle()) then
		return nil, false
	end

	local active = client:GetActiveWeapon()
	local current = IsValid(from) and from or active

	if (IsValid(active)) then
		local class = active:GetClass()

		if (class == "weapon_physgun" and client:KeyDown(IN_ATTACK)) then
			return nil, false
		end

		if (!slot and class == "gmod_tool" and client.GetTool) then
			local tool = client:GetTool()

			if (tool and tool.Scroll != nil) then
				return nil, false
			end
		end
	end

	local weapons = client:GetWeapons()
	local count = #weapons

	if (count == 0 or !client:Alive() or client:IsRestricted()) then
		return nil, true
	end

	local index = 0

	for i, weapon in ipairs(weapons) do
		if (weapon == current) then
			index = i
			break
		end
	end

	local target

	if (slot) then
		target = weapons[math.Clamp(slot, 1, count)]
	elseif (index == 0) then
		target = bPrevious and weapons[1] or weapons[count]
	elseif (bPrevious) then
		target = weapons[index % count + 1]
	else
		target = weapons[(index - 2) % count + 1]
	end

	if (!IsValid(target) or target == current) then
		return nil, true
	end

	return target, true
end

if (CLIENT) then
	-- Helix's methods, kept across a Lua refresh of this file alone (a refresh of the whole gamemode runs Helix's
	-- file first, which defines them again).
	PLUGIN.stock = PLUGIN.stock or {}
	PLUGIN.own = PLUGIN.own or setmetatable({}, {__mode = "k"})

	for _, name in ipairs({"PlayerBindPress", "HUDPaint", "Think"}) do
		if (isfunction(PLUGIN[name]) and !PLUGIN.own[PLUGIN[name]]) then
			PLUGIN.stock[name] = PLUGIN[name]
		end
	end

	local function IsHidden()
		local immersion = ix.plugin.list.immersion

		return immersion != nil and immersion:IsHUDHidden(LocalPlayer())
	end

	function PLUGIN:PlaySwitchSound(weapon)
		local source = hook.Run("WeaponSelectSound", weapon)

		if (isstring(source)) then
			LocalPlayer():EmitSound(source)
			return
		end

		local sounds = self.switchSounds

		LocalPlayer():EmitSound(sounds[math.random(#sounds)], 0, math.random(95, 105), self.switchVolume, CHAN_STATIC)
	end

	-- How long a switch asked for is waited for when it has not reached the hand yet. A TFA weapon plays a holster
	-- animation first and then draws the weapon it was first asked for, whatever is asked after; a later tick is
	-- stepped on from the weapon asked for (not the one still in hand), and Think asks for it again once the hand has
	-- moved on.
	PLUGIN.pendingTime = 2

	function PLUGIN:PlayerBindPress(client, bind, bPressed, ...)
		-- While a world panel is open a slot key does not draw a weapon (worldui swallows the wheel itself, to
		-- scroll the panel).
		if (bPressed and ix.worldui and ix.worldui.panel and string.lower(bind or ""):find("slot%d")) then
			return true
		end

		if (!IsHidden()) then
			return self.stock.PlayerBindPress(self, client, bind, bPressed, ...)
		end

		if (!bPressed) then
			return
		end

		-- a weapon whose holster animation delays the switch is still in hand: step on from the one asked for
		local pending = self:GetPending(client)
		local weapon, bTaken = self:GetDirectSwitch(client, bind, pending)

		if (IsValid(weapon)) then
			if (!pending) then
				self.leaving = client:GetActiveWeapon()
			end

			input.SelectWeapon(weapon)
			self:PlaySwitchSound(weapon)

			self.pending = weapon
			self.pendingUntil = RealTime() + self.pendingTime
		end

		if (bTaken) then
			return true
		end
	end

	--- The weapon last asked for while it has not reached the hand yet (and is not too long in coming), or nil.
	function PLUGIN:GetPending(client)
		local pending = self.pending

		if (!IsValid(pending) or pending:GetOwner() != client or RealTime() > (self.pendingUntil or 0) or
			client:GetActiveWeapon() == pending) then
			self.pending = nil
			return nil
		end

		return pending
	end

	function PLUGIN:Think(...)
		if (self.stock.Think) then
			self.stock.Think(self, ...)
		end

		local client = LocalPlayer()

		if (!IsValid(client) or (self.nextPendingCheck or 0) > RealTime()) then
			return
		end

		self.nextPendingCheck = RealTime() + 0.1

		-- the hand has left the weapon it held but went to an earlier choice: ask for the latest one again
		local pending = self:GetPending(client)
		local active = client:GetActiveWeapon()

		if (pending and IsValid(active) and active != self.leaving) then
			input.SelectWeapon(pending)
		end
	end

	function PLUGIN:HUDPaint(...)
		if (IsHidden()) then
			self.alpha = 0
			self.alphaDelta = 0
			return
		end

		return self.stock.HUDPaint(self, ...)
	end

	PLUGIN.own[PLUGIN.PlayerBindPress] = true
	PLUGIN.own[PLUGIN.HUDPaint] = true
	PLUGIN.own[PLUGIN.Think] = true
end
