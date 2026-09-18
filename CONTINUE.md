# CONTINUE

Hand-off note for the next session. Read `CLAUDE.md` first, then this.

## The owner's brief (session 1, 2026-09-18)
- Port **Rise of Legions** to **Godot** as a strict 1:1 replica of its **last update before it became
  Crystal Clash**. Every detail the same: units, cards, numbers, effects, sounds, UI, little touches.
- The original devs gave the owner permission to use and do anything with the game and its source.
- Build it in parts like a professional team, with care. Claude is the returning lead dev.
- Lean repo, lean Windows build. `play.bat` to launch. Professional GitHub repo (don't claim to be a team).
- Playful dev-team roster (`docs/team.md`): hired only when needed; agents cost the owner's usage.
- Never read or write the owner's other repos.

## Where we are
Phases 0 and 1 done, phase 2 steps 1-4 done, step 5 under way (see `docs/port-plan.md`). Verified facts about the original are in
`docs/original-architecture.md`. If `reference/` is missing, run `tools\fetch_reference.ps1` (~800 MB download,
~3 GB checked out; run it in the background).

Phase 1: `docs/scripts.md` explains the pipeline and the output. `python tools/transpile_scripts.py` regenerates
`src/content/scripts/{client,server}/` (committed), `src/runtime/dws/dws_const.gd`, the class stubs in
`src/runtime/dws/stubs/` and `docs/script-api.md`. `tools/run_tests.ps1` runs the transpiler unit tests, checks
the generated files are up to date (when `reference/` exists) and runs the Godot compile sweep + tests.

## Phase 2, the entity core
Step 1 done: `src/runtime/entity/` ports `BaseConflict.Entity.pas` minus the script runner and serialisation.
Read `docs/entity-core.md` first: original semantics + port conventions (constructors, `_DeclareEvents` for
XEvent handlers, `SetVarParam`, RParam memory casts, sets as sorted Arrays, per-bus side and Game).

Step 2 done: the script runner in `TEntity` (section "Script runner" in `docs/entity-core.md`,
`tests/test_script_runner.gd`).

Step 3 done: `TResourceManagerComponent` in `src/runtime/components/` (section "Shared components" in
`docs/entity-core.md`, `tests/test_resource_manager.gd`, incl. real card league/level runs of
`Units\Neutral\NexusLevel1` and client `Units\Black\VoidSkeletonDrop` with a fake `Game`). The scripts' `Game()`
now resolves to the running script's bus (`TEntity.ScriptGame`).

Step 4 done: `TUnitPropertyComponent`, `TArmorComponent`, `THealthComponent` (thin
`TSerializableEntityComponent` base in `src/runtime/entity/`). New conventions in `docs/entity-core.md`: `out`
parameters return the value or null, `{$IFDEF SERVER}` handlers go under `if IsServerSide():` in `_DeclareEvents`,
components reach `Game` as `GlobalEventbus().Game`. `tests/component_fakes.gd`: event probe + fake
`Game.EntityManager`. Stubs now carry no-op versions of the methods the scripts call, so real unit scripts run
without errors (`tests/test_health_component.gd` builds the server SmallMeleeGolem).

Step 5 in progress (the rest by `docs/script-api.md`, entity-local first). Done: `TCommanderIncome*` + `RIncome`,
and `TTimer`/`TTimeManager` clock in `src/runtime/engine/` (tests freeze time with `TTimeManager.FakeTime`);
`TDynamicZone*Emitter`, `TGameEventEnumeratorComponent` (`TNexusEarlyVulnerabilityComponent` is unused: skipped).
`TEntityManagerComponent` (the real `Game.EntityManager`; `TServerEntityManagerComponent` /
`TClientEntityManagerComponent` extend it later, with the game).
Next: the entity-local modifier components `TModifier*Component` (`BaseConflict.EntityComponents.Shared.Wela.pas:32-207`,
see `docs/script-api.md`), then the `TWelaReady*` / `TWelaTargetConstraint*` families. `TPositionComponent`/
`TMovementComponent` need the map and pathfinding, so check first what they pull in.
When a hand-written file declares `class_name TFoo`, rerun the transpiler: it drops the stub.
