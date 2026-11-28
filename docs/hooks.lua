-- luacheck: ignore 111

--[[--
Hooks fired by GlutWorks code (`ixhl2rp/schema`, `ixhl2rp/entities`, `ixhl2rp/plugins`) that Helix
neither fires nor documents.

This file is documentation only. It sits outside the gamemode and is never loaded by the game. Helix's own
hooks are documented in `helix/docs/hooks/plugin.lua`, `class.lua` and `faction.lua`.

Implement a hook as `PLUGIN:Name(...)` in a plugin, `Schema:Name(...)` in the schema, or with `hook.Add`.
Helix's `hook.Call` (`helix/gamemode/core/libs/sh_plugin.lua`) runs the implementations in this order:

1. plugin methods, in no fixed order;
2. the `Schema` method;
3. `hook.Add` handlers and the gamemode.

It stops at the first non-nil return. A value returned by a plugin therefore overrides the schema's
implementation. Where a hook's result is "ignored", returning a value still skips every implementation after
yours, including the firing plugin's own, so return nothing.
]]
-- @hooks GlutWorks

-- Schema: schema/sh_commands.lua, schema/sv_hooks.lua, schema/sv_schema.lua, schema/derma

--- Whether a player may open another character's Combine data note with `/ViewData`. This is the schema's
-- short note stored in character data `combineData`. It is not the `datafile` plugin.
-- Fired by the `/ViewData` command in `schema/sh_commands.lua` once the target character's player is valid.
-- @realm server
-- @player client Player running the command
-- @player target Player whose character's note would be shown
-- @treturn bool `true` opens the note. `false` or `nil` refuses it with "cantViewData".
-- @usage function PLUGIN:CanPlayerViewData(client, target)
-- 	if (target:Team() == FACTION_OTA) then
-- 		return false -- nobody reads Overwatch notes
-- 	end
-- end
--
-- Implemented by `Schema:CanPlayerViewData` in `schema/sh_hooks.lua`. That version allows a Combine player to
-- view a target who is neither Combine nor in the administrator faction. A plugin that returns `nil` leaves
-- the decision to the schema.
function CanPlayerViewData(client, target)
end

--- Whether a player may change another character's Combine data note.
-- Fired in two places:
--
-- - On the server, by the `ViewDataUpdate` netstream receiver in `schema/sv_hooks.lua`, before the text is
-- saved to the target's `combineData` and announced to the Combine.
-- - On the client, by the view-data panel in `schema/derma/cl_viewdata.lua`, which disables the text box
-- when the result is not truthy.
-- @realm shared
-- @player client Player editing the note (`LocalPlayer()` on the client)
-- @player target Player whose character's note is being edited
-- @treturn bool `true` allows the edit. `false` or `nil` drops it on the server and makes the box read-only
-- on the client.
-- @usage function PLUGIN:CanPlayerEditData(client, target)
-- 	if (client:IsRestricted()) then
-- 		return false
-- 	end
-- end
--
-- Implemented by `Schema:CanPlayerEditData` in `schema/sh_hooks.lua`, using the same rule as
-- `CanPlayerViewData`.
function CanPlayerEditData(client, target)
end

--- Whether a player may open the Combine objectives with `/ViewObjectives`.
-- Fired by the `/ViewObjectives` command in `schema/sh_commands.lua`.
-- @realm server
-- @player client Player running the command
-- @treturn bool `true` sends the objectives. `false` or `nil` refuses with "noPerm".
-- @usage function PLUGIN:CanPlayerViewObjectives(client)
-- 	return client:Team() == FACTION_ADMIN or nil
-- end
--
-- Implemented by `Schema:CanPlayerViewObjectives` in `schema/sh_hooks.lua`, which allows any Combine player.
function CanPlayerViewObjectives(client)
end

