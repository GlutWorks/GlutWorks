
local PLUGIN = PLUGIN

PLUGIN.name = "Stacking"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Item stacks: one instance holding data.quantity, capped by the definition's stackLimit."
PLUGIN.readme = [[
An item definition becomes stackable by setting `ITEM.stackLimit`. A stack is one item instance whose
quantity is `data.quantity` (1 when unset). Optional fields:

- `ITEM.stackStep`: the smallest amount a stack can hold or be split into (default 1). Steps below 1 must
  be 1/n, e.g. 0.1 for kilograms in tenths.
- `ITEM.stackUnit`: the unit shown after the quantity, e.g. "kg" or "gears".

Every stackable definition receives the members of `base_stackable` (quantity on the icon and in the
tooltip, Combine by dragging one stack onto another, Split, and a pickup that merges into partial stacks),
unless the definition already defines that member itself.

Code that moves quantities uses `ix.stack.*` (see libs/sh_stack.lua). `inventory:Add(uniqueID, n, data)`
keeps its stock meaning for non-stackables; for a stackable with no position given it adds
n * (data.quantity or 1) merged into existing stacks, and only when all of it fits.
]]

ix.util.Include("sv_hooks.lua", "server")

-- Runs after every plugin has registered its items, so definitions from plugins that load before this one
-- (glutcraft, mining) get the stack members too.
function PLUGIN:InitializedPlugins()
	ix.stack.ApplyBaseToAll()
end

function PLUGIN:OnReloaded()
	ix.stack.ApplyBaseToAll()
end
