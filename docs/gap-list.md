# Gap list

Every user-visible behaviour of the original, and whether the port has it yet. Worked down by visibility.
Add an entry the moment a behaviour is noticed in the source, even if its phase is far away.

Status: ⬜ missing · 🟨 partial · ✅ matches original (checked against the source)

## Boot and shell
| Behaviour | Source | Status |
| --- | --- | --- |
| Splash screen (`Splash.png`) at startup | `BaseConflictSplash.pas` | ⬜ |
| Window icon | `RiseOfLegions_Icon.ico` | ⬜ |
| Custom mouse cursors: `Default` in the game window, `Hover` over clickable / writable GUI elements (Windows hardware cursors, hot spot 2, 2) | `BaseConflictMainUnit.pas:162` `LoadCursor`, `Graphics/GUI/Cursors/*.cur`, `BaseConflict.Classes.Gamestates.pas:2316-2343` | ✅ converted by `import_graphics.py`, set by `src/viewer/game_cursor.gd` in the main scene and viewers; the client window's Windows cursors (menus outside the game window) wait for the menus |
| VSync off by default (`coGraphicsVSync` = False), no frame limit in the match (`coMenuLimitFramerate` 50 only in menus) | `BaseConflict.Settings.Client.pas:525, :608`, `BaseConflictMainUnit.pas:301` | 🟨 vsync off (`project.godot`); the menu frame limit waits for the menus |
| **Audit to do next**: every client option default (`BaseConflict.Settings.Client.pas` `GetDefault`) and everything `BaseConflictMainUnit.pas` / `TGameStateManager` set up at start, compared one by one with the port, each difference entered here | | ⬜ |
| Settings persisted between runs | `Settings.ini`, `BaseConflict.Settings.Client.pas` | ⬜ |
| Window modes: menus in a window of a fixed 16:9 size (1024x576, 1280x720, 1600x900, 1920x1080, 2560x1440 or custom, `coMenuClientResolution`) with menu scaling (downscaling / fullscreen / disabled); the match switches to the display mode (default borderless fullscreen at the monitor's own size, or windowed at `coEngineResolution`, default: the monitor's work area) and back | `TGameStateManager.SetIngameWindow` / menu window, `MENU_RESOLUTIONS`, `BaseConflictMainUnit.pas` | ⬜ |

