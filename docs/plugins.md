# Plugins

This file has one row per plugin in `ixhl2rp/plugins`. The ID is the folder name, or the file name without `.lua`, and it is the key that `ix.plugin.Get` and `ix.plugin.list` take. Origin `project` means the plugin was written for GlutWorks. `third-party, modified` means the project has changed it since importing it, based on `git log` for the path. The last column lists only links the code actually makes; the project's own hooks are in `docs/hooks.lua`.

Rules that apply across plugins:

- **Never edit `helix/`. Change framework behaviour from a plugin.** Wrapping a Helix function or method is fine; `containerguard`, `enginecompat`, `ragdollstate` and `door_saver` all do this (see `UPSTREAM.md`).
- **A plugin with the same ID as one in `helix/plugins` extends that plugin rather than replacing it.** `ix.plugin.Load` reuses the existing table and runs the second file into it. `pac` and `thirdperson` work this way. Disabling one of those IDs disables both the Helix file and ours.
- **Returning a value from a hook is a decision.** Helix's `hook.Call` runs the plugin methods first, in no fixed order, then `Schema`, then `hook.Add` handlers, and stops at the first non-nil return. Return nothing unless you mean to override the schema and every other plugin (`helix/gamemode/core/libs/sh_plugin.lua`).
- **Use `ix.stack` (from `stacking`) for any item that sets `ITEM.stackLimit`.** A stack is one instance holding `data.quantity`.
  - `HasItem` and `GetItemCount` count instances, not quantity.
  - `inventory:Remove` and `item:Remove` delete the whole stack.
  - `ix.item.Spawn` makes a single quantity-1 instance.
  - Use `ix.stack.Count`, `Take`, `Give`, `GiveOrDrop` and `Spawn` instead.
  - Plain `inventory:Add(uniqueID, n)` is safe, because `stacking` patches it to merge.
- **Make an item stackable by setting `ITEM.stackLimit`, and also `stackStep` and `stackUnit` if needed. Do not set `ITEM.base = "base_stackable"`.** `ix.stack.ApplyBaseToAll` copies `base_stackable` onto every such definition at `InitializedPlugins`.
- **Crafting is split between two plugins:**
  - `ixcraft` has the recipe engine and crafting menu, the station entities, and the recipe and station definitions (`ixcraft/recipes`, `ixcraft/stations`).
  - `glutcraft` has the materials and their item bases, the station items, smelting, and station placement and saving.
  - Any plugin's `recipes/` or `stations/` folder is loaded by `ixcraft`.
  - A placeable station needs a `base_station` item whose `entityName` is the station ID.
- **Some Combine checks must go through schema helpers.**
  - Use `IsCombine()`, `IsDispatch()`, `Schema:IsCombineRank(name, rank)` and `Schema:HasCommandRank(client)` (`schema/meta/sh_player.lua`, `schema/sh_schema.lua`).
  - Rank comes from tokens in the character name, so code that renames characters must not let players forge them.
  - Combine HUD lines go through `Schema:AddCombineDisplayMessage`.
- **An entity that a plugin saves itself sets `ENT.bNoPersist = true`.** Otherwise Helix's persistence plugin saves a second copy.
- **Business is deny-by-default (`Schema:CanPlayerUseBusiness` in `schema/sh_hooks.lua`).** A buyable item needs a positive `price` plus a permit, a `factions`/`classes` list or a flag. Use `noBusiness` for items that must never be sold.

## Crafting and resources

