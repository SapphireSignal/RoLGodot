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
Phases 0 and 1 done, phase 2 steps 1-2 done (see `docs/port-plan.md`). Verified facts about the original are in
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

Next:
3. `TResourceManagerComponent` (`BaseConflict.EntityComponents.Shared.pas:386`) at
   `src/runtime/components/t_resource_manager_component.gd` (TEntity.Create picks it up by that path).
   Until it exists, `CardLeague()`/`CardLevel()` read the plain blackboard slot (0), so scripts using
   `L.i/L.f(..., Entity.CardLeague())` index `arr[-1]`. Once ported, add a runner test with the real card
   initializer (`BaseConflict.Classes.Shared.pas:510`, sets reCardLevel/reCardLeague) on e.g.
   `Units\Neutral\NexusLevel1` (InheritsFrom + `Game` global; needs a fake game with IsDuo/IsPvP/IsOneLane
   and `L.game_resolver`) and `Units\Black\VoidSkeletonDrop` on the client.
4. Then the other shared components by `docs/script-api.md`.
When a hand-written file declares `class_name TFoo`, rerun the transpiler: it drops the stub.
