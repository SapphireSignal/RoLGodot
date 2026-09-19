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
the asset pipeline, is under way: meshes (from the raw `.msh`), map graphics, decorations, the client visuals of
placed entities and the server -> client network done (the map viewer runs the sandbox live), the render extras next (see "Phase 4" below and `docs/port-plan.md`). Verified facts about the original are in
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
Every server / shared stub is ported; the 82 left (`src/runtime/dws/stubs/`) are client visuals (effects, orienters,
positioners, particles...) / GUI / sound (phase 4+) and `RIntVector2` / `RVector3`.

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
Network done: read `docs/game-loop.md`, "Network". Client and server talk over in-process `TLoopbackSocket`s with the
original's protocol; `TClientGame.JoinLocal(thread, info, token)` joins (token `"1"` for the test server game), a
client frame is `TTimeManager.TickTack()`, eiIdle, `ReadyWhenLoaded()`, `Idle()` (see `tests/test_network.gd`,
`src/viewer/map_viewer.gd`). The server's serializable components reach the client (`NetworkFields()` per class).
Open in phase 3: bots (`TPvPBotComponent`), time manager pause.

## Phase 4, the asset pipeline
Read `docs/assets.md`. Setup after fetching `reference/`: `python tools/import_graphics.py`, then a Godot `--import`
(the test runner imports too). **Meshes load from the engine's raw `.msh`** (what release builds draw,
`LOAD_RAW_MESH`), not the FBX: `TEngineRawMesh` reads the whole file, `TMesh` (`src/runtime/graphics/`) builds one
surface, skins in the shader (`ROL_SKINNING`, `bone_transforms`), morphs as blend shapes, and animates with
`TAnimationController` (`Engine.Animation.pas`) + its bone / morph drivers. The FBX route was dropped because Godot's
import misplaced skinned parts (the nexus crystal sat under the ground). `src/viewer/mesh_viewer.tscn` (capture mode;
`--turntable=N` for video frames, ffmpeg is installed via WinGet): all 201 meshes load and pose.
Map graphics (section "Maps"): `TClientMap` with terrain, water, vegetation and the decorations (`.bcc` ->
`<map>.decorations.json`), `DelphiRandom`, the map viewer. Winding rule: keep the original's index order in Godot space.
Client visuals are ported (section "Client visuals" in `docs/entity-core.md`): `TVisualizerComponent`,
`TMeshComponent`, `TAnimationComponent`, `TLogicToWorldComponent`, entity serialize / deserialize, and a partial
`TClientGame` (`src/runtime/game/t_client_game.gd`) whose `ReceiveWorld` copies a server game's entities as a joining
client gets them. `GFXD` (`src/runtime/graphics/gfxd.gd`) holds the main scene and the frame counter;
`TOptionManager` only the client options in use.
The map viewer now shows the battlefield: scenario buttons 1 lane (Single, default), 2 lanes (Classic), PvE (Single,
golem base on its nexus ground); nexus with floating team crystals, towers, bridges with their stone rails.
Mesh effects (section "Mesh effects" in `docs/assets.md`, `tests/test_mesh_effects.gd`): `TShader` composes the
standard shader template (`standard_shader.gdshaderinc`, never included) with the effects' ported block files
(`src/runtime/graphics/effect_shaders/`); ported: Matcap, Metal, Spawn (all colors, blue in 20 own passes), Tint, the
component and the stack. To port another effect: its `.fx` blocks into `effect_shaders/<name>.gdshaderinc` (use the
`pso_*` locals, game-space `Worldposition`), its class in `src/runtime/components/`, rerun the transpiler, add its
shader to `tests/check_shaders.gd`'s EFFECTS.
Open in phase 4: shadow mapping (terrain and vegetation receive it, palms cast it), glow stage + bloom
(`PostEffects.fxs`; the nexus / tower glow textures are bound per team already) and with it the glow-type effects
(Glow, HideAndGlow, SoulGain, the spawn effects' glow pass), the other effects (Ghost, Warp, Wobble, Ice, Stone, Void,
Spherify, Invisible), particle effects and point lights on units, fur, outline, geomipmapping, the camera component
(the viewer only borrows its geometry). No capture of the original exists to compare against; an idea
worth checking: whether the original client (Delphi is installed) can be built and run offline far enough to capture
reference screenshots (it logs in to the closed master server).
The live sandbox runs in the map viewer (network done): card buttons drop footmen / place spawners; units walk, fight
and die on the client. Check in a capture (`--play=... --wait=...`) that drops show their spawn effect, units their
walk / attack / death animations.
**Next:** pick by visibility: the unit visuals of a live fight (death: decay manager, `eiDie` on the client; health
bars are HUD, phase 5), or the glow stage + bloom (the crystals' and every glow texture's look, then the glow
effects), or phase 5's camera component and card hand on top of the network.
Owner: `docs/questions-for-devs.md` is the list for the original developers (master-server values); record their
answers there.
The owner wants longer turns locally: a whole family (or two) per turn, one checkpoint at the end.
When a hand-written file declares `class_name TFoo`, rerun the transpiler: it drops the stub.
