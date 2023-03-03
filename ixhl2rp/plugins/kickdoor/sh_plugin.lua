
PLUGIN.name = "Kick"
PLUGIN.author = "Oebelysk"
PLUGIN.description = "Adds /kickdoor functionality for Civil Protection."
local canKick = true 

ix.command.Add("KickDoor", {
    description = "Attempt to kick down the door.",

	OnRun = function(self, client, arguments)

	local entity = client:GetEyeTrace().Entity
	local stamina = client:GetLocalVar("stm", 0)
	local rand = math.random(1, 2)
	local kickVelocity = client:GetAimVector() * 300

	if(client:IsCombine()) then
		if (IsValid(entity) and entity:GetClass() == "prop_door_rotating" and !entity:GetNetVar("disabled")) then
			if (client:GetVelocity() == Vector(0, 0, 0)) then
				if (client:GetPos():Distance(entity:GetPos()) < 100) then	   
					if (client:GetPos():Distance(entity:GetPos()) > 65) then
						if(stamina > 25) then
							-- need to find out how to check if client is in thirdperson or not
							print(ix.option.Get(client, "thirdpersonEnabled", false))
							if(!ix.option.Get(client, "thirdpersonEnabled", false)) then
								client:ConCommand("ix_togglethirdperson")
							end
							if canKick then
								canKick = false 	
								client:ConsumeStamina(25)
								client:ForceSequence("kickdoorbaton")
								timer.Simple( 1.7, function()
									canKick = true 
									if(!ix.option.Get(client, "thirdpersonEnabled", false)) then
										client:ConCommand("ix_togglethirdperson")
									end
								end )
								timer.Simple( 0.8, function()
									if (rand == 1) then
										client:EmitSound("physics/wood/wood_plank_break1.wav", 90)

										local effectTopHinge = EffectData()
										 	effectTopHinge:SetStart(entity:GetPos() + Vector(0, 0, 24))
										 	effectTopHinge:SetOrigin(entity:GetPos() + Vector(0, 0, 24))
										 	effectTopHinge:SetScale(5)
										util.Effect("GlassImpact", effectTopHinge)

										local effectBottomHinge = EffectData()
											effectBottomHinge:SetStart(entity:GetPos() - Vector(0, 0, 24))
											effectBottomHinge:SetOrigin(entity:GetPos() - Vector(0, 0, 24))
											effectBottomHinge:SetScale(5)
										util.Effect("GlassImpact", effectBottomHinge)

										entity:BlastDoor(kickVelocity, 120, false)
									else
										entity:EmitSound("physics/wood/wood_panel_impact_hard1.wav", 90)
									end
								end )
							else
								client:Notify("You are using this command too quickly!")
							end
						else
    						client:Notify("You don't have enough stamina!")
						end
					else
						client:Notify("You are too close to the door!")
					end
				else
    	            client:Notify("You are not close enough to the door!")
				end
			else
				client:Notify("You need to be standing still!")
			end
		else
			client:Notify("You are not looking at a door!")
		end
	else
		client:Notify("You are not Civil Protection!")
    end
end
})