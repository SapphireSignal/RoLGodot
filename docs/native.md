# The C++ game code

Rise of Legions runs natively in the original (Delphi). The port's game code is C++ too: a GDExtension library
(`native/`, built into `bin/rol_native.*.dll`) that Godot loads through `rol_native.gdextension`. Godot provides
rendering, input, windows, audio and the scene tree; the game (entities, event bus, components, game loop, network,
graphics classes, the transpiled scripts) is C++.

## Build

- `tools/fetch_godot_cpp.ps1`: godot-cpp (the official bindings) at a pinned commit into `native/godot-cpp/`, and the
  extension API of the project's Godot build into `native/extension_api.json` (both git-ignored). godot-cpp is built
  against that dump, so the bindings match Godot 4.7.1 exactly.
- `tools/build_native.ps1` (`-Release` adds the export library): SCons with the Visual Studio C++ tools, incremental.
  The test runner and `play.bat` call it first; a failed build stops them. First build: a few minutes (godot-cpp).
- Needs: Visual Studio 2022 with the C++ tools, Python with SCons (`pip install --user scons`), git.
- Debug library (`template_debug`, `optimize=speed`): what `play.bat` and the tests load. Release library: exports.

## Layout and conventions

- `native/src/<area>/<snake_name>.h/.cpp`, the areas as in the original's units (`entity/`, `engine/`, `components/`,
  `game/`, `graphics/`, `map/`, `network/`, ...). `register_types.cpp` registers every class.
- Class and method names are the original's (`TEventbus`, `Read`, `Trigger`), so the code reads side by side with the
  Delphi source; comments cite the original (`BaseConflict.Entity.pas:512`), never earlier versions of the port.
- Semantics are the original's: Delphi `single` arithmetic stays 32-bit float (no fast-math), sets stay sorted, event
  order, `TDictionary` walk order (`DelphiDictionary`), `TList.Sort` (`DelphiSort`), Delphi's RNG (`DelphiRandom`).
