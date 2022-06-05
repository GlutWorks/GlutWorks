
PLUGIN.name = "Kick"
PLUGIN.author = "Oebelysk"
PLUGIN.description = "Adds /kickdoor functionality for Civil Protection."
local canKick = true 

ix.command.Add("kickdoor", {
    description = "Attempt to kick down the door.",
    adminOnly = false,

	OnRun = function(self, client, arguments)

	local entity = client:GetEyeTrace().Entity
	local stamina = client:GetLocalVar("stm", 0)
	local rand = math.random(1, 2)


	if(client:IsCombine()) then
		if (IsValid(entity) and entity:IsDoor() and !entity:GetNetVar("disabled")) then
			if (client:GetPos():Distance(entity:GetPos())< 100) then	   
				if (client:GetPos():Distance(entity:GetPos()) > 65) then
					if(stamina > 25) then
						-- need to find out how to check if client is in thirdperson or not
						-- client:ConCommand("ix_togglethirdperson")
						if canKick then
							canKick = false 	
							client:ConsumeStamina(25)
							client:ForceSequence("kickdoorbaton")
							timer.Simple( 1.7, function()
								canKick = true 
								entity:Fire("setspeed", 100)
								-- client:ConCommand("ix_togglethirdperson")
							end )
							timer.Simple( 0.8, function()
								if (rand == 1) then
									client:EmitSound("physics/wood/wood_plank_break1.wav", 90)
									entity:Fire("setspeed", 250)
									entity:Fire("unlock")
									entity:Fire("open", 1)
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
                client:Notify("You are not close enough!")
			end
		else
			client:Notify("You are not looking at a door!")
		end
	else
		client:Notify("You are not Civil Protection!")
    end
end
})