--- Whether a player may change the Combine objectives.
-- Fired in two places:
--
-- - On the server, by the `ViewObjectivesUpdate` netstream receiver in `schema/sv_hooks.lua`, before the
-- text is saved and announced.
-- - On the client, by the objectives panel in `schema/derma/cl_viewobjectives.lua`, which disables the text
-- box when the result is not truthy.
-- @realm shared
-- @player client Player editing the objectives (`LocalPlayer()` on the client)
-- @treturn bool `true` allows the edit. `false` or `nil` drops it on the server and makes the box read-only
-- on the client.
-- @usage function PLUGIN:CanPlayerEditObjectives(client)
-- 	if (client:IsAdmin()) then
-- 		return true
-- 	end
-- end
--
-- Implemented by `Schema:CanPlayerEditObjectives` in `schema/sh_hooks.lua`. That version allows OTA and
-- Combine players with a command rank (`Schema:HasCommandRank`).
function CanPlayerEditObjectives(client)
end

--- The name shown as the title of a searched player's inventory window.
-- Fired by `Schema:SearchPlayer` in `schema/sv_schema.lua`, which is called by `/CharSearch` on a tied
-- player.
-- @realm server
-- @player target Player being searched
-- @treturn string Title to show. `nil` uses `target:Name()`.
-- @usage function PLUGIN:GetDisplayedName(target)
-- 	return "Unknown person"
-- end
--
-- No implementation in this repository.
function GetDisplayedName(target)
end

--- Called when a player sends a Combine request with `/Request`.
-- Fired by the `/Request` command in `schema/sh_commands.lua`. The player must hold a `request_device`, be
-- Combine, or be in the administrator faction, and must not be restricted. The hook runs after the
-- schema adds its "cRequest" Combine display line and before the `request` chat messages are sent.
-- @realm server
-- @player client Player who sent the request
-- @string message Request text
-- @usage function PLUGIN:PlayerCombineRequest(client, message)
-- 	ix.log.AddRaw(client:Name() .. " requested: " .. message)
-- end
--
-- The return value is ignored. Implemented by `cto` (`cto/sv_hooks.lua`), which places a request marker
-- and plays a sound for the Combine.
function PlayerCombineRequest(client, message)
end

--- Whether the schema should announce a Combine player's death as a lost biosignal.
-- Fired by `Schema:PlayerDeath` in `schema/sv_hooks.lua` for a Combine player, after it has destroyed
-- their scanner. The announcement is the "cLostBiosignal" and location display lines plus the Overwatch
-- radio sounds to every Combine player.
-- @realm server
-- @player client Combine player who died
-- @treturn bool `false` skips the schema's announcement. Any other value, including `nil`, lets it run.
-- @usage function PLUGIN:ShouldAnnounceBiosignalLoss(client)
-- 	return false -- this plugin announces deaths itself
-- end
--
-- Implemented by `cto` (`cto/sv_hooks.lua`). It always returns `false`, because cto announces the loss
-- itself from its own `PlayerDeath`.
function ShouldAnnounceBiosignalLoss(client)
end

--- Whether a Combine player is sent the death sound of a Combine unit.
-- Fired by `Schema:GetPlayerDeathSound` in `schema/sv_hooks.lua`. That function runs from Helix's
-- `GM:PlayerDeath` when a Combine player dies, and fires the hook once for each Combine player, the dying
-- one included.
-- @realm server
-- @player listener Combine player who would hear it
-- @player client Combine player who died
-- @treturn bool `false` skips `listener:EmitSound` for that listener. Any other value, including `nil`,
-- plays it. Helix still plays the death sound on the dying player whatever this returns.
-- @usage function PLUGIN:CanHearCombineDeath(listener, client)
-- 	if (listener:GetPos():Distance(client:GetPos()) > 4096) then
-- 		return false
-- 	end
-- end
--
-- Implemented by `cto` (`cto/sv_hooks.lua`). It returns `false` when the dead unit had no biosignal, and
-- when the listener has none.
function CanHearCombineDeath(listener, client)
end

