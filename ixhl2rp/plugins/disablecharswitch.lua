
local PLUGIN = PLUGIN
PLUGIN.name = "Disable Charswitch"
PLUGIN.author = "Oebelysk"
PLUGIN.description = "Disables players from switching character if unconscious or dead."

function PLUGIN:CanPlayerUseCharacter(client)
    // if the player is in a ragdoll state, they cannot switch character
    if (IsValid(client.ixRagdoll)) then
        return false, "You cannot switch characters while unconscious!"
    end

    // if the player is dead and they have a loaded character, they cannot switch character
    if (!client:Alive() && (client:GetCharacter() ~= nil)) then
        return false, "You cannot switch characters while dead!"
    end
end
