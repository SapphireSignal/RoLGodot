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
Phases 0-2 done, phase 3 done except bots and network (the headless sandbox match runs and is profiled); phase 4,
the asset pipeline, is under way: meshes done, map graphics next (see "Phase 4" below and `docs/port-plan.md`). Verified facts about the original are in
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

Step 5 done for every server / shared class (the rest by `docs/script-api.md`, entity-local first): `TCommanderIncome*` + `RIncome`,
and `TTimer`/`TTimeManager` clock in `src/runtime/engine/` (tests freeze time with `TTimeManager.FakeTime`);
`TDynamicZone*Emitter`, `TGameEventEnumeratorComponent` (`TNexusEarlyVulnerabilityComponent` is unused: skipped).
`TEntityManagerComponent` (the real `Game.EntityManager`; `TServerEntityManagerComponent` /
`TClientEntityManagerComponent` extend it later, with the game).
`TModifier*` (9), `TWelaReady*` (8 + `TGameTimer`), target types (`RTarget`/`ATarget`/`RTargetValidity`) and
`TWelaTargetConstraint*` (18) + `TWelaTriggerCheck*` (3), each with a real-script test (see `docs/entity-core.md`).
`tools/find_unused_classes.py` now skips fluent setters, strings and comments (43 unused classes, all in
`docs/unused-features.md`).
`TWelaHelperResolveComponent`, `TWarhead{,Link}ApplyScriptComponent` (`tests/test_warhead_apply_script.gd`);
`TEntityDataCache` (`src/runtime/classes/`, carried by the global bus as `TEventbus.EntityDataCache`),
`TWelaEventRedirecter`, `TWelaReadySpawnedComponent` (`tests/test_entity_data_cache.gd`, incl. the real
`Commander\CommanderMethods` AddDrop). `Shared.Wela.pas` is now done except what waits for targeting.
The map and pathfinding are done: read `docs/map.md` (maps are converted by `tools/convert_maps.py` into
`src/content/maps/`, build zones come from the scenario scripts, lanes are hard-coded, A* ties break last in,
first out). All 21 used target constraints are ported.
Movement is done: `TPositionComponent`, `TMovementComponent`, `TPathfindingComponent` (section "Movement" in
`docs/entity-core.md`, `tests/test_movement_component.gd`); the frame step is `TTimeManager.ZDiff` until the game
loop.
Collision is done: the loose quadtree (engine + entity variant), `TCollisionManagerComponent`,
`TServerCollisionManagerComponent` (+ `RTargetWithEfficiency`), `TCollisionComponent`,
`TWelaReadyEnemiesNearbyComponent` (section "Collision" in `docs/entity-core.md`, `tests/test_collision.gd`).
Targeting is done: `TWelaTargeting{,Radial,RadialAttention,Nexus,Self}Component` and `TWelaEfficiency*`
(section "Targeting" in `docs/entity-core.md`, `tests/test_wela_targeting.gd`); `src/runtime/engine/delphi_sort.gd`
is Delphi's `TList.Sort` (use it wherever the original sorts with ties). Global / Rectangle targeting are unused.
Effects and spotty warheads are done: 18 effect/helper classes and 9 warheads (sections "Effects" and "Warheads"
in `docs/entity-core.md`, `tests/test_wela_effects.gd`, `tests/test_warheads.gd`; the real server SmallMeleeGolem
now hits another for 8.5). New helpers: `RParam.Equal` (the original's `=`), `BC.gsLoading..gsShutdown`
(`Game.IngameStatus`, fakes must carry it), `BC.ALL_BUFF_TYPES`. Left of these families (they spawn entities, need
links or collision queries): `TWelaEffect{Factory,Replace,Projectile}Component`, `TWelaLinkEffect*`,
`TWelaEffectLinkPayCostMyselfComponentServer`, splash warheads, `TWarheadSpottyTeleportComponent`.
The brains are done: every used class of `...Server.Brains.pas` (section "Brains" in `docs/entity-core.md`,
`tests/test_brains.gd`; two real server golems now fight to the death through the real think loop). New:
`TDelayedEventHandler` (`src/runtime/classes/`, queue = `Game.DelayedEvents`, a `TIntPriorityQueue`;
`ProcessDueEvents` is TServerGame.Idle's loop), `RCommanderAbilityTarget` (`src/runtime/types/`), `BC.THINK_TIME_INTERVAL`
and `BC.UNIT_PROPERTIES_PREVENT_{THINKING,MOVEMENT}`. Test fakes of the game now need `Map.Lanes` (a real
`TLaneManager`) and `DelayedEvents` when real units think.
Spawning is done: `TServerEntityManagerComponent` (the server game's EntityManager and ServerEntityManager),
`TGameStatisticManager` (`src/runtime/classes/`, `Game.Statistics`), `TWelaEffect{Factory,Replace,Projectile}Component`,
`TProjectileEventRedirecter`, `TBrain{Spawner,CapturePoint}Component`, the splash warheads and
`TWarheadSpottyTeleportComponent` (sections "Spawning" and "Splash and teleport" in `docs/entity-core.md`,
`tests/test_spawning.gd`, `tests/test_splash_teleport.gd`). Old test fakes that kill real units now use the server
entity manager (souls spawn on death). `tools/run_tests.ps1` now fails on any `SCRIPT ERROR` in the test log.
Links are done: the seven link classes (section "Links" in `docs/entity-core.md`, `tests/test_links.gd`, incl. a real
SmallCasterGolem's Crystal Power link and a real GatlingTurret firing until out of ammo). New: `DelphiDictionary`
(`src/runtime/engine/`, Delphi's TDictionary with its slot order and remove-while-walking skip; use it wherever the
original walks or edits a TDictionary) and `RTarget.Hash`.
The combat modifiers are done: `TModifier{Blinded,MultiplyDealtDamage}Component`, `TBuffTakenDamageMultiplierComponent`,
`TWelaReady{Nth,EntityNearby}Component` (section "Combat modifiers", `tests/test_combat_modifiers.gd`; random rolls are
tested by seeding Godot's RNG and replaying the rolls).
Game end, waves and statistics are done: `T{Server,}PrimaryTargetComponent`, `TSuicideOnGameEndComponent`,
`TWelaEffect{IncomePayout,WaveSpawn}Component`, `TStatisticsUnitComponent`, `TWelaEffectStatisticsComponent`,
`TServerCardPlayStatisticsComponent` + `TGameStatisticManager.CardPlayed` (section "Game end, waves, statistics",
`tests/test_statistics.gd`). New: `BC.ScriptFilenameToCard{Type,Colors}`, `BC.BUILDGRID_SIZE/_SLOTS`,
`BC.UNIT_PROPERTIES_STATE_EFFECTS`, `DSet.Intersection`. Fake games that build real server units now need
`Statistics` and `Commanders` (every unit carries TStatisticsUnitComponent).
The commander and the card database are done: `TCardInfoManager.Instance()` (cards from `src/content/cards.json`, made
by `tools/convert_cards.py`, checked by the test runner), `TCardInfo` (stats take the side's `TEntityDataCache`;
translated texts wait for the localization), `TCommanderAbilityComponent` + `RCommanderCard`, `TCommanderAbility`,
`TCommanderComponent` (section "Commander and cards", `tests/test_commander.gd`). New engine helpers: `DelphiHash`
(Delphi's Bob Jenkins string hash, for `DelphiDictionary` string keys) and `DelphiRtl` (ExtractFilePath / FileName,
ChangeFileExt, CompareText, SameText). Test fakes pass real `TCardInfo`s now (resolve by UID).
The directors are done: `TScenarioDirectorComponent` (unit pool, timed actions run last-queued-first, boss waves,
squad rows, KI players), `TServerSandbox{,Command}Component`, `TSandboxComponent`, `TTutorialDirectorServerComponent`
(bullet "Directors" in `docs/entity-core.md`, `tests/test_directors.gd`, incl. the real `Scenarios\AttackScenarioBase`
+ `AttackScenarioEasy` scripts and their first minute). New: `BC.cc*` (EnumClientCommand), `BC.MAP_SINGLE/DOUBLE`,
`BC.SCENARIO_PVE_DEFAULT_PREFIX`, `DelphiRtl.StrToIntDef`. Fake games for the directors carry `GameInformation`
(`.Scenario.MapName`, `.ScenarioUID`), `GameDirector`, `Overwatch` / `OverwatchClearable`.
Every server / shared stub is ported; the 85 left (`src/runtime/dws/stubs/`) are client visuals / GUI / sound
(phase 4+) and `RIntVector2` / `RVector3`.

## Phase 3, the game loop
Done: read `docs/game-loop.md`. `TGameThread.new().Create(TGameManager.CreateTestserverGameInfo())` builds the real
sandbox; `SetAllPlayersPlaying()` then `DoComputeGame()` per 32 ms frame runs it. `tests/test_sandbox_match.gd` is
the phase 3 goal: Footman duel numbers, spawner, nexus damage. Game predicates are methods (`League()`,
`IsSandbox()`, `HasStarted()`, `IsShuttingDown()`, `GameInformation.IsTutorial()`), `InGameStatus` a property; test
fakes follow that. Runner: `$env:RUN_TESTS_ONLY = 'test_foo'` runs one file and prints objects left per test (the
~82 objects "leaked at exit" are the compile sweep's baseline).
Profiled (section "Performance" in `docs/game-loop.md`): the event bus is 2.5x faster (subscribers carry their
handler, single-group events walk only their group's subscribers, no event-stack arrays, a lookup for the network
send check); the sandbox match runs at 0.31 x real time. Tools: `tests/profile_sandbox.gd` (with
`PROFILE_HANDLERS=1`: the costliest handlers), `tests/bench_eventbus.gd`; run them by hand like the test runner
does Godot (headless, absolute `--log-file`, `--script res://tests/...`).
Open in phase 3: bots (`TPvPBotComponent`), network, time manager pause.

## Phase 4, the asset pipeline
Read `docs/assets.md`. Setup after fetching `reference/`: `python tools/import_graphics.py`, then a Godot `--import`
(the test runner imports too). Meshes are done: `TMesh` (`src/runtime/graphics/`), the shader, `TLightManager`,
`src/viewer/mesh_viewer.tscn` (capture mode for checking renders yourself; `--turntable=N` for video frames, ffmpeg is
installed via WinGet). Every script mesh reference resolves (114 references, 86 base models, 173 unit files with skins).
Next: the map graphics: `.ter` terrain (+ tiled Classic<N>Diffuse/Material/Normal textures), `.wat` water, `.veg`
vegetation, `.bcc`; read `Engine.Terrain.pas`, `Engine.Water.pas`, `Engine.Vegetation.pas`, `BaseConflict.Map.Client.pas`
and plan converters, then render the Classic map in a viewer. Later in phase 4/6: glow stage + bloom, fur, outline,
the original's shadow mapping.
The owner wants longer turns locally: a whole family (or two) per turn, one checkpoint at the end.
When a hand-written file declares `class_name TFoo`, rerun the transpiler: it drops the stub.
