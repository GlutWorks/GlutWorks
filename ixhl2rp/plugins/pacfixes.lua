
PLUGIN.name = "Miscellaneous PAC Fixes"
PLUGIN.author = "Oebelysk"
PLUGIN.description = "Fixes multiple PAC issues."

function PLUGIN:OnCharacterGetup(target, ragdoll)
    local character = target:GetCharacter()
    local inventory = character:GetInventory()
    if target then
	    for _, v in pairs(inventory:GetItems()) do
		    if (target:GetActiveWeapon() != v and v:GetData("equip", true) and v.pacData) then
                target:AddPart(v.uniqueID, v)
	        end
        end
	end
end

function PLUGIN:OnCharacterWakeup(target, ragdoll)
    local character = target:GetCharacter()
    local inventory = character:GetInventory()
    if target then
	    for _, v in pairs(inventory:GetItems()) do
		    if (v:GetData("equip", true) and v.pacData) then
                if character:GetFaction() == FACTION_MPF and v.pacData then
                    target:AddPart(v.uniqueID .. "mpf", v)
                elseif target:IsFemale() and v.pacDataFemale then
                    target:AddPart(v.uniqueID .. "female", v)
                elseif !target:IsFemale() and v.pacDataMale then
                    target:AddPart(v.uniqueID .. "male", v)
                else
                    target:AddPart(v.uniqueID, v)
                end
	        end
        end
	end
end


function PLUGIN:OnCharacterWakeupWeapon(target, equippedweapon)
    local weapon = target:GetActiveWeapon()
    local character = target:GetCharacter()
    local inventory = character:GetInventory()
    if target and weapon then
        for _, v in pairs(inventory:GetItems()) do
		    if (v:GetData("equip", true) and v.pacData) then
                if (equippedweapon == v.class) then
                    if character:GetFaction() == FACTION_MPF and v.pacData then
                        target:RemovePart(v.uniqueID .. "mpf")
                    elseif target:IsFemale() and v.pacDataFemale then
                        target:RemovePart(v.uniqueID .. "female")
                    elseif !target:IsFemale() and v.pacDataMale then
                        target:RemovePart(v.uniqueID .. "male")
                    else
                        target:RemovePart(v.uniqueID)
                    end
                end
	        end
        end
    end
end

function PLUGIN:DoPlayerDeath(target, attacker, damageinfo)
    local curParts = target:GetParts()

    if (curParts) then
        target:ResetParts()
    end
end
