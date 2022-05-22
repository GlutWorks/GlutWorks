
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
                target:AddPart(v.uniqueID, v)
	        end
        end
	end
end


function PLUGIN:OnCharacterWakeupWeapon(target, equippedweapon)
    local weapon = target:GetActiveWeapon()
    local character = target:GetCharacter()
    local inventory = character:GetInventory()
    print(equippedweapon)
    if target and weapon then
        for _, v in pairs(inventory:GetItems()) do
		    if (v:GetData("equip", true) and v.pacData) then
                if (equippedweapon == v.class) then
                    print("balls")
                    target:RemovePart(v.uniqueID)
                end
	        end
        end
    end
end
