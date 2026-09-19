# Entity core (phase 2)

Hand port of `BaseConflict.Entity.pas` into `src/runtime/entity/`, method by method, Delphi names kept.
Tests: `tests/test_entity_core.gd` (every expectation is derived from the Pascal method named in its comment).

| File | Original |
| --- | --- |
| `t_object.gd` | `TObject`: `Create`, virtual `Destroy`, `Free`, `ClassName` |
| `t_entity.gd` | `TEntity` |
| `t_entity_component.gd` | `TEntityComponent` (+ `TSubscribedEvent`) |
| `t_eventbus.gd` | `TEventbus` (+ `RSubscriber`, `TEventhandler`, `TEventEnumerator`), script side `TEventbusScriptSideHelper` |
| `t_blackboard.gd` | `TBlackboard`, script side `TBlackboardScriptInvoker` |
| `t_remote_subscription.gd` | `TRemoteSubscription` |
| `r_param.gd` | `RParam` accessors (`Engine/Engine.Helferlein.Windows.pas`) |
| `d_set.gd` | Delphi sets (`SetComponentGroup`, `SetUnitProperty`, ...) |
| `../base_conflict_constants.gd` | functions of `BaseConflict.Constants.pas` (`EventIdentifierToNetworkSend`, ...) |

## How the original works (the parts that matter for porting components)

- **Eventbus**: per entity, plus one global bus per game (owner nil). An event is `(EnumEventIdentifier,
  EnumEventType)` with type `etRead`, `etTrigger` or `etWrite`. Subscribers are components. Order: by
  `EnumEventPriority` (`epFirst` … `epLast`), then by subscription order (`AddSubscriber` inserts before the first
  subscriber with a *greater* priority).
- **Groups**: `Trigger/Read(event, values, Group, ComponentID)`. `Group = []` reaches every subscriber; else the
  component's group must intersect it, or the component is in `ALLGROUP` (`[255]`). `ComponentID <> 0` targets
  one component.
- **Trigger/Write**: a handler returning `False` stops the event. `Write` = trigger with `etWrite` handlers, then
  `Values[0]` goes into the blackboard under that group. Events listed in `EventIdentifierToNetworkSend` for the
  bus's side are also forwarded as `eiNetworkSend` on the global bus.
- **Read**: starts with the blackboard value, then every read handler returns the new result. A handler with one
  parameter more than the call passes gets the previous result as its last parameter.
- **Handlers change their `var` parameters in place**: all handlers of one event share one parameter array
  (e.g. `TArmorComponent.OnDamage(var Amount ...)` lowers damage for the handlers after it).
- **Subscribing or freeing during an event**: the running enumerators are shifted, so a subscriber inserted
  before/at the current position is skipped this time, one after it runs; a freed later subscriber never runs.
- **Blackboard**: `[event][group + 1][index + 1]`; group slot 0 = no group, index slot 0 = the plain value.
  With several groups, `GetValue` walks them **ascending** and takes the first non-empty value. No fallback to
  the global value (that is `ReadHierarchic`, on the bus).
- **Component groups**: `ReserveFreeGroup` hands out 19, 20, … (reserved = -1 until the first component joins);
  `FreeGroups` triggers `eiBeforeFree`/`eiFree` to the groups (ALLGROUP components ignore grouped frees).
- **Component IDs**: server counts up from `low(integer)`, client down from `high(integer)`.
- **Entity creation**: `TEntity.Create` adds a `TResourceManagerComponent` (ALLGROUP) to every entity, so a new
  entity's first component ID is taken by it.

## Port conventions (use these when porting components)

- **Constructors** are instance methods returning `self`: `TFoo.new().CreateGrouped(Owner, Group, ...)`. GDScript
  lets an override add parameters only **with defaults**, so a subclass writes
  `func CreateGrouped(Owner = null, Group = [], Path = "", ...) -> TEntityComponent`, calls `super(Owner, Group)`
  where Delphi says `inherited`, and returns self. Note that `TEntityComponent.Create` calls `CreateGrouped`
  virtually, which reaches a subclass's longer `CreateGrouped` (with defaults) in GDScript.
- **Destructors**: override `Destroy()`, call `super()` last. `Free()` calls `Destroy()`. `Destroy` must also drop
  back-references (owner, handlers) because the port is reference counted and cycles would leak.
- **Event handlers** (Delphi `[XEvent(...)]`): list them in `_DeclareEvents`:
  ```gdscript
  func _DeclareEvents(e: Array) -> void:
      super(e)
      e.append(XEvent("OnDamage", C.eiDamage, C.epMiddle, C.etRead))
      e.append(XEvent("OnGameTick", C.eiGameTick, C.epLast, C.etTrigger, C.esGlobal))
  ```
  A later entry for the same event and type replaces an earlier one (derived class wins). Parameter count comes
  from the method. Trigger/write handlers return `bool`; read handlers return the value.
- **`var` parameters**: assign with `SetVarParam(index, value)` (writes into `TEventbus.CurrentParameters`).
- **RParam** is a plain Variant, `null` = empty. Read with `RParam.AsInteger/AsSingle/AsBoolean/AsString/
  AsVector2/AsSet/...`. Like the release build of the original these are memory casts: `AsSingle` on an integer
  reinterprets the bits. Script floats become 32-bit singles when stored (`RParam.ToSingle`).
- **Sets** (`SetComponentGroup`, `SetUnitProperty`, `SetDamageType`, ...) are sorted int Arrays (`DSet.Make`).
  `x in S` → `S.has(x)`, `A * B <> []` → `DSet.Intersects(A, B)`.
- **Overloads** become one method dispatching on argument type or a `null` default
  (`CardLevel()` / `CardLevel(Byte)` / `CardLevel(TArray<Byte>)`).
- **Exceptions** (`raise`, `MakeException`) become `push_error`; the event continues.
- **`out` parameters**: `TryGetFoo(x, out Y): Boolean` becomes `TryGetFoo(x)` returning `Y` or `null`
  (`Game.EntityManager.TryGetEntityByID(ID)`, `TryGetOwningCommander(Entity)`).
- **`{$IFDEF SERVER}` handlers**: list them in `_DeclareEvents` under `if IsServerSide():` (the subscription
  patterns are cached per class *and* side); `{$IFDEF SERVER}` code in a body also tests `IsServerSide()`.
- **`Game` in components** (the per-process global): `GlobalEventbus().Game`. The original never checks it for
  nil where it uses `Game.EntityManager`; the port treats a missing `Game` (tests, no game loop yet) as "found
  nothing".
- **Two sides in one process**: the original ran client and server as separate programs. Here each `TEventbus`
  has `ApplicationType` (`nsServer`/`nsClient`, replaces `APPLICATIONTYPE`) and `Game` (replaces the `Game`
  global); an entity takes both from its global bus (`TEntity.IsServer()` for `{$IFDEF SERVER}` code paths).
