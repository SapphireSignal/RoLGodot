# RoLGodot

A 1:1 Godot 4.7 port of **Rise of Legions**: its last version before the Crystal Clash rebrand.
The global rules in `C:\Users\srrwz\.claude\CLAUDE.md` always apply.

## Project rules
- Source of truth: `reference/rise-of-legions` at commit `96d5b8e4` (see `docs/source-of-truth.md`).
  Never use Crystal Clash content, the live game, or anything outside that snapshot for decisions.
- Stay inside `D:\Games\RoLGodot`. Never touch the owner's other repos.
- Lean repo and build: `reference/` is git-ignored, `.gdignore`d and excluded from export, like `tools/`,
  `tests/`, `docs/`. Get it with `tools/fetch_reference.ps1`.
- Original data uses German decimal commas and mismatched file-name case: parse/compare accordingly.
- Git identity: SapphireSignal <SapphireSignal@users.noreply.github.com>.
- Subagent roles and their cost: `docs/team.md`.

## Tools
- Godot: `D:\Godot\Godot_v4.7.1-stable_win64.exe` (console build `..._console.exe` for headless runs)
- Delphi: `C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\`
- Tests: `powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1` (import + compile sweep + tests,
  hard timeout, logs in `logs/`). Test files: `tests/test_*.gd` extending `res://tests/test_case.gd`.

## Docs
- `docs/original-architecture.md`: how the original is built, file formats, gotchas.
- `docs/port-plan.md`: phases 0-9. `docs/gap-list.md`: user-visible behaviours and their status.
- `docs/unused-features.md`: things the original can do but never uses (whole classes: `tools/find_unused_classes.py`);
  add every unused option found while porting.
- `docs/scripts.md`: how the original runs scripts, the construct survey, the transpiler and its output.
- `docs/script-api.md` (generated): every class member the scripts use, per class. Phase 2 work list.
- `docs/entity-core.md`: TEntity/eventbus/blackboard semantics and the conventions for porting components.
- `docs/map.md`: map data (zones), build zones, lanes, pathfinding, the priority-queue tie rule.

## Status
- 2026-09-18: Phase 0 (foundation) done: source pinned, reference cloned, architecture researched, Godot
  scaffold + test runner + `play.bat` + export preset. Next: phase 1, the DWScript → GDScript transpiler.
- 2026-09-18: Phase 1 steps 1-2 done: script engine read, lexer + preprocessor (`tools/dws/`), survey
  (`tools/survey_scripts.py`, all 509 scripts preprocess for CLIENT and SERVER), `docs/scripts.md`.
  Next: parser + GDScript emitter (step 3).
- 2026-09-18: Phase 1 done: `python tools/transpile_scripts.py` turns all 500 scripts × 2 sides into
  `src/content/scripts/`, plus `dws_const.gd`, class stubs and `docs/script-api.md` (phase 2 work list).
  1277 files compile, tests green. Next: phase 2, entity core (see CONTINUE.md).
- 2026-09-18: Phase 2 step 1 done: `src/runtime/entity/` (TEntity, TEntityComponent, TEventbus, TBlackboard,
  RParam, sets), `docs/entity-core.md`, 14 entity tests; stubs now carry their Delphi constructors.
  1285 files compile, 21 tests green, no leaks. Next: step 2, the script runner (see CONTINUE.md).
- 2026-09-18: Phase 2 step 2 done: script runner in `TEntity` (`CreateFromScript*` with InheritsFrom /
  InheritsFromPreceding, `ApplyScript*`, per-side resolution); real unit/projectile scripts build entities on
  both sides. 28 tests green, no errors. Next: step 3, `TResourceManagerComponent` (see CONTINUE.md).
- 2026-09-18: Phase 2 step 3 done: `TResourceManagerComponent` on every entity (balance/cap/cost, transactions,
  reset), `RResourceCost`; card league/level now reach the scripts; scripts' `Game()` follows the running
  script's side. 1289 files compile, 39 tests green, no errors. Next: step 4, entity-local shared components.
- 2026-09-18: Phase 2 step 4 done: `TUnitPropertyComponent`, `TArmorComponent`, `THealthComponent` (+ thin
  `TSerializableEntityComponent`); server-only handlers per side; stubs now no-op the methods scripts call, so
  a real server unit (SmallMeleeGolem) builds and takes armored damage cleanly. 1293 files compile, 58 tests
  green, no errors. Next: step 5, the rest by `docs/script-api.md` (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 part 1: `TCommanderIncome{,Default,Loan,Overflow}Component`, `RIncome`, `TTimer` +
  `TTimeManager` clock; the real server CommanderTemplate computes its income. 1298 files compile, 70 tests
  green, no errors. Next: `TDynamicZone*Emitter` (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 part 2: `TDynamicZone{,Radial,Axis}EmitterComponent`, `TGameEventEnumeratorComponent`.
  1300 files compile, 75 tests green, no errors. Next: `TEntityManagerComponent` (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 part 3: `TEntityManagerComponent` (registry, deferred freeing, nexus queries).
  1302 files compile, 84 tests green, no errors. Next: `TModifier*Component` (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 parts 4-6: `TModifier*` (9), `TWelaReady*` (8) + `TGameTimer`, `RTarget`/`ATarget`/
  `RTargetValidity` + `TWelaTargetConstraint*` (18) + `TWelaTriggerCheck*` (3); unused-class finder fixed (43).
  1309 files compile, 124 tests green, no errors. Next: `TWelaHelperResolve`, warhead apply-script (CONTINUE.md).
- 2026-09-18: Phase 2 step 5 parts 7-8: `TWelaHelperResolveComponent`, `TWarhead{,Link}ApplyScriptComponent`;
  `TEntityDataCache` (on the global bus) + `TWelaEventRedirecter` + `TWelaReadySpawnedComponent`. 1312 files
  compile, 137 tests green, no errors. Next: the map's build zones (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 parts 9-10: the map (`TMap` from converted `.bcm` JSON, build zones, lanes, zone
  polygons, `TWelaTargetConstraint{Grid,BuildTeam,Zone}`) and the pathfinding (A* with time-slot reservations,
  `TPriorityQueue`, `TRingBuffer`); `docs/map.md`. 1331 files compile, 154 tests green, no errors. Next:
  `TPositionComponent` / `TMovementComponent` (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 part 11: movement (`TPositionComponent`, `TMovementComponent` direct + pathfinding
  walk, client path straightening, `TPathfindingComponent` tile blocking; `TTimeManager.ZDiff`); the real Footman
  walks its path. 1332 files compile, 164 tests green, no errors. Next: pick the next family (see CONTINUE.md).
