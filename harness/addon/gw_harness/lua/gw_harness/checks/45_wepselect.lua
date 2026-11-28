-- Weapon switching (wepselect, extending Helix's): with no list, the wheel steps through the carried weapons
-- (wrapping round) and a slot key picks one, stepping on from a switch still on its way to the hand; the rules the
-- list kept still hold (a vehicle, the physgun's held trigger, a tool that scrolls, a dead player, a tied one, whose
-- weapons Helix takes), and Helix still lowers what is switched to. The sound, the absence of the list and slot keys
-- swallowed while a world panel is open are client-only and are judged in a play session.

local Lib = GWH.Lib
local Scoped, Replace, Expect = Lib.Scoped, Lib.Replace, Lib.Expect

GWH.Check("wepselect: the wheel and the slot keys switch straight to a weapon, and the old rules hold", function(fail)
	local plugin = ix.plugin.list.wepselect
	local bot = GWH.Bot()
	if (!plugin or !plugin.GetDirectSwitch) then return fail("wepselect is not extended (no GetDirectSwitch)") end
	if (!bot) then return fail("no bot") end

	Scoped(function(defer)
		local given = {}

		defer(function()
			Lib.ResetBotFully(bot)

			for _, class in ipairs(given) do
				if (bot:HasWeapon(class)) then bot:StripWeapon(class) end
			end
		end)

		Lib.ResetBotFully(bot)

		for _, class in ipairs({"weapon_crowbar", "weapon_pistol", "weapon_physgun", "gmod_tool"}) do
			if (!bot:HasWeapon(class)) then
				bot:Give(class)
				given[#given + 1] = class
			end
		end

		local weapons = bot:GetWeapons()
		local count = #weapons
		if (count < 4) then return fail("the bot has " .. count .. " weapons, expected at least 4") end

		local function Name(weapon)
			return IsValid(weapon) and weapon:GetClass() or "nothing"
		end

		local function Switch(bind, from)
			local weapon, bTaken = plugin:GetDirectSwitch(bot, bind, from)
			return Name(weapon) .. (bTaken and "" or " (left alone)")
		end

		local function Hold(weapon)
			bot:SelectWeapon(weapon:GetClass())
			if (bot:GetActiveWeapon() != weapon) then fail("could not put " .. weapon:GetClass() .. " in hand") end
		end

		Hold(weapons[1])
		Expect(fail, "wheel up from the first", Switch("invprev"), Name(weapons[2]))
		Expect(fail, "wheel down from the first wraps to the last", Switch("invnext"), Name(weapons[count]))
		Expect(fail, "slot 2", Switch("slot2"), Name(weapons[2]))
		Expect(fail, "a slot past the last", Switch("slot9"), Name(weapons[count]))
		Expect(fail, "the slot of the weapon in hand", Switch("slot1"), "nothing")
		Expect(fail, "another bind", Switch("+attack"), "nothing (left alone)")

		Hold(weapons[count])
		Expect(fail, "wheel up from the last wraps to the first", Switch("invprev"), Name(weapons[1]))

		-- two quick ticks: the second steps on from the first's target while the first is still holstering
		Hold(weapons[1])
		Expect(fail, "second tick steps from the pending weapon", Switch("invprev", weapons[2]), Name(weapons[3]))
		Expect(fail, "back to the weapon still in hand", Switch("invnext", weapons[2]), Name(weapons[1]))

		-- the physgun's wheel moves what it holds while its trigger is down
		local player = FindMetaTable("Player")

		bot:SelectWeapon("weapon_physgun")

		Scoped(function(inner)
			Replace(inner, player, "KeyDown", function(self, key) return key == IN_ATTACK end)
			Expect(fail, "physgun trigger held", Switch("invprev"), "nothing (left alone)")
		end)

		if (Switch("invprev") == "nothing (left alone)") then fail("the physgun's trigger up still leaves the wheel alone") end

		Scoped(function(inner)
			Replace(inner, player, "InVehicle", function() return true end)
			Expect(fail, "in a vehicle", Switch("invprev"), "nothing (left alone)")
		end)

		-- a tool that scrolls keeps the wheel; a slot key still switches
		bot:SelectWeapon("gmod_tool")

		if (bot:GetActiveWeapon():GetClass() == "gmod_tool") then
			Scoped(function(inner)
				Replace(inner, player, "GetTool", function() return {Scroll = function() end} end)
				Expect(fail, "a scrolling tool", Switch("invprev"), "nothing (left alone)")
				Expect(fail, "a scrolling tool, slot key", Switch("slot1"), Name(weapons[1]))
			end)
		else
			fail("could not put the tool gun in hand")
		end

		-- tied: the press is taken and nothing is switched to, whatever is still carried (Helix takes the weapons
		-- too, but the removed ones linger to the end of the frame, and SetRestricted cannot give them back in the
		-- same frame, so the net var behind IsRestricted is set instead)
		Scoped(function(inner)
			inner(function() bot:SetNetVar("restricted", nil) end)
			bot:SetNetVar("restricted", true)
			Expect(fail, "tied", Switch("invprev"), "nothing")
			Expect(fail, "tied, slot key", Switch("slot2"), "nothing")
		end)

		-- Helix lowers whatever is switched to
		Hold(weapons[1])
		bot:SetWepRaised(true)
		Hold(weapons[2])
		Expect(fail, "switched to and lowered", bot:IsWepRaised(), false)

		bot:KillSilent()
		Expect(fail, "dead", Switch("invprev"), "nothing")
	end)
end)
