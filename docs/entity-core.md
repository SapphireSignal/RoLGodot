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
- **Entity creation**: `TEntity.Create` adds a `TResourceManagerComponent` (ALLGROUP) to every entity.

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
- **Two sides in one process**: the original ran client and server as separate programs. Here each `TEventbus`
  has `ApplicationType` (`nsServer`/`nsClient`, replaces `APPLICATIONTYPE`) and `Game` (replaces the `Game`
  global); an entity takes both from its global bus (`TEntity.IsServer()` for `{$IFDEF SERVER}` code paths).

## Not ported yet

- `TEntity.CreateFromScript*`, `ApplyScript`, `ApplyScriptReturnGroups`: the script runner (next step).
- `TResourceManagerComponent`: `TEntity.Create` loads it from `TEntity.RESOURCE_MANAGER_PATH` once it exists.
- Serialisation (`TEntity.Serialize/Deserialize`, `TBlackboard.SaveToStream/LoadFromStream`,
  `TSerializableEntityComponent`, `TEventbus.InvokeWithRawData`), `TEntity.OwningCommander`, `TTimeManager`
  (`CreatedTimestamp` uses the engine clock meanwhile): phase 3, with the game loop and client-server sync.
