
PLUGIN.name = "Ragdolls Take Damage"
PLUGIN.author = "Oebelysk"
PLUGIN.description = "Causes ragdolls to take damage."

function PLUGIN:PhysicsCollide( data, phys )
    print(data)
    print(phys)
end