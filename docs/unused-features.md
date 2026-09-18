# Unused features of the original

Things the original's code can do that no script or game code in the pinned version ever uses. The port stays
1:1, so none of this is switched on; the list is for deciding, once the game is finished, whether any of it is worth
adding. ("Wela" in the original = a weapon or ability of a unit.)

How the list is kept:
- **Whole classes**: `python tools/find_unused_classes.py` lists every class exposed to scripts
  (`ScriptManager.ExposeClass`) whose name appears in no script (`.dws/.ets/.sps`) and in no other code (case
  ignored, as Delphi and DWScript do). Rerun it after changes to the pinned source; 26 classes on 2026-09-18.
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
| Link that buffs spawns | `TLinkEffectFireAtProducedUnitsComponent`, `...Server.Welas.pas:720` | While linked to a spawner, every unit it spawns gets an effect. | No |
| Trigger before damage | `TAutoBrainOnWillDealDamageComponent`, `...Server.Brains.pas:691` | An ability that fires just before a unit deals damage (vs. the used "after damage" variant). | No |
| Chance on-hit effects | `TAutoBrainWelaOnHitEffectComponent`, `...Server.Brains.pas:786` | On every attack, another effect fires, optionally only by a chance (e.g. 20% to stun). | No |
| Abilities on the own commander | `TBrainWelaTargetCommanderComponent`, `...Server.Brains.pas:411` | A unit ability that fires at its own player's commander entity; what that does depends on the effect put with it. | No |
| Only own units | `TWelaTargetConstraintOwningComponent`, `BaseConflict.EntityComponents.Shared.Wela.pas:447` | An ability that may only target units of the same player (not just the same team). | No |
| Never usable | `TWelaTargetConstraintNeverComponent`, same unit `:273` | Disables an ability entirely (placeholder / switched-off abilities). | No |
| Projectile brain | `TBrainWelaProjectileComponent`, `...Server.Brains.pas:833` | A projectile that fires as soon as it gets a target (the game drives its projectiles another way). | No |

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
