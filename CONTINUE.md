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
Phases 0 and 1 done, phase 2 step 1 done (see `docs/port-plan.md`). Verified facts about the original are in
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

Next:
2. The script runner in `TEntity` (`BaseConflict.Entity.pas:587-692`): `CreateFromScriptProc` with
   `InheritsFrom` / `InheritsFromPreceding`, `CreateFromScript` / `CreateMetaFromScript` / `CreateDataFromScript`,
   `ApplyScript`, `ApplyScriptReturnGroups`. Scripts are resolved through `script_index.gd` (lower-case original
   path, per side = `IsServer()`); set the script's `GlobalEventbus` / `Game` vars if declared; fail like the
   original on `ORIGINAL_COMPILE_ERROR` files. Test: create a real unit script (e.g. `Units\...Footman`) on both
   sides and check the blackboard values it sets against the script source.
3. `TResourceManagerComponent` (`BaseConflict.EntityComponents.Shared.pas:386`) at
   `src/runtime/components/t_resource_manager_component.gd` (TEntity.Create picks it up by that path).
4. Then the other shared components by `docs/script-api.md`.
When a hand-written file declares `class_name TFoo`, rerun the transpiler: it drops the stub.
