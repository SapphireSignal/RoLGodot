# RoLGodot

A 1:1 Godot 4.7 port of **Rise of Legions**: its last version before the Crystal Clash rebrand.
The global rules in `C:\Users\srrwz\.claude\CLAUDE.md` always apply.

## Project rules
- Source of truth: `reference/rise-of-legions` at commit `96d5b8e4` (see `docs/source-of-truth.md`).
  Never use Crystal Clash content, the live game, or anything outside that snapshot for decisions.
- No bugs of the original are ported (global rule "Never port bugs"): port what the code was meant to do, even when it
  changes how units play, and list each fix in `docs/original-bugs.md` (original file:line, what it did, the fix).
  Layout: `BaseConflict.*.pas` at its root, engine units in `Engine/` (`Engine/Engine.Mesh.pas`), engine shaders
  in `Engine/Shader/`, effect shaders in `Graphics/Effects/Shader/`, scripts in `Scripts/`.
- Stay inside `D:\Games\RoLGodot`. Never touch the owner's other repos.
- Lean repo and build: `reference/` is git-ignored, `.gdignore`d and excluded from export, like `tools/`,
  `tests/`, `docs/`. Get it with `tools/fetch_reference.ps1`.
- Original data uses German decimal commas and mismatched file-name case: parse/compare accordingly.
- Git identity: SapphireSignal <SapphireSignal@users.noreply.github.com>.
- Subagent roles and their cost: `docs/team.md`.

## Tools
- Godot: `D:\Godot\Godot_v4.7.1-stable_win64.exe` (console build `..._console.exe` for headless runs)
- Delphi 13 Community: `C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\`. Builds only in the IDE, driven by
  `tools/original_build/` (read `docs/original-build.md` first: what crashes or closes the IDE).
- C++ game code (`native/`, read `docs/native.md`): Visual Studio 2022 C++ tools (MSVC 14.44), SCons (`pip install
  --user scons`), godot-cpp fetched by `tools/fetch_godot_cpp.ps1`; `tools/build_native.ps1` builds `bin/`
  (incremental; the test runner and `play.bat` call it first).
- Tests: `powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1` (import + compile sweep + tests,
  hard timeout, logs in `logs/`; any GDScript runtime `SCRIPT ERROR` in the log fails the run; then a windowed
  shader compile check (`tests/check_shaders.gd`: headless Godot never compiles shaders); last, two smoke tests start the game through
  `play.bat` and press the Mesh viewer / Map viewer button, checking a mesh / the Single map with its decorations and entities is drawn: windows flash up). Test files: `tests/test_*.gd` extending `res://tests/test_case.gd`.

## Docs
- `docs/original-architecture.md`: how the original is built, file formats, gotchas.
- `docs/original-build.md`: the reference build of the original (build, run, capture, crash addresses; the changes
  Delphi 13 needs; NaN compare semantics).
- `docs/port-plan.md`: phases 0-9. `docs/gap-list.md`: user-visible behaviours and their status.
- `docs/original-bugs.md`: every bug of the original the port fixes instead of copying (and what was checked and is
  not a bug).
- `docs/unused-features.md`: things the original can do but never uses (whole classes: `tools/find_unused_classes.py`);
  add every unused option found while porting.