--- The engine's `PlayerHurt`, fired again by the schema for a player piloting a scanner.
-- `Schema:EntityTakeDamage` in `schema/sv_hooks.lua` fires it by hand when an NPC scanner piloted by a
-- player takes damage. The engine never fires it in that case, because the player is spectating the NPC.
-- Before firing, the schema sets the player's health to the scanner's. `EntityTakeDamage` runs before the
-- damage is applied, so `health` is the scanner's health before this hit, not after it as in the engine
-- hook.
-- @realm server
-- @player client Player piloting the scanner
-- @entity attacker `dmgInfo:GetAttacker()`
-- @number health Player's health, just set to the scanner's health
-- @number damage `dmgInfo:GetDamage()`
-- @usage function PLUGIN:PlayerHurt(client, attacker, health, damage)
-- 	-- runs for ordinary hits and, through the schema, for hits on a piloted scanner
-- end
--
-- The return value is ignored. Implemented by `Schema:PlayerHurt` (Combine trauma display lines) and
-- Helix's `GM:PlayerHurt`.
function PlayerHurt(client, attacker, health, damage)
end

--- The engine's `PlayerDeath`, fired again by the schema when a player's scanner is killed.
-- `Schema:OnNPCKilled` in `schema/sv_hooks.lua` fires it by hand when a killed NPC was piloted by a player.
-- The arguments are reordered to the engine's `(victim, inflictor, attacker)`.
--
-- At this point the player is still alive: they are spectating the scanner. Afterwards the scanner's
-- remove callback in `Schema:CreateScanner` (`schema/sv_schema.lua`) calls `KillSilent`, which does not
-- fire `PlayerDeath` or `DoPlayerDeath`. So every `PlayerDeath` implementation runs once for the pilot,
-- and `DoPlayerDeath` implementations (`persistent_corpses`, `dropitems`, `ragdollstate`) do not run.
-- @realm server
-- @player client Player who was piloting the scanner
-- @entity inflictor Inflictor passed to `OnNPCKilled`
-- @entity attacker Attacker passed to `OnNPCKilled`
-- @usage function PLUGIN:PlayerDeath(client, inflictor, attacker)
-- 	if (client:Alive()) then
-- 		return -- a scanner pilot, not a real death
-- 	end
-- end
--
-- Implemented by `Schema`, `cto`, `ragdollstate`, `survivaladditions`, Helix's `GM:PlayerDeath`, the Helix
-- `permakill` and `act` plugins, and the `ixStripClip` handler in Helix's `base_weapons`. The return value
-- is ignored, but a non-nil return skips the rest of that list.
function PlayerDeath(client, inflictor, attacker)
end

-- Schema entities: ixhl2rp/entities

--- Whether a stunstick's secondary attack knocks on a door.
-- Fired by `SWEP:SecondaryAttack` in `ixhl2rp/entities/weapons/ix_stunstick.lua` when the hull trace in
-- front of the player hits a door.
-- @realm server
-- @player client Player holding the stunstick
-- @entity door Door that was hit
-- @treturn bool `false` stops the knock: no sound, view punch, animation or cooldown. `nil` lets it knock.
-- @usage function PLUGIN:PlayerCanKnockOnDoor(client, door)
-- 	if (door:GetNetVar("disabled")) then
-- 		return false
-- 	end
-- end
--
-- No implementation in this repository.
function PlayerCanKnockOnDoor(client, door)
end

-- immersion: immersion/cl_screen.lua

--- Whether a notice is shown. Every notice (`ix.util.Notify`, `ix.util.NotifyLocalized`, `Player:Notify` and
-- `Player:NotifyLocalized`, from the server or the client) passes through here before it is shown: as a private
-- chat line in the notice colour with a sound while `immersionHideHUD` hides the HUD, as Helix's toast otherwise.
-- Fired by `PLUGIN:ShowNotice` in `immersion/cl_screen.lua`, which `immersion` puts in place of Helix's client
-- `ix.util.Notify` and `ix.util.NotifyLocalized`.
-- @realm client
-- @string text The notice, already translated
-- @string[opt] phrase The language phrase it was sent as; nil for a plain notice
-- @bool bRefusal Whether it says something was refused (`PLUGIN:IsRefusalNotice`: a phrase in
-- `PLUGIN.refusalPhrases`, or text ending in "!"); a refusal gets the refusal sound
-- @treturn bool `false` drops the notice, so nothing is shown or played. `nil` shows it.
-- @usage function PLUGIN:ShouldShowNotice(text, phrase, bRefusal)
-- 	if (phrase == "salary") then
-- 		return false -- the money is felt in the pocket
-- 	end
-- end
--
-- Implemented by `vendorpanel` (`vendorpanel/cl_plugin.lua`): while a trade waits for its answer, a trade that
-- went through plays the coin sound and is dropped, and a refusal ends the wait.
function ShouldShowNotice(text, phrase, bRefusal)
end