- **Bus speed-ups** (same behaviour, see `t_eventbus.gd`): each `RSubscriber` carries its handler as a Callable
  and calls it (the original's `TEntityComponent.OnRead` / `OnTrigger` lookup is gone); an event called to one
  group walks only the subscribers of that group (`TEventhandler.MatchingIndices`, dropped on any subscribe /
  unsubscribe and on any component group change via `TEventbus.GroupsVersion`; after a change mid-event the walk
  goes on as the original's); the event stack lives in `Read` / `Trigger` locals. Change a component's group only
  through the `ComponentGroup` setter, never by editing `FComponentGroup` in place. `TEventbus.Prof = {}` times
  every handler (`tests/profile_sandbox.gd`, `tests/bench_eventbus.gd`).

## Script runner (`TEntity`, tests in `tests/test_script_runner.gd`)

- `TEntity.CreateFromScript(file, bus[, Initializer])` / `CreateMetaFromScript` / `CreateDataFromScript` are static
  and run `CreateEntity` / `CreateMeta` / `CreateData`; `IsAbstract` = meta. `Initializer` is a `Callable(Entity)`.
  Inheritance order as in `docs/scripts.md`; the entity keeps the file name first asked for.
- `ApplyScript(file, proc = "Apply", params)` (empty params = `[self]`), `ApplyScriptReturnGroups(file, proc)`
  (returned ints truncated to bytes, as a set; `[]` if the routine returns no array).
- `CompileScriptFromFile(path, Server)`: resolves any case/slash, relative to or inside `Scripts\`, through
  `script_index.gd` for the side (`IsServer()`, or the global bus's `ApplicationType` for the static creators),
  and instantiates the script (= `RunMain`). `GlobalEventbus` / `Game` globals are set from the global bus.
- Where the original raised (missing file, `ORIGINAL_COMPILE_ERROR`, unknown routine, parameter count mismatch):
  `push_error`, `TEntity.LastScriptError`, creators return `null`. `QuietScriptErrors` silences it for tests.
- `Game`: scripts that declare `var Game` get the bus's `Game` (`_SetScriptGlobals`); the others call the exposed
  function `Game()` (`L.Game()`), a threadvar in the original. Here `ExecuteFunction(..., GlobalEventbus)` keeps a
  stack of the running scripts' buses and `L.Game()` returns `TEntity.ScriptGame()` (the innermost bus's `Game`)
  unless `L.game_resolver` is set.

## Shared components (`src/runtime/components/`)

One file per class, `class_name` = Delphi name (the transpiler then drops its stub). Tests: `tests/test_<name>.gd`.

| File | Original |
| --- | --- |
| `t_resource_manager_component.gd` | `TResourceManagerComponent` (`BaseConflict.EntityComponents.Shared.pas:386`), on every entity |
| `../types/r_resource_cost.gd` | `RResourceCost` + `AResourceCostHelper` (`BaseConflict.Types.Shared.pas:32`) |
| `t_unit_property_component.gd` | `TUnitPropertyComponent` (`:36`): adds/removes unit properties, or gives them to the owning commander |
| `t_armor_component.gd` | `TArmorComponent` (`:521`): armor factor/offset on the `var` Amount of `eiTakeDamage` |
| `t_health_component.gd` | `THealthComponent` (`:173`): damage, heal, overheal, death chain; base `../entity/t_serializable_entity_component.gd` (network serialization) |
| `t_commander_income*_component.gd` | `TCommanderIncome{,Default,Loan,Overflow}Component` (`:531-574`): the commander's `eiIncome` |
| `../types/r_income.gd` | `RIncome` (`BaseConflict.Types.Shared.pas:47`), a record: copies in and out of RParams |
| `t_dynamic_zone_*emitter_component.gd` | `TDynamicZone{,Radial,Axis}EmitterComponent` (`:581-614`): answer `eiInDynamicZone` |
| `t_game_event_enumerator_component.gd` | `TGameEventEnumeratorComponent` (`:630`): lists its owner for `eiGameEvent` |
| `t_modifier_*component.gd` | `TModifier{,DamageType,WelaTargetCount,Resource,MultiplyCooldown,ArmorType,WelaDamage,WelaRange,Cost}Component` (`Shared.Wela.pas:32-207`) |
| `t_wela_ready_*component.gd` | `TWelaReady{,Cost,Cooldown,AfterGameStart,AfterGameEvent,ResourceCompare,UnitProperty,Creator,EventCompare}Component` (`Shared.Wela.pas:575-767`) |
| `../types/t_game_timer.gd` | `TGameTimer` (`BaseConflict.Types.Shared.pas:54`): TTimer with `StartingTime` |
| `t_wela_target_constraint_*component.gd`, `t_wela_trigger_check_*component.gd` | `TWelaTargetConstraint*` (all 21 used; Grid/BuildTeam/Zone in `docs/map.md`) and `TWelaTriggerCheck{TakeDamage,NotSelf,TakeDamageThreshold}Component` (`Shared.Wela.pas:222-560`) |
| `../types/r_target.gd`, `a_target.gd`, `r_target_validity.gd` | `RTarget`, `ATarget` helpers, `RTargetValidity` (`BaseConflict.Types.Target.pas`) |
| `t_wela_helper_resolve_component.gd` | `TWelaHelperResolveComponent` (`Shared.Wela.pas:941`): wela values per team / level / tier |
| `t_warhead_apply_script_component.gd`, `t_warhead_link_apply_script_component.gd` | `TWarheadApplyScriptComponent` / `TWarheadLinkApplyScriptComponent` (`Shared.Wela.pas:855`, `:918`): apply a script to targets / link destinations |
| `../classes/t_entity_data_cache.gd` | `TEntityDataCache` (`BaseConflict.Classes.Shared.pas:27`): one data entity per card file / league / level |
| `t_wela_event_redirecter.gd`, `t_wela_ready_spawned_component.gd` | `TWelaEventRedirecter`, `TWelaReadySpawnedComponent` (`Shared.Wela.pas:832`, `:661`): wela values / readiness from the produced unit's data |
| `t_entity_manager_component.gd` | `TEntityManagerComponent` (`:276`): `Game.EntityManager`, entity registry and deferred freeing |
| `../engine/t_timer.gd`, `t_time_manager.gd` | `TTimer` (whole) and the `TTimeManager` clock (`Engine.Helferlein.Windows.pas:985`) |
| `t_position_component.gd`, `t_movement_component.gd`, `t_pathfinding_component.gd` | `TPositionComponent` (`:98`), `TMovementComponent` (`:108`), `TPathfindingComponent` (`:497`): movement, see "Movement" |
| `t_collision_manager_component.gd`, `t_server_collision_manager_component.gd`, `t_collision_component.gd`, `t_wela_ready_enemies_nearby_component.gd` | `TCollisionManagerComponent` (`:443`), `TServerCollisionManagerComponent` (`Server.pas:346`), `TCollisionComponent` (`:474`), `TWelaReadyEnemiesNearbyComponent` (`Shared.Wela.pas:685`): range queries, see "Collision" |
| `t_wela_targeting*_component.gd`, `t_wela_efficiency*_component.gd`, `../engine/delphi_sort.gd` | `TWelaTargeting{,Radial,RadialAttention,Nexus,Self}Component` and `TWelaEfficiency{,MissingHealth,Created,MaxHealth,DamageType,UnitProperty}Component` (`GameServer/...Server.Welas.pas:40-116`, `:828-885`), Delphi's `TList.Sort`: see "Targeting" |
| `t_wela_effect*_component.gd`, `t_wela_efficiency_effect_component.gd`, `t_wela_helper_{beacon,init_active_after_game_start,activate_timer}_component.gd` | `TWelaEffect{,Instant,OnlyByChance,Redirecter,PayCost,ActivationAbility,Suicide,TriggerSpellCast,RemoveAfterUse,IncreaseResource,GameEvent,Fire,ResetCooldown,RemoveBeacon}Component`, `TWelaEfficiencyEffectComponent`, `TWelaHelper*` (`...Server.Welas.pas:253-537`, `:781-826`): see "Effects" |
| `t_warhead*_component.gd` | `TWarhead{,Spotty,SpottyHealth,SpottyDamage,SpottyHeal,SpottyKill,SpottyRemoveBuff,SpottyResource,SpottyWelaStop}Component` (`GameServer/...Server.Warheads.pas:29-215`): see "Warheads" |
| `t_think_*_component.gd`, `t_brain*_component.gd`, `t_auto_brain*.gd`, `../classes/t_delayed_event_handler.gd`, `../types/r_commander_ability_target.gd` | every used class of `GameServer/...Server.Brains.pas` (8 think impulses / block, 21 brains, 20 auto-brains), `TDelayedEventHandler` (`...Classes.Server.pas:93`), `RCommanderAbilityTarget` (`BaseConflict.Types.Target.pas:115`): see "Brains" |
| `t_server_entity_manager_component.gd`, `../classes/t_game_statistic_manager.gd`, `t_wela_effect_{factory,replace,projectile}_component.gd`, `t_projectile_event_redirecter.gd`, `t_brain_{spawner,capture_point}_component.gd` | `TServerEntityManagerComponent` (`GameServer/...Server.pas:358`), `TGameStatisticManager` (`...Classes.Server.pas:20`), `TWelaEffect{Factory,Replace,Projectile}Component`, `TProjectileEventRedirecter` (`...Server.Welas.pas:337-564`, `:660`), `TBrain{Spawner,CapturePoint}Component` (`...Server.Brains.Special.pas`): see "Spawning" |
| `t_warhead_splash*_component.gd`, `t_warhead_spotty_teleport_component.gd` | `TWarheadSplash{,Health,Damage,Heal}Component`, `TWarheadSpottyTeleportComponent` (`...Server.Warheads.pas:66`, `:222-279`): see "Splash and teleport" |
| `t_{,server_}primary_target_component.gd`, `t_suicide_on_game_end_component.gd`, `t_wela_effect_{income_payout,wave_spawn}_component.gd`, `t_statistics_unit_component.gd`, `t_wela_effect_statistics_component.gd`, `t_server_card_play_statistics_component.gd` | `TPrimaryTargetComponent` (`:620`), `TServerPrimaryTargetComponent` (`Server.pas:139`), `TSuicideOnGameEndComponent` (`Client.pas:462`), `TWelaEffect{IncomePayout,WaveSpawn}Component` (`...Server.Welas.Special.pas`), `TStatisticsUnitComponent`, `TWelaEffectStatisticsComponent` (`...Server.Statistics.pas`), `TServerCardPlayStatisticsComponent` (`Server.pas:330`): see "Game end, waves, statistics" |
| `t_commander_ability{,_component}.gd`, `t_commander_component.gd`, `../classes/t_card_info{,_manager}.gd`, `../types/r_commander_card.gd`, `../engine/delphi_{hash,rtl}.gd` | `TCommanderAbility` (`Server.pas:473`), `TCommanderAbilityComponent` + `RCommanderCard` (`:225-250`), `TCommanderComponent` (`Client.pas:199`), `TCardInfo` / `TCardInfoManager` (`BaseConflict.Constants.Cards.pas:87`, `:172`): see "Commander and cards" |

Tests: `tests/test_unit_property_component.gd`, `test_armor_component.gd`, `test_health_component.gd` (incl. the
real server `Units\Colorless\SmallMeleeGolem`), `test_commander_income.gd` (incl. the real server
`Commander\CommanderTemplate` with a fake Game at the TGame defaults), `test_timer.gd`, `test_dynamic_zone.gd`; `tests/component_fakes.gd`
has an event probe and a fake `Game.EntityManager` for component tests.

- **Income** (`eiIncome`, global read `[CommanderID]` → `RIncome`): only the components of the entity whose
  `eiOwnerCommander` matches adjust it. Default (epFirst) adds its group's `eiResourceCost` gold +
  `eiWelaDamage` × `reIncomeUpgrade`; Loan (epMiddle, EchoesOfTheFuture) multiplies gold by Factor for Duration,
  then gives no gold for Duration × Factor / 2; Overflow (epLast) turns gold over the cap into wood.
- **Dynamic zones** (`eiInDynamicZone`, global read `[Position, TeamID, Zones]`): empty = no emitter covers it,
  `true` = covered, `false` = an `Exclude()` emitter covers it; once false, later emitters cannot make it true.
  Radial: `eiWelaRange` of its group around the owner, owner's team or TeamID <= -1. Axis: dot of the direction
  from its point with its normal >= 0 (`SetPosition` normalizes the point, as in the original).
- **Game events** (`eiGameEvent`, global read `[Name]`): an Array of the owners listening to that name, or empty.
- **Modifiers** (`tests/test_modifier_components.gd`, incl. the real `Modifiers\BlessingHealth` on the server
  SmallMeleeGolem): read handlers at epMiddle that change a value read from their groups, using eiWelaModifier
  (or eiWelaDamage) of `SetValueGroup` (default: own group); `ReadyGroup` makes them work only while eiIsReady of
  that group is true or empty (checked by ArmorType, WelaDamage, WelaRange). `TModifierResourceComponent` is the
  exception: it changes a resource cap once on `ApplyNow` and takes it back in `BeforeComponentFree` (needs
  `Game.IsShuttingDown`). Delphi `Round` is banker's rounding (`L.Round`). `TModifierWelaCountComponent` and
  `TModifierMultiplyMovementSpeedComponent` are unused and not ported (`docs/unused-features.md`).
- **Ready checks** (`tests/test_wela_ready_components.gd`, incl. the real server SmallMeleeGolem's attack
  cooldown): `eiIsReady` read in a wela's group is the AND of every ready component there, read at epFirst on
  top of the blackboard value (empty = true). `TWelaReadyCooldownComponent` (not a `TWelaReadyComponent`) only
  answers reads that touch its ReadyGroup; interval = eiCooldown - eiWelaActionpoint; the server writes the start
  to `eiCooldownStartingTime`, the client's timer reads it from there on every check. Helpers in `BC`:
  `ResourceCompare` (int resources compare with `Round(Reference)`), `ResourceAdd`, `ResourcePercentage`.
  `TWelaReadySpawnedComponent`: see "Data cache" below; `TWelaReadyEnemiesNearbyComponent`: see "Collision".
  `TWelaReadyBooleanComponent` / `AfterGameTime` are unused.
- **Targets** (`tests/test_wela_target_constraints.gd`, incl. two real server SmallMeleeGolems in a real
  entity manager): an ATarget is an Array of RTarget (treat both as values: `Clone`). RTarget methods that read
  the original's `Game` global take the Game as a parameter (`GetTargetEntity(Game)`, `GetTargetPosition(Game)`);
  constraints pass `TargetGame()` = `GlobalEventbus().Game`. `eiWelaTargetPossible` / `eiWarheadTargetPossible`
  read `[ATarget]` in a wela's group returns an `RTargetValidity` (`FromRParam` for a copy; empty = valid): each
  constraint (epHigher, own group only) can only make targets invalid; empty targets start invalid.
  `eiWelaTriggerCheck` `[Amount, DamageType, InflictorID]` is the AND of the trigger checks. Quirk kept:
  MaxTargetDistance only compares empty targets (never fails). Waiting for the map: `TWelaTargetConstraint{Grid,
  BuildTeam,Zone}Component` (stubs), `RTarget.GetBuildZone`, build targets' positions.
- **Entity manager** (`tests/test_entity_manager.gd`): `eiNewEntity` (sent by `TEntity.Deploy`) registers,
  `GenerateUniqueID` counts from 2. `eiKillEntity` unregisters at once and frees at the next `Idle` (called by the
  game loop); `eiRemoveComponent` / `eiRemoveComponentGroup` / `FreeEntity` are deferred to `Idle` too.
  `eiReplaceEntity` re-keys the entity and its pending kills and updates `Game.Map.BuildZones`;
  `eiSetGridFieldBlocking` needs `Game.Map` as well (both untested until the map exists). Quirk kept:
  `NexusNext` / `NexusNextEnemy` return the *farthest* nexus (`bestDistance < distance`). The registry is an
  insertion-ordered Dictionary (original: hash order). `InvokeEventOnEntity` waits for `InvokeWithRawData`.
- **Resolve** (`tests/test_warhead_apply_script.gd`): `TWelaHelperResolveComponent` answers wela reads (epFirst)
  with the blackboard value at index = team ID / `reLevel` / a resource / game tier (0-2 by `eiGameEventTimeTo` of
  tech2/tech3) / owner tier, in the group the read was called to; else the previous value. Quirk kept: owner tier
  gives 1 for `upTier1` and `upTier2`, 3 otherwise.
- **Apply script** (same test file, real `BlessingHealth`, `SummoningSickness`, `Links\Invisible`):
  `TWarheadApplyScriptComponent` runs `Entity.ApplyScript(Script, Methodname or 'Apply', [Entity, Pass* values...])`
  on eiFireWarhead entity targets (local call), or on eiWelaUnitProduced (`ApplyToProducedUnits`), or on its owner
  at eiAfterCreate / the first global eiIdle after a delay (then `DeferFree`). Pass* values are read at apply time
  (`RWarheadParameter.GetValue`); eiColorIdentity / eiTeamID / eiFront are read without group; unset record fields
  are zero (original: stack garbage). The link variant never applies at fire: at eiAfterCreate it applies to the
  first `eiLinkDest` if `eiWelaTargetPossible` of its group allows, copies eiCreator / eiCreatorGroup into the new
  groups, and removes them (global `eiRemoveComponentGroup`, deferred) when freed or when its target is replaced.
- **Data cache** (`tests/test_entity_data_cache.gd`, real VoidSkeletonDrop / TyrusDrop / Freeze data and
  `Commander\CommanderMethods` AddDrop): the original's `EntityDataCache` global (per game thread) is
  `TEventbus.EntityDataCache` on the global bus, set by the game and freed with the bus. `Read(file, league, level,
  event, group = [], index = -1, ByPassCache)` builds the data entity on first use (`CreateDataFromScript` with card
  level/league set; `.sps`: bare entity + `CreateData(Entity, 0, 1)`, and every group but [1] reads [0]), caches
  every result (empty too) until a bypassing read. `TWelaEventRedirecter` (epFirst) answers still-empty reads from
  the data of the eiWelaUnitPattern of the group the read was called to (at the component's card league/level);
  `CopyValue` / `CopyIndexedValue` copy once at setup. `TWelaReadySpawnedComponent` writes the wela's
  eiOwnerCommander into that data entity and uses its eiIsReady (legendary checks). A missing data entity reads
  empty (the original crashed).
- **Movement** (`tests/test_movement_component.gd`, incl. the real server Footman walking on the Single map):
  `eiMoveTo [RTarget, Range]` starts moving (an equal target while moving returns False, stopping the event);
  each global `eiIdle` moves by `TTimeManager.ZDiff` (ms, set by the game loop later) × `eiSpeed` (per ms) through
  `eiMove` (position + front). `udUsePathfinding` (read at eiAfterCreate) picks the mode. Direct: straight to
  within Range (+ SPATIALEPSILON), server re-syncs the position every 3000 ms. Pathfinding: the server computes a
  path (max 15, waypoint heuristic only towards a nexus entity) and sends `eiSyncPath [start, target, coords]`;
  both walk the tile centers, the last tile to the exact target, and stand on reaching the target's *tile*; the
  server re-paths when the path runs out or its next tile is blocked. The client straightens paths (OptimizePath)
  and scales its speed to arrive at the same time. `eiStand` reports `eiMoveTargetReached` only if it was moving;
  eiDie / eiExiled(true) / eiLose stand (the server's eiLose only clears FMoving, silently).
  `TPathfindingComponent` blocks its tile at eiAfterCreate and on eiStand; changing tile unblocks the old one
  without blocking the new one; eiStand and freeing drop the computed path. Both find the map as
  `Game.Map.Pathfinding` and do nothing without it (tests; the original crashed). Not ported: FTarget's network
  serialisation.
- **Collision** (`tests/test_collision.gd`, incl. the real client Lanetower's enemies-nearby check):
  `TCollisionManagerComponent` (`Game.CollisionManager`, on the game entity; the server uses
  `TServerCollisionManagerComponent`) keeps a loose quadtree (`src/runtime/engine/t_loose_quad_tree*.gd` +
  the entity variant `src/runtime/classes/t_entity_loose_*.gd`) over `Game.Map.MapBoundaries`, nodes down to
  width 16 (Single/Classic map: leaves 9.375 wide), each node counting its entities per team (0-5).
  `TCollisionComponent` (script: `Create(Entity)`) registers the owner as a circle of `CollisionRadius` (0.5 if
  none, with an error) and follows eiPosition / eiTeamID; eiExiled takes it out and back; eiDie sends the global
  `eiRemoveComponent` for itself. Global reads `[Pos, Range, SourceTeamID, TargetTeamConstraint, Filter]`:
  `eiEntitiesInRange` → Array of TEntity or null, `eiClosestEntityInRange` → TEntity or null (strict `<`: first
  found wins a tie), server `eiEnemiesInRangeEfficiency` → Array of `RTargetWithEfficiency` (Filter rates, < 0
  drops) or null. Filter = `Callable(Entity)` or null. Circles touch at `distance <= r1 + r2`. Result order is the
  tree order (children top-left, top-right, bottom-left, bottom-right; a node's items in list order, removal
  swaps the last item into the gap, moving or re-teaming re-adds at the end); it decides ties, so it is ported
  exactly. Range must be a float (`AsSingle` bit-casts ints). Quirks kept: a center outside the root is counted
  but stored nowhere; removal leaves `HasItems` stale above the parent node (only makes queries descend more).
  Distances are doubles (original singles). `TWelaReadyEnemiesNearbyComponent`: ready while an enemy within
  eiWelaRange of ValueGroup passes eiWelaTargetPossible of CheckGroup.
- **Targeting** (server, `tests/test_wela_targeting.gd`, incl. two real server SmallMeleeGolems finding each
  other): `eiWelaUpdateTargets [Targets]` (trigger in the wela's group) changes the caller's Array of RTarget in
  place; `eiWelaValidateTarget [RTarget or empty]` (read) answers a bool. A target is possible when it exists, is
  not exiled and passes eiWelaTargetPossible (validation: of `SetValidateGroup`, default own group); its
  efficiency is eiEfficiency `[Entity]` read in the group (+0.01 for the `SetTargetTeamConstraintPriority` team),
  -1 if not possible. Radial: fills free slots (eiWelaTargetCount, default 1; `MaxNewTargetCount`) from
  `eiEnemiesInRangeEfficiency` at range (eiWelaRange or `RangeFromEvent`) + own radius (unless
  `IgnoreOwnCollisionradius`), sorted only when there are more candidates than slots: efficiency high first, then
  not upLowPrio, then nearest (`PrioritizeMostDistant` / `PrioritizeMiddleDistant`); `Cone` drops units whose
  circle is outside the cone; validation adds the target's radius and needs efficiency >= 0. RadialAttention
  replaces the list with the one unit to approach (least `TLane.GetWeightedDistance` of eiGetLane, else nearest)
  among possible units within eiAttentionrange × 1.2, if it is within eiAttentionrange; its validation (and
  Nexus', Self's) needs efficiency > 0, so a group without efficiency components never keeps its target. Nexus:
  `TryGetNexusNextEnemy` (farthest, quirk). Self: the owner. Random picks (`PicksRandomTargets[WithRepetition]`)
  take the prioritized team first. New targets get `eiWelaYoureMyTarget [Owner]`. Sorting uses `DelphiSort`
  (Delphi 10.1's quicksort; assumed, the snapshot has no RTL) so ties keep the original's order. `Contains` uses
  `RTarget.Equal` (the original compared record memory, garbage fields included). Global / Rectangle targeting are
  unused (`docs/unused-features.md`).
- **Efficiency** (same test file): `TWelaEfficiency*Component` add to the previous eiEfficiency (epMiddle) in
  their group: missing health, age in ms (`TTimeManager.GetTimeStamp() - CreatedTimestamp`), health cap (Inverse:
  10000 - cap), 1 if the main weapon has a prioritized damage type, 1 if the target has a prioritized unit
  property (Reverse: 0). The effects (`TWelaEfficiencyEffectComponent`, epFirst) answer first and drop the
  previous value.
- **Effects** (server, `tests/test_wela_effects.gd`): `eiFire [ATarget]` called to a wela's group. Order:
  `TWelaEffectRedirecterComponent` (epFirst, may replace the `var` targets with the ground at the owner),
  `TWelaEffectOnlyByChanceComponent` (epMiddle, stops the event unless `eiWelaChance >= random`), then every
  `TWelaEffectComponent` (epLast) whose group the fire was called to runs `Fire` (a groupless fire only reaches
  groupless effects: `IsLocalCall`). Instant: `eiFireWarhead` to its target group if `eiWarheadTargetPossible` of
  the called-to group allows; efficiency 1, -1 against upUntargetable. Fire: `eiFire [one target]` per possible
  target in a ready target group (MultiTargetGroup: first group that fired wins; FireInCreator: all targets on
  `eiCreator` in `eiCreatorGroup`). PayCost: `eiResourceSubtraction` per cost except `NOT_PAYED_RESOURCES` (a static
  var here, the game sets it). ActivationAbility writes `eiWelaActive` only on change; its balance = cap test is
  `RParam.Equal` (type and value). `TWelaHelperInitActiveAfterGameStartComponent` reads `Game.IngameStatus`
  (`BC.gsPlaying`; no Game = not playing) and frees itself at the first `eiGameTick`; `TWelaHelperActivateTimer`
  at the first `eiIdle` after its delay. Beacons: `eiWelaSearch [SetUnitProperty]` collects the groups of matching
  `TWelaHelperBeaconComponent`s (ResetCooldown, RemoveBeacon, the resource warhead use it). The global
  `eiGameTickTimeToFirstTick` has no blackboard: the game's tick component answers it (phase 3). Factory, Replace,
  Projectile: see "Spawning". Not yet: the link effects and `TWelaEffectLinkPayCostMyselfComponentServer` (need
  links), `TWelaEffectStatisticsComponent`, `TWelaEffectWaveSpawnComponent`.
- **Warheads** (server, `tests/test_warheads.gd`, incl. a real server SmallMeleeGolem hitting another through its
  instant effect): `eiFireWarhead [ATarget]` in a group runs `FireWarhead` (epLast; RedirectToSelf: the owner).
  Spotty warheads act on each existing entity target. Health: amount = eiWelaDamage × eiWelaModifier (default 1)
  of its group (× health balance / cap for the percentage variants); damage asks the owner's `eiWillDealDamage`
  (non-empty replaces the amount), then the target's `eiTakeDamage`; dealt > 0 → owner `eiDamageDone [dealt,
  types, target]`; target dead → `eiKillDone [ID]` in its group. Heal: target `eiHeal`, healed > 0 →
  `eiHealDone`. Kill: `eiKill [owner, owner's commander]` (Exile / Sacrifice first; Remove: only the global
  `eiDelayedKillEntity`). Resource: amount rounded (banker's) for int resources, see the class comment. Splash and
  teleport: see "Splash and teleport".
- **Brains** (server, `tests/test_brains.gd`, incl. two real server SmallMeleeGolems fighting to the death): a
  think impulse triggers `eiThink` then `eiThinkChain` in its group (groupless for most units). eiThink (epMiddle)
  runs every brain that `CanThink` (no `UNIT_PROPERTIES_PREVENT_THINKING` unless passive, eiWelaActive of its group
  not false, ThinksLocal: a local call). The chain runs brains by priority until one returns False: action
  (epHigher, locked while a delayed shot waits and for max(1, action point, action duration)), targeting brains
  (epHigh; preemptive ones epMiddle), selftarget / saved / ground / targetless (epMiddle), approach / wait / flee
  (epLow), overwatch (epLower), lane (epLast, always consumes). Passive brains (all auto-brains) run their chain
  inside eiThink. Impulses: Timer (every `THINK_TIME_INTERVAL` 250 ms from creation, at once after
  eiMoveTargetReached; not exiled or dead), Once (first idle, or at eiAfterCreate / eiDeploy; frees itself), Now,
  GameTick, Immediate, Fire (eiFire in its own group), TimerCooldown (eiCooldown). Welas fire `eiFire`, or
  `eiPreFire` when Blocking / Preemptive: `TBrainActionComponent` then fires at `eiWelaActionpoint` through a
  `TDelayedEventHandler` in `Game.DelayedEvents` (a `TIntPriorityQueue`; `TDelayedEventHandler.ProcessDueEvents` is
  TServerGame.Idle's loop, before the global eiIdle; equal times come out last in, first out) and re-checks
  readiness and targets then (else `eiCancelFire`). Targeting brains keep a target list that the group's targeting
  changes in place and announce `eiWelaSetMainTarget`. Numbers from the golem test: 250 ms think + 533 ms action
  point = first hit at 783 ms, then every 1750 ms (ready 1167 ms after a shot, next think on the 250 ms grid); both
  golems strike in the same frame, so the 8th exchange kills both (the dead one's pending shot still lands: the
  server entity manager removes a unit one frame later). Quirks kept: `TAutoBrainOnDeathComponent.FireAtKiller`
  never changes the target (Delphi overloads: the override is never reached from CheckAndFire; `Fire()` /
  `FireTargets(Targets)` here); the commander brain's target-count assert is dropped (release build). Port notes:
  the original's `Fire(Amount, TargetEntity)` of the deal-damage brain is `FireDamage`; without
  `Game.DelayedEvents` delayed shots / projectile retargets are dropped. Unused and not ported: see `docs/unused-features.md` (link / kill / will-deal-damage /
  on-hit / commander-target / projectile / instant-chain brains).
- **Spawning** (server, `tests/test_spawning.gd`, incl. a real VoidSkeletonSpawner on a build field spawning its
  squad, and a dying real golem's soul flying to a soul gatherer): `TServerEntityManagerComponent` is the server
  game's `EntityManager` and `ServerEntityManager`. `eiDelayedKillEntity` → `eiKillEntity` at the next `Idle`
  (unregistered), freed at the one after. `SpawnUnit(Position, Front, Pattern, League, Level, TeamID, Commander = -1,
  Creator, Callback, PreProcessing, PostProcessing)` or the scripts' `SpawnUnit(X, Y, Pattern, TeamID)`:
  `INHERIT_FROM_GAME` = `Game.League` / `BC.MAX_LEVEL`; non-spawners are clamped to the walk zone
  (`Game.Map.ClampToZone`); `Game.Statistics.UnitSpawned`; the initializer writes team, position, front, commander
  (if >= 0), creator (+ its `ScriptFileName`), card league / level, then PreProcessing (the entity has ID 0 still);
  then the ID, Callback, sandbox overwatch (`Game.IsSandbox` + `Game.Overwatch[Clearable]`), `eiAfterCreate`, global
  `eiSendEntities [[Entity]]`, `Deploy`, PostProcessing. `SpawnSpawner` places a 1x1 unit on a build field and blocks
  it (`eiBuildgridBlockedFields` = Array of `[ZoneID, Vector2i]`). Fakes of the server game need `League`,
  `IsSandbox`, `ServerEntityManager`, `Map.ClampToZone` / `Map.Lanes` (and `Map.BuildZones` for replace / build
  targets). `TGameStatisticManager` (`Game.Statistics`, optional in fakes) counts per commander; `CardPlayed` waits
  for the card info. Factory: `eiWelaCount` units per target (SpreadSpawns: `RTarget.ComputeSpawningPattern`, or
  random within `eiWelaAreaOfEffect`); build targets sit at `RTarget.GetRealBuildPosition` and block their fields
  **with ID 0** (quirk: blocked in PreProcessing); `eiWelaUnitProduced [ID]` in the fired group, then groupless.
  Replace: `eiDelayedKillEntity` for the target, the new unit in its place, then `eiReplaceEntity [owner, new, False]`.
  Projectile: from the owner (**an owner at exactly (0, 0) shoots from the target**, quirk: "a commander"), values
  copied into blackboard group [0], a `TProjectileEventRedirecter` (damage done / kills / will-deal-damage go to the
  creator). Spawner brain: `eiWaveSpawn [GridID, Coord]` for its field fires group 0 at the zone's spawn target +
  grid offset through `RMatrix2x2.Inverse` **as coded** (the transpose of the inverse; for the rotation base: the
  base itself, so field (0, 0) of a 4x4 zone facing (0, 1) gives (-3, -3), not (3, 3)). Capture point: team groups in
  `SetTeamGroup` order (original: hash order). Unused options: `docs/unused-features.md`.
- **Splash and teleport** (server, `tests/test_splash_teleport.gd`, incl. a real MeleeGolemTower's cone splash):
  splash warheads query `eiEntitiesInRange` (all teams) around each target (an empty target ends the fire) with
  `eiWelaAreaOfEffect` of the value group, filtered by IgnoreMainTargets, the target's layer (ground / flyer, unless
  TargetsGroundAndAir), LineFromOwner(width) or the cone `eiWelaAreaOfEffectCone` (from the owner), and
  `eiWelaTargetPossible` of the validate group. Health splash shares `eiWelaDamage × eiWelaSplashfactor` (default
  10000) with at most `eiWelaDamage` per unit, round by round from the unit needing least (health; heal: missing
  health, full units skipped unless dtOverheal); what is left is spread over all, capped per unit. Types get
  dtSplash. Teleport: to the team's nexus (else the farthest one), a fixed spot, or the owner to its target; unless
  imprinted it offsets from an entity destination, exiles and re-keys the unit (`eiReplaceEntity [ID, new, True]`:
  the entity manager changes its `ID`); AsProjectile hands the unit to a projectile carrying an imprinted teleport
  warhead in [0] (commander = the owner's ID, quirk kept).
- **Links** (server, `tests/test_links.gd`, incl. a real SmallCasterGolem giving an ally Crystal Power and a real
  GatlingTurret firing until its ammo is gone): a link is an entity. `TWelaLinkEffectComponent` fires
  `eiLinkEstablish [owner, target]` (epFirst: an already linked target stops the event; over `eiWelaTargetCount` the
  oldest link breaks first) and spawns `eiLinkPattern` at (0, 0) with upLink, `eiLinkSource` / `eiLinkDest` (ATargets),
  `eiCreatorGroup` and a `TLinkEventRedirecter` (empty `eiCooldown` / `eiWelaDamage` / `eiDamageType` reads come from
  the source in the link effect's group; damage done and kills go to the source). `eiLinkBreak [RTarget]` kills the
  link entity; death, exile, the global eiLose and freeing break all. The links are a `DelphiDictionary`
  (`src/runtime/engine/`, Delphi's TDictionary: linear probing, 75% grow threshold, backward-shift delete; keys hash
  with `RTarget.Hash`): breaking all walks it live, so a link shifted back into a visited slot is skipped and **stays
  up** (quirk kept; use the class wherever the original walks or edits a TDictionary). `TLinkBrainComponent` fires
  every cooldown on the global eiIdle (TimesExpired, max 50). `TWelaEffectLinkPayCostMyselfComponentServer`: 1 cost at
  once, then per whole second on its group's eiThinkChain; emptying fires FireOnEmpty's group. Continuous effects hook
  the ends with remote subscriptions at eiAfterCreate (damage redirection at epHigher, before armor). Numbers from the
  turret test: linked at 1500 (LinkTime 500), a volley (3 splash + 15) every 500 ms from 2000, mana 19 → 0 at 20500,
  38 volleys, then the link breaks.
- **Combat modifiers** (server, `tests/test_combat_modifiers.gd`, incl. real Blind.dws on a golem, the VoidSkeleton's
  bonus damage, Bleeding.dws and the ObserverDrone): `TWelaReadyNthComponent` (every readiness check counts),
  `TWelaReadyEntityNearbyComponent` (asks the targeting group's eiWelaUpdateTargets), `TModifierMultiplyDealtDamageComponent`
  (eiWillDealDamage epMiddle, chains through Previous), `TModifierBlindedComponent` (a fire to the value group rolls,
  random <= 0.5 misses: stops eiFireWarhead, marks projectiles upProjectileWillMiss), `TBuffTakenDamageMultiplierComponent`
  (eiTakeDamage epLow = after armor; Flat, Dodge, Reflect, ApplyOnHeal on eiHeal epLower). Delphi's `random` is
  Godot's RNG; tests seed it and replay the rolls.
- **Game end, waves, statistics** (`tests/test_statistics.gd`; the unit statistics in the real golem kill of
  `test_warheads.gd` and the real spawn of `test_spawning.gd`): a nexus' `TPrimaryTargetComponent` answers the global
  `eiEnumerateNexus` (`EntityManager.NexusList`); `TServerPrimaryTargetComponent` turns its death into the global
  `eiLose [TeamID]` and stops the eiDie chain (false). `TSuicideOnGameEndComponent` (client links) frees its owner on
  eiLose. The scenario game entity pays incomes (`TWelaEffectIncomePayoutComponent`, every `Game.Commanders`' eiIncome
  as gold and wood transactions) and spawns waves (`TWelaEffectWaveSpawnComponent`: one field per build zone per
  fire from a cycle of the 20 non-corner fields, random or the fixed tutorial order; at global eiWaveSpawn epFirst it
  stops every wave spawn of a field outside the cycle, so a spawner placed mid-cycle waits). The zones walk in
  `DelphiDictionary` order with an identity integer hash (Delphi 10.1's, unverified; ascending for IDs 0-3).
  Statistics go to `Game.Statistics` (`TGameStatisticManager`, now with `CardPlayed`; card type and colors from the
  file name: `BC.ScriptFilenameToCard{Type,Colors}`, first matching folder wins). Server games (and test fakes that
  build real server units) must carry `Statistics` and `Commanders`; without a game the statistics are skipped.
- **Commander and cards** (`tests/test_commander.gd`): the card database is `TCardInfoManager.Instance()`, filled
  from `src/content/cards.json` (`python tools/convert_cards.py` turns the original's AddCard / AddSkin list into it,
  checked by the test runner). A card info is one (UID, league, level), cached per triple; skins are clones with
  their own UID, `BaseUID` of the base card, and make the base card the `default` skin (so its file + empty skin
  finds nothing in `ScriptFilenameToCardInfo`). The mapping is a `DelphiDictionary` with `DelphiHash.StringHash`
  (Bob Jenkins' lookup3 over the UTF-16 units, the Delphi 10.x string comparer; checked against lookup3's published
  values, the RTL choice is unverified: the `.dproj` files say ProjectVersion 18.5 and Delphi 11+ hashes with
  FNV-1a), so `GetAllCardUIDs` (the bots' card walk) follows the original's slot order. `TCardInfo`'s stats read the
  entity data cache and take it as a parameter (the cache is per side in the port); the translated texts (Name,
  descriptions, skills, keywords) come with the localization. `TCommanderAbilityComponent` (server: in the
  constructor; client: at eiAfterCreate, then it frees itself) applies the card's script: `Commander\CommanderMethods`
  AddDrop / AddBuilding / AddSpawner, or the spell file's AddSpell. Every card script adds a `TCommanderAbility` in
  the card's group: it answers `eiEnumerateCommanderAbilities` (an Array, deck order), and `CanUseAbility` /
  `UseAbility` read / trigger eiCanUseAbility / eiUseAbility in the card's group or the chosen mode's (IsMultiMode:
  one group per mode; `ModeCount` keeps the original's `Min(1, modes)`). Charges are the commander's reCharge in the
  card's group. The client's `TCommanderComponent` adds its commander to the global `eiEnumerateCommanders` (epFirst).
  `DelphiRtl` has SysUtils' file-name functions with Windows delimiters and `CompareText` / `SameText` (ASCII only).
- **Directors** (`GameServer/BaseConflict.EntityComponents.Server.pas`, server only; `tests/test_directors.gd`):
  `TScenarioDirectorComponent` is the PvE director (`Game.ScenarioDirector`, made by `Scenarios\Attack*Base`). Its
  unit pool is every card of the faction at the director's league (default `Game.League`), no spawners, no 'Golems'
  files, units only, typed by `SCENARIO_UNIT_INFO_MAPPING` (`...Constants.Scenario.Server.pas`), costs and squad
  size normalized to league 4 level 1 (gold of the drop, wood of the spawner card with the same identifier). Timed
  actions queue in `FActions`; at every global eiGameTick those with tick <= `eiGameTickCounter` run **from the last
  queued to the first**, then every KI player thinks: income, a drop of units costing exactly `NextGoldSave` (300
  after the first think, and no golem costs 300, so the KI never drops: waves come from boss waves) and the next
  random spawner once the wood suffices (fields skip the corners 0, 7, 16). Random picks shuffle the list first with
  Delphi's `TUltimateList.Shuffle` (`Exchange(i, Random(i))`: the last item always moves, so a two-unit subset
  alternates whatever the RNG). `SpawnUnits` builds squad rows behind the point (fodder, tank/melee, ranged, siege;
  3 apart, centred; a row wraps after 7 but keeps its y offset growing). Guards spawn with overwatch and flee 30;
  mirroring repeats spawns at -y. Where the original raised, the port logs and skips.
  `TServerSandboxComponent` (infinite gold / wood, tech 2 + 3), `TSandboxComponent` (`Game.GameDirector.ClearEvents`)
  and `TServerSandboxCommandComponent` (the `BC.cc*` client commands: clear units / spawners / towers, base building
  levels, indestructible bases, overwatch switches on `Game.Overwatch` / `OverwatchClearable`, forced tick) read
  `Game.GameInformation.Scenario.MapName` / `.ScenarioUID`. `TTutorialDirectorServerComponent` handles the tutorial's
  game events: freeze (think blocks + eiStand, also on new entities; eiGameTick stopped), wave spawn / income
  switches, card costs (`TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES`), give / set gold and wood
  (`DelphiRtl.StrToIntDef`, default 100), refill charges, skip warming.
- `TNexusEarlyVulnerabilityComponent` (`:88`) is not ported: only declared and exposed, nothing creates it
  (listed in `docs/unused-features.md`, with the unused axis and exclude zones).
- **Time**: `TTimer` reads `TTimeManager.GetFloatingTimestamp()` (ms). Tests freeze it with
  `TTimeManager.FakeTime`. The global pause and `TickTack` come with the game loop (phase 3). `TTimer` keeps the
  original's quirks: `StartWithRest` behaves like the code, not its comment, and the `Paused` setter is inverted.

- **Damage pipeline** (`eiTakeDamage`, read `[Amount, DamageType, InflictorID]`): `TArmorComponent` (epMiddle)
  rewrites Amount (`Max(1, Factor * Amount - Offset)`, only for Amount > 1 and without `dtIgnoreArmor`), then
  `THealthComponent.OnDamage` (epLower, server) takes overheal first, then health, and returns the damage dealt.
- **Death chain** (server): health < 1 → `eiKill` → `OnKill` (resolves a projectile killer to its creator) →
  `eiDie` → `OnDie`: killer gets `eiYouHaveKilledMeShameOnYou`, `eiIsAlive := False` (health 0), `eiInstaDie` if
  the unit was at full health when last hit/healed, `eiDelayedKillEntity` on the global bus. Also on `eiIdle`.

- **Resources**: balance / cap / cost are blackboard values of `eiResourceBalance` / `eiResourceCap` /
  `eiResourceCost` indexed by `EnumResource`, under the group the event was called to (`CurrentEvent_CalledToGroup`).
  `RES_INT_RESOURCES` (`BC.IsIntResource`) are integers, the rest singles; `BC.IgnoresCap` = `RES_IGNORE_CAP`.
  Note `Write(eiResourceBalance, [Res, Amount])` also stores `Res` as the plain value (Values[0]), as in the original.
- `AResourceCost` is an Array of `RResourceCost`; `OnGetResourceCost` sorts it by resource (the original used
  TDictionary hash order; callers only look entries up).
- 32-bit integer overflow is not emulated (balances never get near it).

## Client visuals (`BaseConflict.EntityComponents.Client*.pas`; `tests/test_client_visuals.gd`)

- **`TVisualizerComponent`** (+ `RMatrixAdjustments`): on the global `eiIdle` (epLower) `Update` reads `eiSize`
  (ungrouped times grouped) and `Apply` builds the bind matrix: a bound zone (`eiSubPositionByString` to the bind
  group), else the entity's `DisplayPosition` / `DisplayFront` / `DisplayUp` (pieces read them hierarchically,
  fixed orientations replace them), then the adjustments, the rotation offset, the model offset
  (`Offset * ModelSize * Size + FixedOffset`) and a fixed height. `FinalSize` = scale event (or collision radius)
  clamped, times the resource scale, times model size and size (not for range / area scale events). `eiModelSize` is
  read at creation and written later (etWrite epLast). Static visualizers (environment meshes) apply once.
  Matrices are game-space Transform3Ds (`RMatrix` helpers: Column[0..2] = Left, Up, Front, Column[3] =
  Translation). `IsVisible`: `eiVisible` (hierarchic, default true), not exiled, wela ready, resource full, client
  option (`TOptionManager`: only the options in use, with the original's defaults), unit properties.
- **`TMeshComponent`**: a `TMesh` in `GFXD.MainScene` (the owner of the view sets it; none in headless tests) at the
  bind matrix with `FinalSize * SizeNormalization` (`ApplyLegacySizeFactor` = 2 / 125, `ApplyAutoSizeNormalization`),
  `ShadingReductionOverride` = `coEngineGlobalShadingReduction`; `CreateNewAnimation` cuts the take on both drivers
  and makes `stand` the default; `eiPlayAnimation` plays with the original's length rules (walk scaled by speed and
  size, random walk offset, following default animations, attack loop); conditional textures (team with
  `GetDisplayedTeam`, unit property, resource) are checked when dirty; `eiSubPositionByString` answers bones (after
  `BindZoneToBone` and the bone adjustments) or head / top / ground / pivot / bottom / center; `eiBoundings` the
  sphere. Not yet: mesh effects (`TMeshEffect*` stay stubs, the effect stack is empty), the death decay manager,
  the outline pass.
- **`TAnimationComponent`**: spawn on eiAfterCreate, attack / attack2 / air / ability on eiPreFire or eiFire (by the
  wela's action point), links, stand, walk (eiMoveTo) as `eiPlayAnimation` to its group.
- **`TLogicToWorldComponent`**: the client adds it to every entity from the server; logic position / front become
  the display ones on the ground (epFirst reads), refreshed on the global eiIdle (epHigh) and on eiAfterCreate.
- **Serialisation** (the network stand-in): `TEntity.Serialize(TEntityStream)` writes ID, script, skin, UID and
  `TBlackboard.SaveToStream` (count, then event / group slot / index slot / value in event order);
  `TEntity.Deserialize` creates the entity from its script with the server's blackboard loaded in the initializer,
  then loads it again over the script's values (blackboard events go through `Write`, position / front through the
  setters). eiSerialize then lets every `TSerializableEntityComponent` write its class, UniqueID, group and its
  `NetworkFields()` (the public and protected fields); `Deserialize` creates those components on the client copy and
  writes their `NetworkSerializeEvents()` (`TMovementComponent.FTarget` -> eiMoveTo). Sent by
  `TServerNetworkComponent`, received by `TClientNetworkComponent.DeserializeEntity` (+ TLogicToWorldComponent,
  eiAfterCreate, Deploy): `docs/game-loop.md`, "Network". A new serializable class lists its public / protected
  fields in `NetworkFields()` (declaration order).

## Not ported yet

- `TEntity.OwningCommander`, the per-game pausable clock (`GameTimeManager`; `TGameTimer` uses `TTimeManager`
  meanwhile, the server swaps its own frame state in), the rest of `TTimeManager` (pause).