- `docs/native.md`: the C++ game code: build, conventions, the order the game moves to C++, the measurements.
- `docs/scripts.md`: how the original runs scripts, the construct survey, the transpiler and its output.
- `docs/script-api.md` (generated): every class member the scripts use, per class. Phase 2 work list.
- `docs/entity-core.md`: TEntity/eventbus/blackboard semantics and the conventions for porting components.
- `docs/map.md`: map data (zones), build zones, lanes, pathfinding, the priority-queue tie rule.
- `docs/game-loop.md`: TGame / TServerGame / TGameThread, scenarios, game setup, ticks, what the headless match shows.
- `docs/assets.md`: the graphics import (`tools/import_graphics.py`, generated `assets/graphics/`), TMesh on the raw
  `.msh` (skinning, morphs, animation drivers), the mesh shader (gamma-space port of the original's lighting),
  TLightManager, the maps (terrain, water, vegetation, decorations), the mesh effects (shader block composition,
  own passes, the effect stack, the death decay), the post effects (viewport pipeline, glow stage, G-buffer camera and Toon, FXAA), the viewers.
- `docs/questions-for-devs.md`: what only the closed master server knew (meta values), asked of the original devs.

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
- 2026-09-18: Phase 2 step 5 part 12: collision (loose quadtree with per-team counts, `TCollisionManagerComponent`
  + server variant, `TCollisionComponent`, `TWelaReadyEnemiesNearbyComponent`); range queries answer in the
  original's tree order. 1342 files compile, 173 tests green, no errors. Next: targeting welas (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 part 13: targeting (`TWelaTargeting{,Radial,RadialAttention,Nexus,Self}Component`,
  `DelphiSort` = Delphi's TList.Sort) and `TWelaEfficiency*` (6). 1344 files compile, 183 tests green, no errors.
  Next: the wela effects `TWelaEffect*` (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 part 14: wela effects (18: `TWelaEffect*` without spawning/links, efficiency effect,
  beacon/activation helpers) and spotty warheads (9: damage, heal, kill, resource, remove-buff, wela-stop); a real
  golem now hits another. 1346 files compile, 221 tests green, no errors. Next: brains (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 part 15: the brains (every used class of `...Server.Brains.pas`: 8 think impulses /
  block, 21 brains, 20 auto-brains) + `TDelayedEventHandler`, `RCommanderAbilityTarget`; two real golems now fight
  to the death (both fall at the 8th exchange, 13033 ms). 1351 files compile, 232 tests green, no errors. Next: the
  spawning family (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 part 16: spawning (`TServerEntityManagerComponent`, `TGameStatisticManager`, factory /
  replace / projectile effects, `TProjectileEventRedirecter`, spawner and capture-point brains) and splash / teleport
  warheads; a real spawner spawns its squad, a dying golem's soul flies to a gatherer, a real tower splashes. The test
  runner now fails on runtime script errors. 1356 files compile, 261 tests green, no errors. Next: links (CONTINUE.md).
- 2026-09-18: Phase 2 step 5 parts 17-18: links (7 classes + `DelphiDictionary`, Delphi's TDictionary, and
  `RTarget.Hash`; a real caster golem's Crystal Power link, a real gatling turret firing until out of ammo) and the
  combat modifiers (blinded, dealt / taken damage multipliers, Nth / entity-nearby ready). 1361 files compile, 284
  tests green, no errors. Next: the small server rest from the stub list (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 part 19: game end, waves, statistics (primary target / nexus loss, suicide on game
  end, income payout, wave spawn rotation, unit / wela / card-play statistics, `CardPlayed`). 1362 files compile,
  298 tests green, no errors. Next: the commander and the directors (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 part 20: the commander and the card database (`TCardInfo`, `TCardInfoManager` from
  `src/content/cards.json` by `tools/convert_cards.py`, `TCommanderAbility{,Component}`, `TCommanderComponent`,
  `DelphiHash`, `DelphiRtl`); a commander gets its real drop / building / spawner / spell cards. 1369 files compile,
  310 tests green, no errors. Next: the scenario / tutorial / sandbox directors (see CONTINUE.md).
- 2026-09-18: Phase 2 step 5 part 21: the directors (`TScenarioDirectorComponent`, `TServerSandbox{,Command}Component`,
  `TSandboxComponent`, `TTutorialDirectorServerComponent`); the real AttackScenario Base + Easy scripts set up the PvE
  game and its first minute plays out (spawners, first boss wave). Every server / shared stub is now ported. 1370
  files compile, 323 tests green, no errors, no leaks. Next: phase 3, the game loop (see CONTINUE.md).
- 2026-09-18: Phase 3 game loop: `src/runtime/game/` (scenarios, game information, `TGame`, `TServerGame`,
  `TGameThread`, the sandbox setup) + tick / director / token mapping / surrender components; `docs/game-loop.md`.
  The headless sandbox match runs: Footman squads trade hits (10.4 / 2048 ms, hit at the 320 ms action point),
  spawners spawn, footmen damage the nexus. Game predicates are methods now (fakes updated). Test runner:
  `RUN_TESTS_ONLY` filter, default timeout 400 s. 1388 files compile, 334 tests green, no errors, no leaks.
  Next: profile the headless simulation (about real time only), then phase 4 (see CONTINUE.md).
- 2026-09-18: Phase 3 profiled: the event bus is 2.5x faster with the same behaviour (subscribers carry their
  handler, single-group events walk only their group, no event-stack arrays, network-send lookup); the sandbox
  match runs at 0.31 x real time (was 0.81). `tests/profile_sandbox.gd`, `tests/bench_eventbus.gd`. 1390 files
  compile, 334 tests green, no errors. Next: phase 4, the asset pipeline (see CONTINUE.md).
- 2026-09-18: Phase 4 part 1, meshes: `tools/import_graphics.py` (200 descriptors -> `assets/graphics/`, generated,
  git-ignored; raw FBX units, KTF `.tex` decoder, NaN-bone repair on import), `TMesh` + the mesh shader (gamma-space
  port of Standardshader + the deferred sun/ambient pass), `TLightManager` from the map's `.lig`, the mesh viewer
  (main scene button). All 200 meshes render and animate without errors. 340 tests green. Next: the map graphics
  (terrain, water, vegetation), see CONTINUE.md.
- 2026-09-18: Phase 4 part 2, map graphics: `tools/import_map_graphics.py` (.ter grid in the original's base64 +
  zlib, .wat, .veg, raw .msh), `TTerrain`, `TWaterSurface`/`TWaterManager`, `TVegetationManager` (rolls replayed with
  `DelphiRandom`, the Win32 RTL generator), `TEngineRawMesh`, `TClientMap`, three shaders, the map viewer (main scene
  button, capture mode, second launcher smoke test). Both maps render. `docs/questions-for-devs.md` lists what only the
  master server knew. 354 tests green, no errors. Next: see CONTINUE.md.
- 2026-09-18: Phase 4 part 3, the battlefield: meshes now load from the engine's raw `.msh` like release builds
  (`LOAD_RAW_MESH`; FBX import dropped: Godot misplaced skinned parts), skinning in the shader, morph blend shapes,
  `TAnimationController` + bone / morph drivers; client visuals (`TVisualizerComponent`, `TMeshComponent`,
  `TAnimationComponent`, `TLogicToWorldComponent`), entity serialize / deserialize, map decorations (`.bcc`), a
  partial `TClientGame`. The map viewer shows the 1 lane / 2 lane / PvE sandboxes with nexus, towers, bridges.
  1411 files compile, 361 tests green, no errors. Next: see CONTINUE.md.
- 2026-09-18: Phase 4 part 4, mesh effects: `TShader` (the original's shader block composition), the standard shader
  as a block template with flag defines, 8 ported effect shaders, `TMeshEffect{,Generic,WithTimekeys,Matcap,Metal,
  Spawn,Tint}`, `TMeshEffectComponent`, the effect stack, own passes (blue spawn), smoothed normals, effect textures.
  The nexus / tower crystals show their matcap. New windowed shader check (560 variants). 366 tests green, no errors.
  Next: see CONTINUE.md.
- 2026-09-18: Network (phase 3's open part): `TNetworkComponent`, `TServerNetworkComponent`, `TClientNetworkComponent`
  over in-process `TLoopbackSocket`s (the original's protocol: hello/token, world, ready, NET_EVENT, new entities),
  serialized components (`TSerializableEntityComponent`: movement, health, primary target, commander abilities reach
  the client), `TClientGame.JoinLocal`, the game thread's player state machine and own clock. The map viewer runs the
  sandbox live with card buttons: units spawn, walk, fight and die on the client. `play.bat` refreshes the class cache
  (quick import) first. 371 tests green, no errors. Next: see CONTINUE.md.
- 2026-09-18: Death decay and post effects: `TUnitDecayManagerComponent` + `DeathShader{,_Black}.fx` (dying units blow
  apart / darken for 500 ms); `TPostEffectManager` runs `PostEffects.fxs` on a SubViewport chain (pass-through
  pixel-exact) with the glow stage (a second camera, meshes' glow passes), Glow, UnsharpMasking, ColorCorrection; mesh
  effects Glow, HideAndGlow, SoulGain (effects-stage own pass); the importer takes the scripts' effect textures.
  380 tests green, 1403 shader variants compile, no errors. Next: see CONTINUE.md.
- 2026-09-18: Toon and FXAA: a G-buffer camera (HDR viewport, packed normal / depth / shading reduction written by
  every world shader, `toon.gdshaderinc`), the border blur (`PosteffectBlackBorder.fx`) and the Toon border applied in
  the world shaders' fragments (dark outlines on units, buildings, palms, rocks); FXAA 3.11 preset 12 as a pass. The
  shader check now covers the map shaders. 382 tests green, 1408 shader variants compile, no errors. Next: see
  CONTINUE.md.
- 2026-09-18: Fixes after the owner's playtest: water was gone (POSITION written on one path only) and blew out to
  white past the terrain; the build grid (`TBuildGridManagerComponent`, glow rotation) was never ported; right-drag
  now grabs the ground like `TClientCameraComponent` (checked by `--drag-check`); clear color `$23373C`. The launcher
  smoke test now checks water / white pixels and grid tiles (proven to fail on broken water). The gap list names every
  unported client visual. 385 tests green, no errors. Next: see CONTINUE.md.
- 2026-09-19: The server game runs on its own thread like the original's TGameThread (`TThreadContext` = the
  original's threadvars; `docs/game-loop.md` "Threads"): no more hitches while dragging (worst frame 25-43 ms ->
  6-13 ms). The HUD's technical panel (FPS, ping) in the map viewer; `--fps-check` / `--profile` measure frame times
  with a real right-drag. Fonts and ping icons imported. 387 tests green. Next: the owner's decision on a C++ core
  (see CONTINUE.md).
- 2026-09-19: The owner chose C++ for all game code (GDExtension; C# ruled out: GC pauses, .NET build). Toolchain
  (godot-cpp pinned, SCons, MSVC; `tools/build_native.ps1`, runner and `play.bat` build first), `docs/native.md`
  (conventions, order, rules); `DSet` and `RParam` moved to C++, their GDScript deleted. 387 tests green. Next: the
  rest of the leaf helpers, then the entity core (see CONTINUE.md).
- 2026-09-19: Every leaf helper is C++: `native/src/engine/` (Delphi RNG / hash / sort / RTL / dictionary, the clock
  `TTimeManager` (per-thread `GameTimeManager` in `TThreadContext`), `TTimer`, `TGameTimer`, priority queues, ring
  buffer, 2D grid) and `native/src/math/` (`RMatrix`, lines, rays, bezier, polygons); 18 GDScript files gone. Captures
  unchanged, client step ~10% faster. 1411 files compile, 387 tests green, no errors. Next: the entity core
  (see CONTINUE.md).
- 2026-09-19: The entity core is C++ (`native/src/entity/`: TEventbus, TBlackboard, TEntity + script runner,
  TEntityComponent, TRemoteSubscription, TEntityStream; `TThreadContext` a thread_local). GDScript components extend the
  layer `TGDEntityComponent` (GDScript cannot override bound C++ methods, `docs/native.md`). Bus Read 2.4 -> 0.5 us;
  loaded Classic 79 -> 136 fps, server 11 -> 4 ms/frame; captures unchanged. 388 tests green, no errors. Next: the
  component families (see CONTINUE.md).
- 2026-09-19: Owner's playtest fixes: outlines / glow no longer trail the picture while dragging (the extra stages'
  cameras reach the renderer in the same frame, `--ghost-check`); the game's cursors (Default / Hover); vsync off like
  the original; skinned animation and GFXD in C++ (heavy game 35 -> 69 fps); the viewer drops footmen inside the drop
  zone. 389 tests green. Next: the server thread spikes, the client-defaults audit, an all-units test (CONTINUE.md).

- 2026-09-19: The original runs: its client and game server built with Delphi 13 Community from the snapshot
  (`tools/original_build/`, `docs/original-build.md`: IDE automation, 13 documented changes), the client joins the
  server's sandbox game and draws the Single map. Found: the shipped x87 build treats NaN compares as true for
  `=`/`<`/`<=` (gotcha in `docs/original-architecture.md`). Open: its HUD does not lay out. Next: fix that, then
  reference captures and side-by-side checks (CONTINUE.md).
- 2026-09-19: The original's HUD works: the snapshot's text data is LF, the original splits on CRLF (stylesheets,
  shaders, terrain), so `run/` is a CRLF mirror; its GUI errors are logged; `run_original.ps1 -Keys P` shows the
  player HUD (capture mode). Next: reference captures of the map viewer's views, side by side (CONTINUE.md).
