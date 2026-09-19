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
- Every class exposed to Godot keeps the API the rest of the game calls, so the tests stay the spec.

## Moving the game over

Bottom-up, so C++ calls C++ (every GDScript <-> C++ call costs ~0.2 us at the boundary; the gain comes when whole paths
are native):

1. Leaf helpers: `DSet` (done), `RParam`, the Delphi RTL helpers, `TTimer` / `TTimeManager`, math, containers.
2. The entity core: `TBlackboard`, `TEventbus`, `TEntity`, `TEntityComponent` (and the per-thread context).
3. The component families, hottest first by `--profile`: server brains / think timers, movement, collision and
   targeting, welas and warheads, then the client visuals (mesh, animation, logic-to-world).
4. The game loop, network, map and graphics classes.
5. The transpiler emits C++ for the 500 game scripts.
6. Viewers, HUD and tests in C++; the last `.gd` file goes.

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