## Match (sandbox first)
| Behaviour | Source | Status |
| --- | --- | --- |
| Map terrain (Classic, Single): heightmap, 16 chunk textures, normal / material maps, lighting | `Engine.Terrain.pas`, `Maps/*/*.ter` | 🟨 drawn at full detail (the original's geomipmapping LoD is not ported), no shadow mapping yet |
| Map water: waves, refraction, reflection, depth color, caustics, sun specular | `Engine.Water.pas`, `Watershader.fx`, `*.wat` | 🟨 the G-buffer lookups come from Godot's depth / screen / normal textures (where nothing is drawn: position (0, 0, 0) like the cleared buffer); not compared against a capture of the original; the smoke test checks the sea covers the overview. The sea past the terrain's edge turns bright cyan (the extinction formula over the cleared buffer): outside the game camera's zoom range |
| Map vegetation: palms and grass tufts from their stored seeds, wind sway | `Engine.Vegetation.pas`, `*.veg` | ✅ rolls replayed with Delphi's RNG (tested); palms cast no shadow yet |
| Map decorations (`.bcc` and the scenarios' `AddDecoEntity`: nexus ground, bridges, rocks) | `BaseConflict.Map.Client.pas` | ✅ created from their scripts, placed, drawn (map viewer); the ambient sound emitters are silent until sound |
| Nexus, towers, spawners and the other scenario entities drawn with their meshes, team textures and stand animations | `TMeshComponent`, `TAnimationComponent`, `Engine.Animation.pas` | 🟨 drawn from the engine's raw meshes like release builds, matcap crystals, tower spawn animation, glow (nexus crystal and runes); particles and point lights not yet |
| Shadows (the original's own shadow mapping, first light) | `Engine.Core.pas` shadow map | ⬜ |
| Game camera: scroll (keys, edges, drag), zoom 2.6..3.8, camera zone limits, rotation | `TClientCameraComponent` | 🟨 the map viewer uses its view geometry (offset, field of view, zoom range) and its right-drag panning (the grabbed ground point on the y = 0 plane stays under the cursor like `Client.pas:2314`, checked by `--drag-check`; the extra stages follow the camera in the same frame, checked by `--ghost-check`); the component itself is not ported |
| Every unit card plays: spawn each unit of the game on both sides and let them fight (errors, behaviour, frame times) | `Scripts/Units/**` | ⬜ an automated all-units test is to be written; so far footmen, golems, caster golem, gatling turret, towers are tested |
| Frame times with a full field (50+ units): no server frame over its 32 ms budget, no stutter | performance goal | 🟨 129 entities: client 35 -> 69 fps dragging after the animation move; the server thread spikes to 70-290 ms while the same game headless stays under 20 ms (cause not found yet: next) |
| Build grid behind each nexus: glowing tiles, a tile goes dark when its spawner fires (flash, 1 s fade), all glow in again after the rotation; colors while placing a card | `TBuildGridManagerComponent` | 🟨 tiles, glow and rotation ported (test_build_grid, captures); the activation particles and the placement colors' callers (input) wait for particles / phase 5 |
| HUD technical panel: FPS and ping (icon good / neutral / bad) top left, option `coGameplayShowTechnicalPanel` (on) | `TechnicalPanel.dui`, `core_game.scss` `.technical-panel`, `TFPSCounter` | 🟨 map viewer (`TTechnicalPanel`): layout, colors, font Proza Libre 500 and the counter from the source; the font size is not from the GUI engine's metrics yet (phase 7) |
| Clear color `$23373C` (dark teal) where nothing is drawn | `BaseConflictMainUnit.pas:346` | ✅ map viewer |
| Health bars and resource bars over units and buildings | `TResourceDisplay*Component` | ⬜ |
| Units turn to face where they walk / what they attack; attached parts (weapons, riders) follow bones | `TOrienter*Component`, `TPositioner*Component` | ⬜ (stubs: the facing a client unit shows is not checked yet) |
| Buff / state icons over units | `TStateDisplay*Component` | ⬜ |
| Weapon trails, link beams and rays, projectile ribbons | `TVertexTrace*`, `TLink*VisualizerComponent`, `TVertexRay*`, `TVertexQuad*` | ⬜ |
| Range indicators and spell target previews | `TRangeIndicator*`, `TSpelltargetVisualizer*`, `TTextureRangeIndicatorComponent` | ⬜ |
| Point lights on units and effects | `TPointLightComponent` | ⬜ |
| Camera shake | `TCameraShakerComponent` | ⬜ |
| Commander manager (the local player's commanders on the client), GUI, input | `TCommanderManagerComponent`, `TClientGUIComponent`, `TClientInputComponent` | ⬜ phase 5 |
| Units walk lanes, fight, die | `Scripts/Units`, server components, the server -> client link | 🟨 live in the map viewer: the server's units reach the client over the in-process network and walk, fight and die there (test_network); dying units and buildings freeze and decay with the death shader of their color for 500 ms (`TUnitDecayManagerComponent`, test_unit_decay) |
| Card hand, play spawner / drop / spell | `BaseConflict.Classes.Gamestates*.pas` | 🟨 plays go client -> server (eiUseAbility) and work; the map viewer has stand-in card buttons (drops go on the lanes, inside the map's `Drop` zone: the sandbox server checks no targets, `Brains.pas:1158`, the game's client does); the hand, targeting and the HUD's can-use check are phase 5 |
| Units on the two lanes of Classic walk the shortest way, along the rails at the lanes' inner edge (the walk zone's hole is the river, y -10..10); in the middle the river is 20 wide and the attention range 22 (`UnitTemplate.dws`), so both sides notice each other across it | `TBrainFollowLaneComponent`, `TPathfinding`, `TWelaTargetingRadialAttentionComponent.UpdateTargets` (`Server.Welas.pas:1574`) | 🟨 ported as the source does it; the owner remembers no cross-river targeting in the real game: to settle |
| Minimap | `BaseConflict.Classes.MiniMap.pas` | ⬜ |
| Unit skins (Default, Machine, Underworld, Woodlands, ...) | mesh folders, `Entity.SkinID` | ⬜ (the SkinID reaches client entities; the skin mesh folders are imported) |
| Unit animations: walk / attack / stand with fades, walk speed from movement speed | `TAnimationController`, `TMeshComponent.OnPlayAnimation` | 🟨 ported; units now walk on the client (not yet checked frame by frame against the walk animation's speed) |
| Tooltips with ability keywords | `TTooltipUnitAbilityComponent` | ⬜ |
| Scripted AI `MegaRootDude` never runs: its server script does not compile (undeclared `ArcherDrop`); the port keeps the error | `Scripts/AI/MegaRootDude.dws` | 🟨 transpiled as the error; runtime reporting in phase 2 |

## Presentation
| Behaviour | Source | Status |
| --- | --- | --- |
| Particle effects per card | `Graphics/Effects/ParticleEffects` | ⬜ |
| Mesh effects: matcap, metal, spawn animations (per color, with their glow), tint, glow, hide-and-glow, soul gain | `TMeshEffect*`, effect shaders | ✅ ported, compile-checked, tested; seen on the nexus crystals and drops (captures) |
| Mesh effects: ghost, warp, wobble, ice, stone, void, spherify, invisible | `TMeshEffect*` | ⬜ |
| Post effects: glow stage + glow, unsharp masking, color correction | `PostEffects.fxs`, `Engine.PostEffects.pas` | 🟨 ported on a viewport pipeline (map viewer); pass-through checked pixel-exact; no capture of the original to compare the look against |
| Post effects: Toon (dark borders on units, buildings, decorations, palms), FXAA | `PostEffects.fxs`, `PosteffectBlackBorder.fx`, `PosteffectToon.fx`, `FXAA.fx` | 🟨 ported (G-buffer camera, border passes, preset 12); borders and smoothed edges seen in map viewer captures; no capture of the original to compare against |
| Post effects: distortion, outline (hover highlight) | `PostEffects.fxs` | ⬜ (distortion needs particles, outline the outline stage) |
| Music and sound effects | `Sound/Banks` | ⬜ |
| 29 languages | `Lang/*.csv` | ⬜ |

## Menus and meta
| Behaviour | Source | Status |
| --- | --- | --- |
| Main menu, dashboard, navbar | `Graphics/GUI`, `Lang/dashboard.csv`, `navbar.csv` | ⬜ |
| Collection, deckbuilder, card sacrifice | `Lang/collection.csv`, `deckbuilder.csv` | ⬜ |
| Shop (offline) | `BaseConflict.Api.Shop.pas` | ⬜ |
| Quests | `BaseConflict.Api.Quests.pas` | ⬜ |
| Tutorial | `Lang/tutorial.csv`, `Scripts/Scenarios` | ⬜ |
| Scenarios and mutators | `Scripts/Scenarios` | ⬜ |
| Post-game statistics | `Lang/game_statistics.csv` | ⬜ |