-- interaction: interaction/cl_plugin.lua

--- Adds options to the ones held Use shows beside an entity, after its own entity menu.
-- Fired by `PLUGIN:BuildRows` in `interaction/cl_plugin.lua` each time the options are built or refreshed
-- (every quarter second while they are open), for every entity, `ix_item` world items included.
-- @realm client
-- @entity entity The entity the options are for
-- @player client The local player
-- @tab options Label -> function, as `GetEntityMenu` returns. Add entries to it. A function that returns
-- anything but `false` also sends `ix.menu.NetworkChoice(entity, label, result)`, as Helix's menu did;
-- return `false` when the function has done everything itself.
-- @treturn nil The return value is ignored, but a non-nil return skips the other implementations.
-- @usage function PLUGIN:PopulateInteractionOptions(entity, client, options)
-- 	if (entity:GetClass() == "ix_item") then
-- 		options["Kick"] = function() net.Start("MyKick") net.WriteEntity(entity) net.SendToServer() return false end
-- 	end
-- end
--
-- Implemented by `ixcraft` (`ixcraft/cl_panel.lua`): "Break down" and similar for a world item that a
-- recipe needing no station uses.
function PopulateInteractionOptions(entity, client, options)
end

-- protectionteams: protectionteams/sv_plugin.lua (server), protectionteams/cl_plugin.lua (client)
-- The server fires each team hook from the plugin's team methods. The client fires the same hook from
-- its own copy of the method when the matching `ixPT*` net message arrives (protectionteams/cl_hooks.lua).
-- Team indices are numbers from 1 to 99.

--- Called after a protection team is created. Also fired by `ReassignTeam`, for the new index.
-- @realm shared
-- @player client Team owner
-- @number index New team's index
-- @usage function PLUGIN:OnCreateTeam(client, index)
-- end
--
-- The return value is ignored. Implemented by `protectionteams` on the client
-- (`protectionteams/cl_hooks.lua`), which rebuilds the open team menu.
function OnCreateTeam(client, index)
end

--- Called after a team moves to a new index with `/PTReassign`.
-- The plugin first deletes the old team, which fires `OnDeleteTeam(index)`. It then recreates the team
-- under the new index, which fires `OnCreateTeam(owner, newIndex)`, and only then fires this hook.
-- @realm shared
-- @number index Old index
-- @number newIndex New index
-- @usage function PLUGIN:OnReassignTeam(index, newIndex)
-- end
--
-- The return value is ignored. Implemented by `protectionteams` on the client (menu rebuild).
function OnReassignTeam(index, newIndex)
end

--- Called after a team's owner changes.
-- Fired by `SetTeamOwner(index, client)`. The hook's arguments are in the opposite order to that method's.
-- `LeaveTeam` also fires this hook, with no owner, when the owner leaves.
-- @realm shared
-- @player client New owner. When the team has no owner this is `nil` on the server and an invalid entity on
-- the client (read with `net.ReadEntity`).
-- @number index Team index
-- @usage function PLUGIN:OnSetTeamOwner(client, index)
-- 	if (!IsValid(client)) then
-- 		return -- the owner left
-- 	end
-- end
--
-- The return value is ignored. Implemented by `protectionteams` on the client (menu rebuild).
function OnSetTeamOwner(client, index)
end

--- Called after a team is deleted.
-- Fired in two cases: when the server's `Tick` cleanup (every 30 seconds, `protectionteams/sv_hooks.lua`)
-- deletes a team with no members, and by `ReassignTeam` for the old index. No command deletes a team.
-- @realm shared
-- @number index Deleted team's index
-- @usage function PLUGIN:OnDeleteTeam(index)
-- end
--
-- The return value is ignored. Implemented by `protectionteams` on the client (menu rebuild).
function OnDeleteTeam(index)
end

