# Unused features of the original

Things the original's code can do that no script or game code in the pinned version ever uses. The port stays
1:1, so none of this is switched on; the list is for deciding, once the game is finished, whether any of it is worth
adding. ("Wela" in the original = a weapon or ability of a unit.)

How the list is kept:
- **Whole classes**: `python tools/find_unused_classes.py` lists every class exposed to scripts
  (`ScriptManager.ExposeClass`) whose name appears in no script (`.dws/.ets/.sps`) and in no other code (case
  ignored, as Delphi and DWScript do). Rerun it after changes to the pinned source; 43 classes on 2026-09-18 (26 before it learnt to skip fluent setters, strings and comments).
- **Unused options of used classes** (a method no script calls): added by hand when porting turns one up.

## Gameplay ideas

| Feature | Where | What it would do | Ported? |
| --- | --- | --- | --- |
| Nexus early vulnerability | `TNexusEarlyVulnerabilityComponent`, `BaseConflict.EntityComponents.Shared.pas:88` | Its group's `eiWelaDamage` starts at the set value and falls linearly to 1 by the game tick in `eiCooldown`, rounded up to whole steps (its comment: "6x, 5x, 4x, 3x ..."). The name suggests the Nexus taking extra damage early in the match. | No |
| Axis dynamic zone | `TDynamicZoneAxisEmitterComponent`, same unit `:606` | A card-placement zone bounded by a straight line instead of a circle, e.g. "your whole half of the map". Quirk: `SetPosition` normalizes the point, so it only sits at distance 1 from the map centre unless fixed. | Yes |
| Excluding zones | `TDynamicZoneEmitterComponent.Exclude`, same unit `:592` | A "no-play" zone: a spot inside it is out of zone even if another emitter allows it (e.g. no drops around an objective). | Yes |
| Life leech | `TBuffLifeLeechComponent`, `GameServer/BaseConflict.EntityComponents.Server.pas:128` | The unit heals for a share of all damage it deals (0.5 = half). | No |
| Damage cap by health | `TBuffCapDamageByHealthComponent`, same unit `:88` | No single hit can take more than a set percentage of the unit's max health (anti-burst, good for bosses). | No |
| Damage multiplier buff | `TBuffDamageMultiplierComponent`, same unit `:109` | Multiplies a weapon's damage by a factor (buff > 1, debuff < 1), optionally only for the next N attacks, then removes itself. | No |
| Unit limiter | `TWelaReadyUnitLimiterComponent`, `GameServer/BaseConflict.EntityComponents.Server.Welas.pas:183` | A spawner stops spawning while its maximum number of units is alive, and resumes as they die. | No |
| Permanent buff warhead | `TWarheadSpottyPermaBuffComponent`, `GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:201` | Each hit permanently raises a value of the target (the comment: "e.g. increasing money-amount like the commander has"): stacking buffs. | No |
| Movement speed multiplier | `TModifierMultiplyMovementSpeedComponent`, `BaseConflict.EntityComponents.Shared.Wela.pas:92` | Speeds a unit up or slows it down by a factor (haste / slow effects). | No |
| Meteor arrival | `TPositionerMeteorComponent`, `BaseConflict.EntityComponents.Client.Visuals.pas:1426` | Visual: the unit falls from the sky onto its spot when created, over a set flight time. | No |
| Link commander spells | `TBrainLinkWelaCommanderComponent`, `GameServer/BaseConflict.EntityComponents.Server.Brains.pas:881` | A spell where the player picks two targets and a link (beam/tether) is made between them. | No |
| Links that react to death | `TAutoBrainKillLinkComponent` (`...Server.Brains.pas:547`), `TLinkAutoBrainOnDeathComponent` (`:818`) | A link breaks when either end dies; or a link triggers an effect on its source when its target dies. | No |
| Link that buffs spawns | `TLinkEffectFireAtProducedUnitsComponent`, `...Server.Welas.pas:720` | While linked to a spawner, every unit it spawns gets an effect. Quirk: the hook keeps the link component's group, so only the spawner's groupless `eiWelaUnitProduced` reaches it. | Yes |
| Trigger before damage | `TAutoBrainOnWillDealDamageComponent`, `...Server.Brains.pas:691` | An ability that fires just before a unit deals damage (vs. the used "after damage" variant). | No |
| Chance on-hit effects | `TAutoBrainWelaOnHitEffectComponent`, `...Server.Brains.pas:786` | On every attack, another effect fires, optionally only by a chance (e.g. 20% to stun). | No |
| Abilities on the own commander | `TBrainWelaTargetCommanderComponent`, `...Server.Brains.pas:411` | A unit ability that fires at its own player's commander entity; what that does depends on the effect put with it. | No |
| Only own units | `TWelaTargetConstraintOwningComponent`, `BaseConflict.EntityComponents.Shared.Wela.pas:447` | An ability that may only target units of the same player (not just the same team). | No |
| Never usable | `TWelaTargetConstraintNeverComponent`, same unit `:273` | Disables an ability entirely (placeholder / switched-off abilities). | No |
| Projectile brain | `TBrainWelaProjectileComponent`, `...Server.Brains.pas:833` | A projectile that fires as soon as it gets a target (the game drives its projectiles another way). | No |
| Wela count modifier | `TModifierWelaCountComponent`, `BaseConflict.EntityComponents.Shared.Wela.pas:59` | Adds to an ability's `eiWelaCount` (e.g. how many units it spawns): a flat offset, or the number of units on the map (all or enemy) with given properties, optionally times a resource. | No |
| Trigger on kill | `TAutoBrainOnKillComponent`, `...Server.Brains.pas:558` | An ability that fires at the unit it just killed (or at itself, `FireAtMyself`). | No |
| Survival mode director | `TSurvivalScenarioDirectorComponent`, `GameServer/BaseConflict.EntityComponents.Server.pas:1041` | A scenario director that computes a "threat" level each tick for a survival mode (waves scaled to how the player is doing). | No |
| Instant kill warhead | `TWarheadSplashKillComponent`, `...Server.Warheads.pas:284` | Kills everything hit at once, ignoring shields and abilities (`Sacrifice` / `Exile` variants). | No |
| Resource steal warhead | `TWarheadSplashResourceCollectComponent`, `...Server.Warheads.pas:243` | Takes a resource from every target hit and gives it to the owner, optionally converted to another resource. | No |
| Inherit creator value | `TWelaEffectInheritEventValueComponent`, `...Server.Welas.pas:440` | Units a spawner produces copy one of the spawner's values (read at creation). | No |
| Ready after game time | `TWelaReadyAfterGameTimeComponent`, `BaseConflict.EntityComponents.Shared.Wela.pas:728` | An ability that only unlocks after the match has run a set number of seconds (game ticks). | No |
| Ready every Nth tick | `TWelaReadyEachNthGameTickComponent`, `...Server.Welas.pas:197` | An ability that is ready once every N game ticks (default 60) since its creation. | No |
| Target by buff | `TWelaTargetConstraintBuffComponent`, `BaseConflict.EntityComponents.Shared.Wela.pas:513` | An ability that may only (or may never) target units carrying certain buff types, e.g. dispel only buffed enemies. | No |
| Global targeting | `TWelaTargetingGlobalComponent`, `...Server.Welas.pas:141` | Picks the best targets anywhere on the map instead of in range. | No |
| Rectangle targeting | `TWelaTargetingRectangleComponent`, `...Server.Welas.pas:160` | Picks targets in a rectangle in front of the unit (a line/beam area) instead of a circle. | No |
| Boolean ready check | `TWelaReadyBooleanComponent`, `BaseConflict.EntityComponents.Shared.Wela.pas:587` | An ability is ready by combining the readiness of two other groups with AND / OR / NOT. | No |
| Instant chain projectile | `TAutoBrainWelaInstantChainComponent`, `...Server.Brains.pas:537` | A projectile that jumps from target to target at once, never hitting one twice. Its own code says "Not working atm." | No |
| Simple scripted AI | `TScenarioComponent`, `GameServer/BaseConflict.EntityComponents.Server.pas:764` | "A very simple AI for a commander": builds and spawns units at set timestamps (the game uses the scenario directors instead). | No |
| Add-component warhead | `TWarheadSpottyBuffComponent`, `...Server.Warheads.pas:144` | Each hit adds a named component class to the target (a generic "apply any buff" warhead). | No |
| Damage type trigger check | `TWelaTriggerCheckTakeDamageTypeComponent`, `BaseConflict.EntityComponents.Shared.Wela.pas:560` | An on-damage-taken ability that only reacts to (or ignores) certain damage types, e.g. "when hit by ranged". | No |

