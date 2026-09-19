# CONTINUE

Hand-off note for the next session. Read `CLAUDE.md` first, then this.

## The owner's brief (session 1, 2026-09-18)
- Port **Rise of Legions** to **Godot** as a strict 1:1 replica of its **last update before it became
  Crystal Clash**. Every detail the same: units, cards, numbers, effects, sounds, UI, little touches.
- But **never the original's bugs** (2026-09-19): port what the code was meant to do, list each fix in
  `docs/original-bugs.md`. Don't ask the owner whether to keep a bug.
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
and `TTimer`/`TTimeManager` clock (now C++; tests freeze time with `TTimeManager.SetFakeTime(ms)`);
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
`docs/entity-core.md`, `tests/test_movement_component.gd`); the frame step is
`TThreadContext.Current().GameTimeManager.ZDiff` (the original's threadvar GameTimeManager).
Collision is done: the loose quadtree (engine + entity variant), `TCollisionManagerComponent`,
`TServerCollisionManagerComponent` (+ `RTargetWithEfficiency`), `TCollisionComponent`,
`TWelaReadyEnemiesNearbyComponent` (section "Collision" in `docs/entity-core.md`, `tests/test_collision.gd`).
Targeting is done: `TWelaTargeting{,Radial,RadialAttention,Nexus,Self}Component` and `TWelaEfficiency*`
(section "Targeting" in `docs/entity-core.md`, `tests/test_wela_targeting.gd`); `DelphiSort` (C++)
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
(`src/runtime/graphics/effect_shaders/`); ported: Matcap, Metal, Spawn (all colors, blue in 20 own passes), Tint,
Glow, HideAndGlow, SoulGain, the component and the stack. To port another effect: its `.fx` blocks into
`effect_shaders/<name>.gdshaderinc` (use the `pso_*` locals, game-space `Worldposition`), its class in
`src/runtime/components/`, rerun the transpiler, add its shader to `tests/check_shaders.gd`'s EFFECTS; textures a
script passes to `TMeshEffect*.Create` are imported by `import_graphics.py` already.
Death decay (end of "Mesh effects" in `docs/assets.md`, `tests/test_unit_decay.gd`): `TUnitDecayManagerComponent`
(`TClientGame.DecayManager`), `DeathShader{,_Black}.fx`; dying units and buildings freeze (no script makes a death
animation) and blow apart / darken for 500 ms.
Post effects (section "Post effects" in `docs/assets.md`, `tests/test_post_effects.gd`): `TPostEffectManager` runs
`PostEffects.fxs` (`tools/convert_post_effects.py` -> `src/content/post_effects.json`) on a SubViewport chain; the
glow stage is a second camera without cull layer 20 (shaders test `CAMERA_VISIBLE_LAYERS`), meshes draw their glow
pass there (`TMesh.GlowMaterial`, `_glow_flags`). Ported: Toon, Glow, FXAA, UnsharpMasking, ColorCorrection. Toon
(section "G-buffer camera and Toon"): a third camera without cull layer 19 draws the packed G-buffer into an HDR
viewport (`toon.gdshaderinc`: every world shader writes it under `ROL_GBUFFER_CAMERA` and applies `rol_toon` to its
own fragments; a new world shader must do both), `black_border.gdshader` blurs the border buffer. Map viewer capture
switches: `--post-effects=off|none`, `--effects-off=Toon,FXAA`, `--dump-glow=on`, `--dump-toon=on`,
`--death-burst=N`, `--view=x,z,zoom`. `tests/check_shaders.gd` now compiles the map shaders too (Godot rejects
`return` in `fragment()`).
Open in phase 4: Distortion and Outline (need particles / hover), shadow mapping (terrain and vegetation receive it, palms cast it), the other mesh effects
(Ghost, Warp, Wobble, Ice, Stone, Void, Spherify, Invisible), particle effects and point lights on units, fur,
geomipmapping, the camera component (the viewer only borrows its geometry). No capture of the original exists to
compare against; an idea worth checking: whether the original client (Delphi is installed) can be built and run
offline far enough to capture reference screenshots (it logs in to the closed master server).
The live sandbox runs in the map viewer (network done): card buttons drop footmen / place spawners; units walk, fight
and die (decay) on the client, drops show their spawn effect.
Build grid (`TBuildGridManagerComponent`, `TClientGame.BuildgridManager`, `tests/test_build_grid.gd`, helpers
`RCubicBezier`, `TGUITransitionValueSingle`; `TMesh.Rotation` now exists). The map viewer: background `$23373C`,
right-drag = the original's grab-the-ground panning (`--drag-check=on` proves the point stays under the cursor), the
smoke test checks water pixels, white pixels and grid tiles in the overview (proven to fail with broken water).
**How to verify rendering changes** (the owner must never be the one to find a regression): capture every view of
both maps before (changed files from HEAD~, restored after) and after, diff, look at each capture; see the global
rule "Claude checks the screen". The gap list now names every unported client visual (health bars, orienters,
positioners, traces, range indicators, point lights, camera shake): work them down by visibility.
Owner's wishes (2026-09-18): a strict replica down to camera placement / angle / drag feel; several full audit passes
over everything once the port is complete (phase 9); requests ahead of their phase are fine (do them unless they
need an unported system, then say which).
Performance (2026-09-19, owner's priority: "a good part of why we need this port"): the server game now runs on its own
thread like the original (section "Threads" in `docs/game-loop.md`, `TThreadContext`); the hitches while dragging are
gone. The map viewer has the HUD's technical panel (FPS, ping; `TTechnicalPanel`, `GFXD.FPS`) and `--fps-check=on`
(a real fast right-drag) with `--profile=on`; results and hot spots in "Performance" of `docs/game-loop.md`. Still slow
with units: client 9 ms/frame and server 12 of 32 ms with 42 entities, mostly event bus overhead (2.3 us per Read).
Measure every change with `--fps-check` on all three setups (1 lane, 2 lanes, PvE), empty and with spawners, nothing
else running (ask the owner to close the viewer).

## The move to C++ (decided 2026-09-19, the current main line of work)
The owner decided: **all game code becomes C++** (GDExtension inside Godot; C# ruled out: GC pauses, .NET build), kept
are Godot, shaders, importers / converters, assets, docs, the transpiler (to emit C++ later) and the tests as the
spec. **Read `docs/native.md` first**: build, conventions, the order (leaf helpers, entity core, component families by
profile, game loop / network / map / graphics, transpiler to C++, viewers / HUD / tests), the rules. The owner wants
the result to look like a project built in C++ from day one: delete every GDScript file in the same change its C++
replacement lands, comments cite only the original's Delphi source, no transition traces; at the end the C++ moves to
the conventional layout and the finished project gets a **fresh git history** (confirm with the owner right before
rewriting the published repository). No `.gd` files at the end (shaders, scenes, project files and the Python tools
stay). Done: toolchain, `DSet`, `RParam`, and every leaf helper (`native/src/engine/`: the Delphi RNG / hash / sort /
RTL / dictionary, `TTimeManager`, `TTimer`, `TGameTimer`, the priority queues, ring buffer, 2D grid; `native/src/math/`:
`RMatrix`, `RLine2D`, `RRay2D`, `RCubicBezier`, `TPolygon`, `TMultipolygon`); the list, the API changes (statics ->
Get/Set, constructor args -> `.new().Create(...)`) and the measurements are in `docs/native.md`.
Step 2, the entity core, is done (2026-09-19): `native/src/entity/` (`TEventbus`, `TBlackboard`, `TEntity` with the
script runner, `TEntityComponent`, `TRemoteSubscription`, `TEntityStream`, `base_conflict_constants.h`) and
`native/src/engine/t_thread_context.*` (threadvars as a `thread_local`). **GDScript cannot override a bound C++ method**
(typed and self calls skip the override), so GDScript components extend the GDScript layer `TGDEntityComponent`
(`src/runtime/entity/t_gd_entity_component.gd`: constructors, `Destroy`, `_DeclareEvents`, base handlers), which calls
the C++ bodies `_CreateGrouped` / `_Destroy`; read "GDScript subclasses of C++ classes" in `docs/native.md`. Statics
became Get/Set (`TEventbus.GetCurrentEvent_CalledToGroup()`, `TEntity.GetLastScriptError()`, `TEventbus.SetProf({})`).
The transpiler now also writes `native/src/dws/dws_const.h` (`C::eiFree`). Result: bus Read 2.4 -> 0.5 us, Trigger
11.6 -> 3.1 us, the loaded Classic game 79 -> 136 fps with no frame over 12 ms, server 11 -> 4 ms per frame.
Capture check tooling for C++ moves: a scratch script ran the map viewer's capture mode (`--capture-out=<dir>
--wait=4000`), `--fps-check=on` on the three setups plus Classic with `--play=Blue spawner,Red spawner,Blue
footmen,Red footmen --wait=15000`, and `tests/bench_eventbus.gd`, once on the change and once on HEAD (git stash -u,
build, import), then restored and rebuilt; noise floor = two captures of the same build (water and wind animation:
up to 5% of pixels).
**First, before anything else (decided with the owner 2026-09-19): reference captures from the original itself.**
Every feature is compared against the source, but nothing against how the original looks and plays, so visible gaps
(cursor, vsync, invisible spawners, water shapes) reach the owner.
Done so far (2026-09-19): **the original runs.** Read `docs/original-build.md`: `tools/original_build/`
prepares a patched code copy (`prepare_original.py`), builds it in the Delphi 13 Community IDE by real mouse /
keyboard input (`delphi_build.ps1`: the IDE refuses command-line builds, crashes when sent window messages during a
build, closes when its EULA reminder is clicked by message), runs server + client and captures
(`run_original.ps1`), and resolves logged crash offsets (`resolve_map.py`). The client joins the server's sandbox and
draws the Single map (capture in `build/original/captures/`, not committed). Rules learned with the owner: tell them
before Delphi opens on their screen, keep every step under about a minute and report after each (they close windows
that look idle), never capture more than the window being checked (their other screens show private apps).
Done 2026-09-19: the HUD. Its collapse was the snapshot's LF line ends (the original splits its data on CRLF; stylesheets,
shaders and terrain too): `run/` is now a CRLF mirror (section "The data needs CRLF line ends" in
`docs/original-build.md`). The original's GUI / dXML / stylesheet errors are logged. `run_original.ps1 -Keys P` switches
the sandbox to capture mode: the player HUD (capture `build/original/captures/hud_capture_mode.png`). The build grid
glows cyan in the original like in the port (the grey tiles were the broken data). The owner's tutorial images
(`Graphics/GUI/Shared/Tutorial/tut*.png`) are the snapshot's only pictures of the real HUD.
Done 2026-09-19: Rise of Legions screenshots / videos are allowed as a visual cross-check (owner; rules and the list in
`docs/visual-references.md`: the 10 Steam store screenshots of 2020-11-07). The lobby runs: `run_original.ps1 -Lobby`
logs in to `tools/original_build/master_standin.py` (sample account) and reaches the real main menu; `-Steps` clicks
through it (section "The lobby" in `docs/original-build.md`). Captured: dashboard, PLAY, deck list, deck editor, card
vendor, leaderboards, shop, profile menu.
Next, in order:
1. Open question to the owner (asked 2026-09-19): may the 10 full-size Steam screenshots be downloaded into
   `build/visual-references/` (git-ignored) for detailed comparisons? The browser pane only shows them shrunk.
2. The lobby's missing content (list under "Open" in `docs/original-build.md`): shop offers, the card vendor's unlock
   requirements (legion trees), leaderboards, quests, loot, friends; then every remaining screen (settings, collection
   details, card detail / ascend, quests, notifications, starter deck choice, first-time tutorial) captured; then the
   diamond glyph in ability names; then a match started from the lobby (the stand-in hands out the local game server).
3. Capture the same views as the map viewer (overview, nexus, lanes; 1 lane, 2 lanes, PvE), then side-by-side
   checks of every open visual (gap list), and later timings, paths, frame rates. Camera placement: the sandbox dev
   panel (camera position, save / load camera) or input (`-Keys`; clicks would need the same cursor handling). The
   original now renders effects from CRLF shader data: recheck that its look did not change from the first captures.

**Then, in this order (the owner's playtest, 2026-09-19, found the port slow and missing basics; they want everything
the same as the real game or better, and the gaps found by Claude, not by them):**
1. The server thread spikes: in the map viewer the heavy Classic game (`--play=Blue spawner` x4, `Red spawner` x4, both
   footmen x2, `--wait=25000 --fps-check=on`) takes 10-90 ms per server frame with spikes to 290 ms, while the same game
   headless (DoComputeGame on the main thread, no client joined) stays under 20 ms. Not the CPU (capping the drawing
   at 60 fps and a high thread priority did not help; the machine is an i9-14900KF with efficiency cores). Suspects:
   the network path to the joined client (serializing new entities and events), contention with the main thread.
   Measure inside the thread (per-part timings of a frame), fix, then move the hottest server families to C++
   (targeting constraints, health, collision queries, think timers, pathfinding). If client and server cannot stop
   slowing each other in one process, the fallback is the original's split: the server as its own local process.
   Also measure a release export (export template + `tools/build_native.ps1 -Release`) against the debug run on the
   same setups: every number so far is the editor engine with debug checks; the owner's targets (300+ fps with 150
   units, 600+ empty) count for the release build.
2. The audit of client defaults (gap list, "Audit to do next"): every `GetDefault` option of
   `BaseConflict.Settings.Client.pas` and everything the main unit / `TGameStateManager` set up, each difference fixed
   or entered in the gap list. The cursor and vsync were such misses.
3. An automated all-units test: every unit card spawned on both sides, fighting, no script errors, frame times.
4. Classic's cross-river targeting: ported as the source does it (units walk the lanes' inner edge; the river is 20 wide,
   attention 22); the owner remembers otherwise: show them the numbers and settle it.
Then step 3 of the C++ move (component families). Tools added: map viewer `--ghost-check=on` (a dragged frame against a
still frame from the same camera), `--fps-phases=still,dragging`; `tests/test_graphics.gd` covers a released mesh's last
frame.
Owner: `docs/questions-for-devs.md` is the list for the original developers (master-server values); record their
answers there.
The owner wants longer turns locally: a whole family (or two) per turn, one checkpoint at the end.
When a hand-written file declares `class_name TFoo`, rerun the transpiler: it drops the stub.