--- Called after a player joins a team.
-- @realm shared
-- @player client Player who joined
-- @number index Team index
-- @usage function PLUGIN:OnJoinTeam(client, index)
-- end
--
-- The return value is ignored. Implemented by `protectionteams` on the client (menu rebuild).
function OnJoinTeam(client, index)
end

--- Called after a player leaves a team. This covers `/PTLeave`, being kicked, disconnecting, and loading a
-- non-Combine character.
-- When the player was the owner, `OnSetTeamOwner(nil, index)` fires first.
-- @realm shared
-- @player client Player who left
-- @number index Team they left
-- @usage function PLUGIN:OnLeaveTeam(client, index)
-- end
--
-- The return value is ignored. Implemented by `protectionteams` on the client (menu rebuild).
function OnLeaveTeam(client, index)
end

--- Fills the list of teams shown in the Protection Teams tab.
-- Fired from `PANEL:Init` of `ixTeamMenu` in `protectionteams/derma/cl_protectionteams.lua`. That happens
-- each time the tab opens, and again whenever a team hook above rebuilds it.
-- @realm client
-- @tab teams Table to fill. Each key becomes a team button, and each value is `function(container)` that
-- builds that team's page.
-- @usage function PLUGIN:PopulateTeamMenu(teams)
-- 	teams["Dispatch"] = function(container)
-- 		container:Add("DLabel"):SetText("Dispatch")
-- 	end
-- end
--
-- The return value is ignored. Implemented by `protectionteams` itself with
-- `hook.Add("PopulateTeamMenu", "ixTeamMenu")` in the same file, which adds one entry per team. A hook.Add
-- handler runs last, so a plugin or schema method that returns a non-nil value stops the real teams from
-- being listed.
function PopulateTeamMenu(teams)
end

-- ragdollstate: ragdollstate.lua

--- Called when a timed knockdown runs out and the player stands up.
-- `ragdollstate` wraps the countdown timer that Helix's `Player:SetRagdolled(true, time)` creates. The hook
-- fires only when that countdown removes the ragdoll and the player is alive. It does not fire for
-- `SetRagdolled(false)`, for a ragdoll removed any other way, or for a death.
-- @realm server
-- @player client Player getting up
-- @entity ragdoll Ragdoll being removed (marked for deletion). The player gets their position and weapons
-- back when its removal completes, just after this hook.
-- @usage function PLUGIN:OnCharacterWakeup(client, ragdoll)
-- 	client:ChatNotify("You come to.")
-- end
--
-- The return value is ignored. No implementation in this repository.
function OnCharacterWakeup(client, ragdoll)
end

--- Called when a player gets up from a ragdoll by any means and is handed back the weapon they held.
-- Fired from the ragdoll's `"fixer"` remove callback, which `ragdollstate` replaces, after Helix's own
-- callback has restored the player. It fires only when the ragdoll was not removed for a death or
-- respawn (`ixIgnoreDelete`) and the player has that weapon again.
-- It never fires for a body that `persistent_corpses` turns into a corpse, because that plugin removes the
-- `"fixer"` callback.
-- @realm server
-- @player client Player who got up
-- @string weaponClass Class name of the weapon they were holding (not an entity)
-- @usage function PLUGIN:OnCharacterWakeupWeapon(client, weaponClass)
-- 	client:SelectWeapon(weaponClass)
-- end
--
-- The return value is ignored. No implementation in this repository.
function OnCharacterWakeupWeapon(client, weaponClass)
end

-- persistent_corpses: persistent_corpses.lua

--- Whether a dying player leaves a persistent corpse.
-- Fired by `PLUGIN:DoPlayerDeath` in `persistent_corpses.lua` when the `persistentCorpses` config is on. It
-- runs before the `corpseMax` check. The hook gets no arguments, so an implementation cannot tell whose
-- death it is.
-- @realm server
-- @treturn bool `false` means no corpse, and Helix removes the ragdoll as usual. Any other value, including
-- `nil`, makes one.
-- @usage function PLUGIN:ShouldSpawnPlayerCorpse()
-- 	if (self.bEventRunning) then
-- 		return false
-- 	end
-- end
--
-- No implementation in this repository.
function ShouldSpawnPlayerCorpse()
end