- The original's `threadvar`s are C++ `thread_local`s (the game server runs on its own thread, like `TGameThread`).
- Every class exposed to Godot keeps the API the rest of the game calls, so the tests stay the spec. What a GDExtension
  class cannot offer, and what replaces it: static variables (`TTimeManager.SetFakeTime` / `GetFakeTime`,
  `DelphiRandom.SetRandSeed` / `GetRandSeed`), constructor arguments (`TRingBuffer.new().Create(50, false)`, the
  original's style anyway), non-integer constants. Methods that return the object itself (`Create`) return `Ref<T>`
  (`Ref<T>(this)`), never a raw pointer.
- GDScript's number semantics are kept where the tests pin them: GDScript `float` is a double and `Vector2` holds floats,
  so a port computes scalars in `double` and converts to `real_t` where GDScript did (`Vector2 * float`).
- Classes the transpiled scripts see: the transpiler reads `GDCLASS(Name, Base)` in `native/src/` like a `class_name`,
  so it writes no stub for them.
- The game's enum values and constants (`dws_const.gd`) are generated for C++ too: `native/src/dws/dws_const.h`
  (`C::eiFree`, ...), by `tools/transpile_scripts.py`.
- Real C++ inside: a moved class uses C++ types for its own state (bit masks for sets, `std::vector`, typed pointers,
  `thread_local`s), not `Variant` / `Array` copied over from GDScript; `Variant` and `Array` only where Godot or
  GDScript code hands values in or out.

### GDScript subclasses of C++ classes

GDScript cannot override a method a C++ class binds: typed calls (`TFoo.new().CreateGrouped(...)`, a variable of the
class's type) and plain self calls go straight to the C++ method, only untyped calls reach the script (measured
2026-09-19; the analyzer's `native_method_override` warning is an error, so the compile sweep refuses such an
override). A C++ class GDScript still subclasses therefore binds none of the methods the subclasses override; a thin
GDScript layer holds those and calls the C++ bodies under their own names, and C++ calls the overrides through the
script (`object_call_script_method`). `TEntityComponent` is the case today: GDScript components extend
`TGDEntityComponent` (`CreateGrouped` -> `_CreateGrouped`, `Destroy` -> `_Destroy`; C++ calls `_DeclareEvents`,
`ClassName`), and the transpiler's stubs extend it too (`GD_BASES` in `tools/transpile_scripts.py`). The layer goes
when the last GDScript component has moved. A family moves with all its subclasses, so no other C++ class needs a
layer.

## Moving the game over

Bottom-up, so C++ calls C++ (every GDScript <-> C++ call costs ~0.2 us at the boundary; the gain comes when whole paths
are native):

1. Leaf helpers (done): `DSet`, `RParam`, the Delphi RTL helpers, `TTimer` / `TTimeManager`, math, containers. Left
   in GDScript on purpose, they move with their families: the loose quadtree (collision: the entity variant subclasses
   it), `TCommandSequence` / `TLoopbackSocket` (network), `TGUITransitionValueSingle` (GUI).
2. The entity core (done): `TBlackboard`, `TEventbus`, `TEntity`, `TEntityComponent`, `TRemoteSubscription`,
   `TEntityStream` and the per-thread context `TThreadContext` (with its `GameTimeManager`).
3. The component families, hottest first by `--profile`: server brains / think timers, movement, collision and
   targeting, welas and warheads, then the client visuals (mesh, animation, logic-to-world).
4. The game loop, network, map and graphics classes.
5. The transpiler emits C++ for the 500 game scripts.
6. Viewers, HUD and tests in C++; the last `.gd` file goes.

Big steps: a whole family (or two) per session, with all its subclasses, so little glue is needed in between.
Rules for every step: the replaced GDScript file is deleted in the same change (never two versions of a class); the
full test suite passes unchanged (it is the spec); `--fps-check` on all three setups before and after, the numbers in
"Performance" below. At the end: the C++ moves to the conventional layout, and the finished project is published with
a fresh history (asked for by the owner; confirm with the owner right before rewriting the published repository).

## Performance

Measured with `tests/bench_eventbus.gd` (per call) and the map viewer's `--fps-check` (see `docs/game-loop.md`).

| | GDScript | C++ |
| --- | --- | --- |
| `DSet.Make([])` | 0.59 us | 0.23 us (the rest is the GDScript -> C++ call) |
| `RParam.AsBoolean(null)` | 0.25 us | 0.10 us |
| `bus.Read` without handlers (bus still GDScript) | 2.34 us | 2.07 us |

Done so far: `DSet`, `RParam` (2026-09-19). `RPARAMEMPTY` is plain `null` in GDScript (a GDExtension class exposes
integer constants only).

2026-09-19, the rest of the leaf helpers: `native/src/engine/` (`DelphiRandom`, `DelphiHash`, `DelphiSort` (also a
template, `QuickSortT`, for C++ callers), `DelphiRtl`, `DelphiDictionary`, `delphi_math.h` (Round, Frac, SameValue,
CompareValue), `TTimeManager`, `TTimer`, `TGameTimer`, `TPriorityQueue`, `TIntPriorityQueue`, `TRingBuffer`,
`T2DGrid`) and `native/src/math/` (`RMatrix`, `RLine2D`, `RRay2D`, `RCubicBezier`, `TPolygon`, `TMultipolygon`).
Captures of every map viewer view before and after: the same picture (differences at the run-to-run noise of water
and vegetation animation). Map viewer `--fps-check`, window 1600 x 900, before -> after:

| | fps dragging | median / p99 / worst ms | client step ms/frame |
| --- | --- | --- | --- |
| Single, empty | 227 -> 238 | 4.3 / 5.3 / 5.4 -> 4.1 / 5.5 / 6.0 | 2.40 -> 2.10 |
| Classic, empty | 171 -> 180 | 5.7 / 7.0 / 7.3 -> 5.4 / 7.0 / 7.3 | 3.21 -> 2.84 |
| PvE | 107 -> 108 | 9.2 / 11.2 / 11.6 -> 9.1 / 11.5 / 11.6 | 5.22 -> 4.80 |
| Classic, 2 spawners + 2 drops (42 entities) | 79 -> 86 | 12.4 / 17.4 / 19.3 -> 11.5 / 15.2 / 16.2 | 9.35 -> 8.48 |

Server thread per 32 ms frame: unchanged within noise (8.7 empty, 11.3-12 with 42 entities). The next gains need the
event bus in C++ (step 2).

2026-09-19, the entity core (`native/src/entity/`: `TEventbus`, `TBlackboard`, `TEntity` with the script runner,
`TEntityComponent`, `TRemoteSubscription`, `TEntityStream`; `native/src/engine/t_thread_context.*`). The components are
still GDScript: the bus calls their handlers straight through the script (no Callable, no lookup), groups are bit
masks. Same-session measurements, previous commit -> this one (captures of every view identical but for the water and
wind animation phase; objects leaked at exit 40 -> 23):

| `tests/bench_eventbus.gd` | before | after |
| --- | --- | --- |
| `bus.Read(eiExiled)` (no handler) | 2.41 us | 0.49 us |
| `bus.Read(eiExiled, [], [20])` | 2.24 us | 0.59 us |
| `bb.GetValue(eiExiled, [])` | 0.68 us | 0.22 us |
| `bus.Trigger(eiThink, [], [20])` (48 of 100 subscribers run) | 11.59 us | 3.12 us |
| `bus.Trigger(eiThink, [], [250])` (no match) | 4.19 us | 1.30 us |

| map viewer `--fps-check`, 1600 x 900 | fps dragging | median / p99 / worst ms | client ms/frame | server ms/frame |
| --- | --- | --- | --- | --- |
| Single, empty | 237 -> 398 | 4.1 / 5.3 / 5.7 -> 2.5 / 3.0 / 4.4 | 2.10 -> 0.59 | 8.4 -> 2.3 |
| Classic, empty | 172 -> 303 | 5.7 / 7.3 / 7.6 -> 3.3 / 3.9 / 4.3 | 2.91 -> 0.81 | 8.9 -> 2.3 |
| PvE | 100 -> 172 | 9.8 / 11.9 / 12.0 -> 5.7 / 6.9 / 7.5 | 5.03 -> 1.74 | 9.2 -> 2.8 |
| Classic, 2 spawners + 2 drops (42 entities) | 79 -> 136 | 12.4 / 16.4 / 17.5 -> 7.2 / 9.2 / 9.7 | 8.98 -> 4.21 | 11.2 -> 4.1 |

Loading a scenario: 4.4-8.5 s -> 2.3-6.3 s. Frames over 12 ms with 42 entities: 174 of 3 s -> 0.