## Unused options of used classes

| Option | Where | What it would do | Ported? |
| --- | --- | --- | --- |
| Resolve by level / resource | `TWelaHelperResolveComponent.ResolveLevel`, `.ResolveResource`, `BaseConflict.EntityComponents.Shared.Wela.pas:2731` | An ability's damage, range, cooldown, spawned unit etc. picked per unit level (or per amount of an integer resource), from values saved under that index. | Yes |
| Delayed self script | `TWarheadApplyScriptComponent.ApplyToSelfAfterDelay`, same unit `:2345` | Applies a script to the unit itself once a delay is over (e.g. a buff that kicks in N seconds after spawning). | Yes |
| Float / boolean script parameters | `TWarheadApplyScriptComponent.PassSingleValue`, `.PassBooleanValue` | Passes a fixed float or boolean to the applied script (only integers are passed). | Yes |
| Paths through other units | `TMovementComponent.ComputeNewPath` `IgnoreOtherEntities`, `BaseConflict.EntityComponents.Shared.pas:671` | A unit that plans a path around the terrain but walks through other units. Unreachable: it is on only for units with `udUsePathfinding` off, and those walk straight (`IdleDirect`) and never compute a path. Broken too (the search then only expands blocked tiles, see `docs/map.md`). | Yes |
| Commander pays | `TWelaEffectPayCostComponent.CommanderPays`, `GameServer/BaseConflict.EntityComponents.Server.Welas.pas:2030` | A unit's ability paid from its player's resources instead of its own. | Yes |
| Suicide without removal | `TWelaEffectSuicideComponent.DontFree`, same unit `:2039` | A self-destruct that runs the death but leaves the unit in the game. | Yes |
| Fire at link ends | `TWelaEffectFireComponent.RedirectToLinkSource`, `.RedirectToLinkDestination`, same unit `:2910` | Meant to fire at a link's source / destination; unfinished: they only set flags that `Fire` never reads. | Yes (no-ops, as in the original) |
| Resource warhead on cost / commander | `TWarheadSpottyResourceComponent.ChangesCost`, `.TargetsOwningCommander`, `GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:477`, `:546` | A hit that makes a target's card cheaper/dearer, or gives/takes resources from the target's player. | Yes |
| Spotty percentage of current health | `TWarheadSpottyHealthComponent.PercentageOfCurrentHealth`, same unit `:594` | Damage or heal as a share of the target's current health (only the max-health variant is used). | Yes |
| Mixed squads / ring spawns | `TWelaEffectFactoryComponent.SpawnsDifferentUnits`, `.SpreadSpawnsOnCircle`, `...Server.Welas.pas:422`, `:426` | A factory spawning a different unit per index of `eiWelaUnitPattern` (a mixed squad), or its units on a circle of `eiWelaAreaOfEffect` around the target instead of anywhere inside it. | Yes |
| Projectile volleys and link projectiles | `TWelaEffectProjectileComponent.MultipleProjectiles`, `.IsLinkEffect`, `.ReverseLink`, `...Server.Welas.pas:557-563` | `eiWelaCount` projectiles per target, or projectiles leaving from a link's source / destination instead of the shooter. | Yes |
| Links hitting both ends | `TLinkBrainComponent.FiresAtSources`, `GameServer/BaseConflict.EntityComponents.Server.pas:163` | A link that, on each cooldown, also fires a group at its source (e.g. a drain beam that heals the caster while it damages the target). | Yes |
| Spawner timing and scatter | `TBrainSpawnerComponent.FireNotInitially`, `.ApplyRandomOffset`, `...Server.Brains.Special.pas:64-66` | A spawner that skips its first wave (at game start / placement), or scatters its spawn point by ±1 on each axis. | Yes |
| Spawn with front | `TServerEntityManagerComponent.SpawnUnitWithFront`, `GameServer/BaseConflict.EntityComponents.Server.pas:379` | Scenario scripts spawning a unit facing a chosen direction (they use the plain, overwatch and no-lifetime variants). | Yes |
| Whole-grid and ordered waves | `TWelaEffectWaveSpawnComponent.SpawnAllTogether`, `.SpawnInOrder`, `GameServer/BaseConflict.EntityComponents.Server.Welas.Special.pas:73-74` | Every spawner on the build grid spawning at once each wave, or the spawners taking turns in grid order instead of a random order (the tutorial uses its own fixed order). | Yes |
| Unused mesh effects | `TMeshEffectColorOverlay`, `TMeshEffectTeamColor` (via `TMeshComponent.ApplyTeamColoring`), `TMeshEffectSlidingTexture`, `TMeshEffectSoulExtract`, `TMeshEffectSpawnerSpawn`, `BaseConflict.EntityComponents.Client.Visuals.pas:542-833` | A flat color over a unit; hue-shifting masked parts to the team color; a scrolling texture overlay; a ghost flying out of a unit; a cyan build-up for spawners. No script or code creates them (not exposed to scripts, so the class finder does not list them). | No |
| Procedural trees | `TTree`, `Engine/Engine.Vegetation.pas:99` | Trees generated from a trunk spline and leaf quads (height, thickness, leaf count, gravity), with their own trunk / leaf textures. No map uses them: both maps' vegetation is palm meshes and grass tufts. | No |
| Sky reflection on water | `TWaterSurface.SkyTexture`, `Engine/Engine.Water.pas:79` | A spherical environment map reflected by the water instead of the flat `SkyColor`. Both maps leave it empty. | No |
| Terrain from a picture / OBJ | `TTerrain.LoadFromGrayscaleTexture`, `.LoadFromOBJ`, `Engine/Engine.Terrain.pas:541`, `:1016` | Map-editor ways to create a terrain from a grayscale heightmap or a mesh. The game only loads `.ter` files. | No |

## Developer tools (debug views, not gameplay)

| Tool | Where | What it shows |
| --- | --- | --- |
| Movement visualizer | `TMovementVisualizerComponent`, `BaseConflict.EntityComponents.Client.Debug.pas:39` | Circles where units stop or reach move targets, the planned path spline. |
| Position / sub-position visualizers | `TPositionVisualizerComponent` (`:75`), `TSubPositionVisualizerComponent` (`:85`) | Unit positions and attachment points (e.g. where projectiles leave). |
| Pathfinding visualizers | `TPathfindingGridVisualizerComponent` (`:96`), `TPathfindingPathVisualizerComponent` (`:117`) | The pathfinding grid and the paths units take. |
| Build grid visualizer | `TWelaTargetConstraintGridVisualizedComponent`, `BaseConflict.EntityComponents.Client.GUI.pas:672` | Grid cells in red / green where a building can or cannot be placed. |
| Resource console | `TResourceDisplayConsoleComponent`, same unit `:373` | Prints a unit's resource values to the console. |
| Debug event warhead | `TWarheadDebugThrowEventComponent`, `...Server.Warheads.pas:44` | Fires a chosen global event when it hits: for testing. |

These could become a debug overlay for the port (useful while checking movement against the original).