--- Called after a dying player's corpse has been set up.
-- Fired at the end of `PLUGIN:DoPlayerDeath` in `persistent_corpses.lua`. By then the corpse is marked
-- `isDeadPlayer`, detached from the player (`client.ixRagdoll` and `entity.ixPlayer` are cleared) and
-- scheduled to decay.
-- @realm server
-- @player client Player who died
-- @entity entity Corpse (`prop_ragdoll`)
-- @usage function PLUGIN:OnPlayerCorpseCreated(client, entity)
-- 	entity:SetNetVar("deathTime", os.time())
-- end
--
-- The return value is ignored. Implemented by `persistent_corpses` itself: when `dropItemsOnDeath` is on, it
-- moves items marked `bDropOnDeath` into a corpse inventory. A non-nil return from another plugin can skip
-- that.
function OnPlayerCorpseCreated(client, entity)
end

-- shootlock: shootlock.lua

--- Whether a shot may bust a door's lock or blast the door open.
-- Fired by `PLUGIN:EntityTakeDamage` in `shootlock.lua` for bullet damage to a `prop_door_rotating` that
-- has a `handle` bone. The attacker must be a player looking at the door from within the shoot distance.
-- The hook runs before the plugin decides between a shotgun breach and a handle shot.
-- @realm server
-- @player client Player who fired
-- @entity door Door that was hit
-- @treturn bool `false` blocks both the breach and the lock bust. `nil` allows them.
-- @usage function PLUGIN:CanPlayerBustLock(client, door)
-- 	if (IsValid(door.ixLock)) then
-- 		return false -- Combine locks resist bullets
-- 	end
-- end
--
-- No implementation in this repository.
function CanPlayerBustLock(client, door)
end

-- legs: legs.lua

--- Whether to hide the local player's first-person legs.
-- Fired by `ShouldDrawLegs` in `legs.lua`, which is checked every time the legs are rendered.
-- @realm client
-- @treturn bool `true` hides the legs. `false` or `nil` leaves the plugin's other checks to decide; it does
-- not force them on.
-- @usage function PLUGIN:ShouldDisableLegs()
-- 	return LocalPlayer():GetNetVar("actEnterAngle") != nil
-- end
--
-- No implementation in this repository.
function ShouldDisableLegs()
end

-- spawnmenu_itemtab: spawnmenu_itemtab.lua

--- The icon for an item category in the spawn menu's Items tab.
-- Fired by `PLUGIN:GetExpectedIcon` in `spawnmenu_itemtab.lua` once per category while the tab is built.
-- @realm client
-- @string category Item category name (`ITEM.category`)
-- @treturn string Path of a 16x16 icon material. `nil` uses the plugin's built-in table, then
-- `icon16/folder.png`.
-- @usage function PLUGIN:GetIconsForSpawnMenuItems(category)
-- 	if (category == "Books") then
-- 		return "icon16/book.png"
-- 	end
-- end
--
-- No implementation in this repository.
function GetIconsForSpawnMenuItems(category)
end

-- weather: weather/sv_plugin.lua (server), weather/cl_plugin.lua (client)

--- Called when the weather type changes.
-- The server fires it from `ix.weather.Set` as the transition begins, so `ix.weather.GetValue` still returns
-- values close to the old type's. Each client fires it when the `ixWeatherState` message brings a different
-- type, including the first message after joining (where `oldType` is the client's default, `"clear"`).
-- Setting the type that is already current only changes when it ends and does not fire it.
-- @realm shared
-- @string newType ID in `ix.weather.types` of the type now being moved to (`ix.weather.Get()`)
-- @string oldType ID of the type before it
-- @usage function PLUGIN:WeatherChanged(newType, oldType)
-- 	if (SERVER and ix.weather.types[newType].precipitation > 0) then
-- 		print("rain starts after " .. oldType)
-- 	end
-- end
--
-- The return value is ignored. No implementation in this repository.
function WeatherChanged(newType, oldType)
end