| Plugin | What it does | Origin | Depends on / used by |
|---|---|---|---|
| `ixcraft` | Owns the recipe engine (`PLUGIN.craft`, `/CraftRecipe`, a recipe's `OnCanSee`/`OnCanCraft`/`OnCraft`), the Crafting tab, the `ix_station` entity base and its `ix_station_<id>` subclasses. It also holds the 7 recipes and the 6 station definitions; a station definition with `STATION.smelting` is a smelter. | third-party (wowm0d, CC BY-NC-SA), modified (extended by Ierion in 2022–23, recipe engine rewritten on `ix.stack` in 2026) | Needs `stacking` (calls `ix.stack` unguarded). Uses `ix.smelting`/`ix.station` from `glutcraft` when present. Recipes use `glutcraft` and `glutworksweapons` items. Station tooltips refresh through `livetooltips`. Workshop: station and weapon models. Used by `glutcraft` (`ix.plugin.list.ixcraft.craft.stations`). Fires and implements `BuildCraftingMenu`. |
| `glutcraft` | Owns the crafting materials: resources, components, junk, tools and station items, with bases `base_resources`, `base_components`, `base_misc_junk`, `base_smeltable_junk`, `base_singular_components`, `base_tools` and `base_station`. Also owns `ix.smelting` (fuel and input tables, queue, collect) and `ix.station` (place a station from its item, pick it up, save and load). | project (Ierion0, 2023; `PLUGIN.author` PhiYerion; reworked 2026) | Needs `ixcraft` (station definitions and entities) and `stacking` (unguarded). Workshop: Fallout 4 junk props, WN Content Pack, Fallout NV crafting stations. Used by `ixcraft`, `mining` (ores are smelting inputs and fuel), `scavenging`, `itemspawner` and `npcdropitems` (its items). |
| `stacking` | Owns `ix.stack` and `base_stackable`: stack quantities, merging, splitting, pickup that fills partial stacks, an `INVENTORY:Add` that merges stackables, and vendor trades that move `tradeAmount` (default 1 unit) per trade. | project | Implements the Helix vendor plugin's `CanPlayerTradeWithVendor` and `CharacterVendorTraded`. Used by `ixcraft`, `glutcraft`, `mining` and `scavenging` (unguarded); `npcdropitems`, `survivaladditions` and `Schema:GiveLoadout` check for `ix.stack` first. |
| `mining` | Admin-placed ore nodes (`ix_orenode_{coal,copper,gold,iron,tin}` on base `ix_orenode`) break stage by stage under any damage. Each stage drops kilograms of ore through `ix.stack.Spawn`. Nodes regrow after `oreNodeRespawnTime`, are saved by the plugin, and use item base `base_ore`. | project (Bryce, 2023; reworked 2026) | Needs `stacking`. Workshop: Ore Models (falls back to a box without them). Ores are inputs in `glutcraft`'s `ix.smelting`. |
| `scavenging` | Admin-placed props (`ix_barrel`, `ix_bench`, `ix_chair`, `ix_pallet` on base `ix_scavengeable`) break after 100 damage into metal or wood scrap. They respawn after `scavengeRespawnTime` and are saved by the plugin. | project (Ierion0, 2023; reworked 2026) | Needs `stacking` and `glutcraft` scrap items. |
| `itemspawner` | Staff place named spawn points (`/ItemSpawnerAdd` and others, with a manager UI). Each point periodically spawns a random item from hard-coded common and rare pools, which are all `glutcraft` junk today. Noclip staff see an ESP of the points. | third-party (Gary Tate, wowm0d; MIT), modified (pools replaced) | `glutcraft` items. Helix `observer` (privilege, `observerESP`). Reads the `observerItemESP` option that `itemesp` defines. |
| `npcdropitems` | Headcrabs, antlions and zombies drop meat, a poison gland or fabric when killed, rolled from the `PLUGIN.drops` table. This applies to any killed NPC of those classes, not only spawner NPCs. | project (Bryce, 2023) | Items from `survivaladditions` and `glutcraft`. Uses `ix.stack.Spawn` for stackables when `stacking` is loaded. |

## Items and weapons

| Plugin | What it does | Origin | Depends on / used by |
|---|---|---|---|
| `glutworksweapons` | Defines the 14 weapon items. They take Helix `base_weapons` from the folder name. It also adds the magazine-ammo tooltip row and turns off TFA's context menu, inspection and crosshair. | project (Bryce, 2023) | Workshop: TFA Base, TFA INS2 Shared Parts, HL2 MMod pack, Makarov, Spectre, Rust Firearms, Junk Weapon Pack; PAC3 for the lamp and pistol `pacData`. Schema classes `CLASS_EOW`/`CLASS_EMP` gate purchase. Used by `ixcraft` recipes and `shootlock` (`ITEM.isShotgun`). |
| `books` | Adds about 50 readable book and newspaper items (`base_books`, a Read action showing `ITEM.text`). None has a price. | third-party (author unknown); only items removed since import | - |
| `writing` | Adds `paper`. A player writes it once, up to 512 characters, and anyone can read it afterwards. Edits are checked for reach and `CanPlayerInteractItem`. Only the `CLASS_EOW` class can buy it, because `classes = {CLASS_EOW}`. | third-party (`impulse), modified | Schema `CLASS_EOW`. |
| `randomitems` | Joke content: `ix_childdispenser` (a copy of the ration dispenser that takes a CID and gives a `baby`) and the `baby` item, which opens into meat and a skull. | project (Oebelysk) | Schema `cid` item and `rationInterval` config; `survivaladditions` `meat_chunk`. |

## Combine

| Plugin | What it does | Origin | Depends on / used by |
|---|---|---|---|
| `cto` | Owns the Combine biosignal overlay: unit markers through walls, biosignal-loss alerts that name the unit (replacing the schema's), `/Request` markers, camera movement alerts with the `ix_ctocameraterminal`, CID tags and sociostatus. Its commands are `/SetSocioStatus`, `/SetBiosignalStatus`, `/CharSetBiosignalStatus`, `/CharSetHasTags`, `/CameraEnable` and `/CameraDisable`. | third-party (Trudeau & Aspect, MIT), modified | Schema Combine helpers, `Schema.CombineObjectives`, Helix `area` (`GetArea`). Implements `ShouldAnnounceBiosignalLoss`, `CanHearCombineDeath` and `PlayerCombineRequest`, which the schema fires. |
| `datafile` | `/Datafile <name>` opens a character's Combine record: medical, union and civil entries, points, civil status, BOL and restriction. It is stored in SQL table `ix_datafile`. Access is tiered: recruits, other Civil Protection, then command, OTA and admins. Superadmins get `/ManageDatafile`, `/RestrictDatafile` and `/ClearDatafile`. It is separate from the schema's `/ViewData` note. | third-party ("James"), modified (permissions and receivers rewritten) | Schema `IsCombineRank`, `HasCommandRank`, and `FACTION.bAllowDatafile` (citizen and OTA factions). Its `README.md` describes an older data layout. |
| `protectionteams` | Adds a Protection Teams tab and `/PTCreate`, `/PTJoin`, `/PTLeave`, `/PTLead`, `/PTKick` and `/PTReassign` for Combine squads (indices 1–99). Dispatch can manage any team. Empty teams are deleted. | third-party (wowm0d, CC BY-NC-SA), modified | Schema `IsCombine`, `IsDispatch`; Helix tab menu. Fires `OnCreateTeam`, `OnReassignTeam`, `OnSetTeamOwner`, `OnDeleteTeam`, `OnJoinTeam`, `OnLeaveTeam` and `PopulateTeamMenu`, all implemented only by itself. |
| `combinevoices` | Registers about 80 extra HL2-beta Civil Protection voice lines for MPF and OTA, and Airwatch lines for Dispatch. | third-party (Ice Bear / DevAppeared, MIT), modified (sound paths) | `Schema.voices`. Workshop: Beta Metrocop Sounds. |
| `vocoder` | OTA (Combine that are not MPF) get vocoder clicks instead of radio beeps when typing and after voice lines. It does this by replacing the schema's `PlayerChatTextChanged` and `PlayerFinishChat` netstream handlers, and it carries a copy of `Schema:PlayerMessageSend` that wins for Combine speakers. | third-party (sanny, MIT), unmodified | `Schema.voices`. Workshop: Helix HL2 RP Vocoder Sounds. Changes to Combine chat in `schema/sv_hooks.lua` must be mirrored here. |
| `waypoints` | `/WaypointAdd`, `/WaypointUpdate`, `/WaypointRemove` and related commands place timed markers. Only factions with `canAddWaypoints` and similar flags can place them, and only factions with `canSeeWaypoints` can see them through walls. Those flags are set on MPF and OTA. | third-party (Gr4ss, CC BY-SA), unmodified | The faction flags in `schema/factions/sh_metropolice.lua` and `sh_ota.lua`. Defines `Schema:AddWaypoint`, which nothing calls. |
| `applicationsystem` | A citizen with a CID uses an `ix_applicationterminal` to apply to Civil Protection. Admins use `/ViewApplications` to read and accept or deny. The applicant gets a letter on next load, and an accepted applicant gets `acceptance_paper`. Applications are stored in SQL table `ix_applications`. | third-party (ZeMysticalTaco), modified | Schema `cid` item. |

## Characters, death and survival

| Plugin | What it does | Origin | Depends on / used by |
|---|---|---|---|
| `survivaladditions` | Covers hunger and thirst: character vars, HUD bars, drain and starvation, slower stamina regeneration when low, `/CharSetHunger` and `/CharSetThirst`. It also adds the food, drink and ingredient items (`base_eatable`, `base_drinkable`, `base_ingredient`) and filling cans with water. The system is off until `hungerthirstEnabled` is set to true. | third-party (firehellrain, per `PLUGIN.author`), modified | Helix `stamina`. Uses `ix.stack` when `stacking` is loaded. Workshop: Fallout 4 food props. The schema ration gives its `supplements` and `water`. `npcdropitems` and `randomitems` use its items. |
| `customdamage` | Its in-game name is "Knockdown". A hit that leaves a character below `unconsciousHealth` knocks them out for `unconsciousTime`, and a bad fall ragdolls them. A downed body takes half damage, and knockout time resumes after reconnect. It also quietens crouched footsteps and plays a bone-break sound on headshots. | project (Oebelysk, 2022; rewritten 2026) | Helix `SetRagdolled` (wrapped by `ragdollstate`), `ixFallGrace`. `disablecharswitch` and `persistent_corpses` act on the ragdolls it makes. |
| `ragdollstate` | Wraps `Player:SetRagdolled` and `CreateServerRagdoll`. It fires `OnCharacterWakeup` and `OnCharacterWakeupWeapon`, sets `isDeadPlayer` on a dead owner's ragdoll, and clears Helix's stale `ixRagdoll`. It also stops Helix's get-up timer on death, so a kept body stays down. | project | Relies on Helix internals: timer `ixUnRagdoll<SteamID>`, remove callback `"fixer"`. `isDeadPlayer` is read by `entity_info`. |
| `persistent_corpses` | A dead player's body stays as a searchable ragdoll (`corpseMax`, `corpseDecayTime`). A knocked-out ragdoll becomes the corpse. With `dropItemsOnDeath`, items marked `bDropOnDeath` move into the corpse. | third-party (`impulse, MIT), modified | Removes the ragdoll's `"fixer"` callback, which also removes `ragdollstate`'s wake-up hook for that body. Fires `ShouldSpawnPlayerCorpse` and `OnPlayerCorpseCreated`. |
| `dropitems` | On death, equipped weapon items drop into the world, including those Helix stored on a downed player's ragdoll (`dropWeaponOnDeath`). | third-party (pedro.santos53), modified | Helix `SetRagdolled` (`ragdoll.ixWeapons`). |
| `disablecharswitch` | Refuses a character switch while the player is ragdolled or dead. | project (Oebelysk) | Helix `client.ixRagdoll`, which `ragdollstate` keeps accurate. |
| `simple_nicknames` | `/SetNickname <text>` renames the character to `First 'nick' Rest`, and `none` restores the name. It is refused for MPF and OTA, whose names hold rank tokens. | third-party (alexgrist, Unlicense), modified | Schema `IsCombine`. |
| `mynotes` | `/MyNotes` opens a per-character notepad of up to 1024 characters, stored in column `personal_notes` of `ix_characters`. | third-party (`impulse, MIT), modified | - |
| `fancyme` | Adds ranged `/me` and `/it` variants: `/MeY` and `/ItY` (yell range), `/MeW` and `/ItW` (whisper range), and `/MeL` and `/ItL` (only the player looked at). | third-party (liquid), modified | - |

## Models, animation and PAC

| Plugin | What it does | Origin | Depends on / used by |
|---|---|---|---|
| `pac` | Extends Helix's `pac` plugin, which shares the ID. Items may define `pacDataMale`, `pacDataFemale` and `pacDataMPF`, and the wearer gets the matching variant. The held weapon is not also shown holstered. `PLUGIN:GetItemPartID` decides which part an item uses. | project (extends Helix's plugin by Black Tea; also credits pedro.santos53) | Workshop PAC3 (inert without it). Used by `pacfixes` (`ix.plugin.Get("pac"):GetItemPartID`) and by `glutworksweapons` lamp and pistol `pacData`. |
| `pacfixes` | Re-applies equipped items' PAC parts after a character gets up, and clears them on death. | project (Oebelysk) | `pac`'s `GetItemPartID`; PAC3. |
| `enhancedanims` | Adds animation classes for the extended citizen models and maps `police_nemez` to `metrocop`. Keeps distinct animations for every weapon hold type, mirrors citizen `/act`s onto the new classes, and nil-guards Helix act's `ixActEnter` receiver. | project (moved out of earlier `helix/` edits) | Helix `act` (`ix.plugin.Get("act")`). Workshop: Enhanced and Extended Citizens, Nemez Metropolice. |
| `addfactionhands` | Registers Combine viewmodel hands for `models/police_nemez.mdl`. | project (Oebelysk) | Workshop: Nemez Metropolice. |
| `legs` | Draws the local player's legs in first person (options `legsEnabled`, `legsInVehicle`). | third-party (Valkyrie & blackops7799, Unlicense), unmodified | Fires `ShouldDisableLegs`. |
| `thirdperson` | Extends Helix's `thirdperson` plugin, which shares the ID. Third person is on by default, and the `thirdpersonEnabled` option is networked so the server can read it. | project | Helix `thirdperson`. Used by `kickdoor`, which reads the option on the server. |
| `rappelling` | A player holding the `rappel_gear` SWEP rappels down from a ledge with a rope and a controlled descent. No item gives the SWEP; it is admin-spawned. | third-party (wowm0d, CC BY-NC-SA), unmodified | - |

## World, doors and NPCs

| Plugin | What it does | Origin | Depends on / used by |
|---|---|---|---|
| `door_saver` | A door bought by a character stays theirs across restarts and map cleanups, with the access they granted. While the owner is offline it is locked and cannot be bought. Deleting the character frees it. | third-party (Taxin2012, Apache-2.0), modified (access stored by character ID) | Helix `doors` (`ix.plugin.Get("doors")`; wraps `Entity:RemoveDoorAccessData`). |
| `kickdoor` | `/KickDoor` lets an MPF or OTA unit standing still near a `prop_door_rotating` spend 25 stamina to kick it, with a 50% chance of blasting it off its hinges. It is refused while dead, downed or tied. It ignores Combine locks and ownership. | project (Oebelysk; whether it was adapted from an outside plugin is unknown) | Helix `stamina` and `thirdperson` (`ix_togglethirdperson`); `thirdperson`'s networked option. |
| `shootlock` | Shooting a door's handle unlocks it and swings it open. Any shotgun hit (an item with `isShotgun`, or `weapon_shotgun`) blasts the door off its hinges. It ignores Combine locks and ownership. | third-party (Chessnut, ported by FatherSquirrel), modified | `glutworksweapons` `ITEM.isShotgun`. Fires `CanPlayerBustLock`. |
| `stealthability` | Holding walk while using a door opens it slowly (`StealthySpeed`) and silently, along with its double-door partner. | third-party (Shooter#5269), modified | - |
| `npcspawner` | `/NPCSpawnAdd <group>` and related commands place spawn points for birds, zombies, headcrabs and antlions. They spawn away from players every `npc_spawnrate` seconds, up to 40 NPCs. | third-party (Black Tea, Neon, B4tr1p), modified | - |

## Environment

| Plugin | What it does | Origin | Depends on / used by |
|---|---|---|---|
| `weather` | Owns `ix.weather`: a server-wide weather type (`clear`, `cloudy`, `fog`, `drizzle`, `rain`, `storm` in `weather/sh_types.lua`, each followed only by the types in its `next` weights), the blended values `GetValue`, the outdoor temperature from season, hour and weather (`GetTemperature`, `GetTemperatureAt`), and what reaches a player (`GetExposure`). Precipitation is snow at or below 1 °C. Clients draw rain or snow only where the sky is open, play rain, wind and server-timed thunder, and add weather fog and overcast dimming; there is no HUD. `/WeatherSet <type> [minutes]` (admin). The state survives restarts. | project | Helix `ix.date` (month and hour). Fires `WeatherChanged`. Its fog hooks return `true` only while weather fog is drawn. |

## Staff tools

| Plugin | What it does | Origin | Depends on / used by |
|---|---|---|---|
| `admincontext` | Context-menu options on players for holders of "Helix - Admin Context Options": show name, SteamID, health and armor; set health or armor; edit the description. | third-party (Gary Tate, MIT), modified | CAMI (bundled with Helix). |
| `bodygroupmanager` | `/CharEditBodygroup` and a context-menu option open a bodygroup editor that saves to the character's `groups` data. | third-party (Gary Tate, MIT), modified | - |
| `customitem` | `/CreateCustomItem <name> <model> <description>` (superadmin) gives the caller an item with that name, model and description. | third-party (Gary Tate, MIT), modified | - |
| `spawnmenu_itemtab` | Adds an Items tab to the spawn menu that spawns any item in front of the player, for holders of "Spawn Menu: Items - Spawning" (superadmin). | third-party (Rune Knight, CC BY-NC-SA), modified | Fires `GetIconsForSpawnMenuItems`. |
| `itemesp` | In observer noclip, shows the name of every world item (option `observerItemESP`). | third-party (Huargenn, per `PLUGIN.author`), modified | Helix `observer`. Its option is read by `itemspawner`. |
| `permaremove` | `/MapEntRemove` (superadmin) permanently deletes the map entity looked at; it is removed again on every load and map cleanup. | third-party (alexgrist, Unlicense), modified | - |

## UI and compatibility fixes

| Plugin | What it does | Origin | Depends on / used by |
|---|---|---|---|
| `entity_info` | For containers, money, vendors, shipments, players and their ragdolls, draws Helix's tooltip rows as fading text on the entity instead of the box. Corpses read "Seems deceased". | third-party (wowm0d, MIT), modified (rewritten 2026) | Helix `ix.gui.entityInfo`; the `isDeadPlayer` net var from `ragdollstate` and `persistent_corpses`. |
| `livetooltips` | Rebuilds the tooltip of the entity being looked at when its state changes, so station timers and world stack quantities stay current. An entity opts in with `ENT:GetEntityInfoState()`; `ix_item` is always covered. | project | Helix `ix.gui.entityInfo`. Used by `ixcraft`'s `ix_station`. |
| `uifonts` | Makes Times New Roman the default Helix title font (`font` config). | project | - |
| `enginecompat` | Replaces `ix.util.DrawPrecachedArc` so that current Garry's Mod builds do not error every frame on Helix's hold-to-pick-up arc. | project | Overrides a function in `helix/gamemode/core/sh_util.lua`. |
| `containerguard` | Stops a removed `ix_container` without an inventory (ID 0, the world inventory) from deleting every world item from the database. | project | Wraps `ix_container`'s `OnRemove` from Helix `containers`. |
