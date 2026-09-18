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
| `t_health_component.gd` | `THealthComponent` (`:173`): damage, heal, overheal, death chain; base `../entity/t_serializable_entity_component.gd` (thin until phase 3) |
| `t_commander_income*_component.gd` | `TCommanderIncome{,Default,Loan,Overflow}Component` (`:531-574`): the commander's `eiIncome` |
| `../types/r_income.gd` | `RIncome` (`BaseConflict.Types.Shared.pas:47`), a record: copies in and out of RParams |
| `t_dynamic_zone_*emitter_component.gd` | `TDynamicZone{,Radial,Axis}EmitterComponent` (`:581-614`): answer `eiInDynamicZone` |
| `t_game_event_enumerator_component.gd` | `TGameEventEnumeratorComponent` (`:630`): lists its owner for `eiGameEvent` |
| `t_entity_manager_component.gd` | `TEntityManagerComponent` (`:276`): `Game.EntityManager`, entity registry and deferred freeing |
| `../engine/t_timer.gd`, `t_time_manager.gd` | `TTimer` (whole) and the `TTimeManager` clock (`Engine.Helferlein.Windows.pas:985`) |

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
- **Entity manager** (`tests/test_entity_manager.gd`): `eiNewEntity` (sent by `TEntity.Deploy`) registers,
  `GenerateUniqueID` counts from 2. `eiKillEntity` unregisters at once and frees at the next `Idle` (called by the
  game loop); `eiRemoveComponent` / `eiRemoveComponentGroup` / `FreeEntity` are deferred to `Idle` too.
  `eiReplaceEntity` re-keys the entity and its pending kills and updates `Game.Map.BuildZones`;
  `eiSetGridFieldBlocking` needs `Game.Map` as well (both untested until the map exists). Quirk kept:
  `NexusNext` / `NexusNextEnemy` return the *farthest* nexus (`bestDistance < distance`). The registry is an
  insertion-ordered Dictionary (original: hash order). `InvokeEventOnEntity` waits for `InvokeWithRawData`.
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

## Not ported yet

- Serialisation (`TEntity.Serialize/Deserialize`, `TBlackboard.SaveToStream/LoadFromStream`,
  `TSerializableEntityComponent`, `TEventbus.InvokeWithRawData`, `TEntityManagerComponent.InvokeEventOnEntity`),
  `TEntity.OwningCommander`, the rest of
  `TTimeManager` (pause, `TickTack`; `CreatedTimestamp` uses the engine clock meanwhile): phase 3, with the game
  loop and client-server sync.
