# Gap list

Every user-visible behaviour of the original, and whether the port has it yet. Worked down by visibility.
Add an entry the moment a behaviour is noticed in the source, even if its phase is far away.

Status: ⬜ missing · 🟨 partial · ✅ matches original (checked against the source)

## Boot and shell
| Behaviour | Source | Status |
| --- | --- | --- |
| Splash screen (`Splash.png`) at startup | `BaseConflictSplash.pas` | ⬜ |
| Window icon | `RiseOfLegions_Icon.ico` | ⬜ |
| Custom mouse cursors | `Graphics/**/*.cur` | ⬜ |
| Settings persisted between runs | `Settings.ini`, `BaseConflict.Settings.Client.pas` | ⬜ |

## Match (sandbox first)
| Behaviour | Source | Status |
| --- | --- | --- |
| Map terrain (Classic, Single): heightmap, 16 chunk textures, normal / material maps, lighting | `Engine.Terrain.pas`, `Maps/*/*.ter` | 🟨 drawn at full detail (the original's geomipmapping LoD is not ported), no shadow mapping yet |
| Map water: waves, refraction, reflection, depth color, caustics, sun specular | `Engine.Water.pas`, `Watershader.fx`, `*.wat` | 🟨 the G-buffer lookups come from Godot's depth / screen / normal textures; not compared against a capture of the original |
| Map vegetation: palms and grass tufts from their stored seeds, wind sway | `Engine.Vegetation.pas`, `*.veg` | ✅ rolls replayed with Delphi's RNG (tested); palms cast no shadow yet |
| Map decorations (`.bcc` and the scenarios' `AddDecoEntity`: nexus ground, bridges, rocks) | `BaseConflict.Map.Client.pas` | ✅ created from their scripts, placed, drawn (map viewer); the ambient sound emitters are silent until sound |
| Nexus, towers, spawners and the other scenario entities drawn with their meshes, team textures and stand animations | `TMeshComponent`, `TAnimationComponent`, `Engine.Animation.pas` | 🟨 drawn from the engine's raw meshes like release builds, matcap crystals, tower spawn animation; glow, particles and point lights not yet |
| Shadows (the original's own shadow mapping, first light) | `Engine.Core.pas` shadow map | ⬜ |
| Game camera: scroll (keys, edges, drag), zoom 2.6..3.8, camera zone limits, rotation | `TClientCameraComponent` | 🟨 the map viewer uses its view geometry (offset, field of view, zoom range); the component itself is not ported |
| Units walk lanes, fight, die | `Scripts/Units`, server components | ⬜ |
| Card hand, play spawner / drop / spell | `BaseConflict.Classes.Gamestates*.pas` | ⬜ |
| Minimap | `BaseConflict.Classes.MiniMap.pas` | ⬜ |
| Unit skins (Default, Machine, Underworld, Woodlands, ...) | mesh folders, `Entity.SkinID` | ⬜ (the SkinID reaches client entities; the skin mesh folders are imported) |
| Unit animations: walk / attack / stand with fades, walk speed from movement speed | `TAnimationController`, `TMeshComponent.OnPlayAnimation` | 🟨 ported and tested on a static unit; units don't walk on the client yet (no network sync of movement) |
| Tooltips with ability keywords | `TTooltipUnitAbilityComponent` | ⬜ |
| Scripted AI `MegaRootDude` never runs: its server script does not compile (undeclared `ArcherDrop`); the port keeps the error | `Scripts/AI/MegaRootDude.dws` | 🟨 transpiled as the error; runtime reporting in phase 2 |

## Presentation
| Behaviour | Source | Status |
| --- | --- | --- |
| Particle effects per card | `Graphics/Effects/ParticleEffects` | ⬜ |
| Mesh effects: matcap, metal, spawn animations (per color), tint | `TMeshEffect*`, effect shaders | ✅ ported, compile-checked; seen on the nexus crystals only (units don't reach the client yet) |
| Mesh effects: glow, hide-and-glow, soul gain, ghost, warp, wobble, ice, stone, void, spherify, invisible | `TMeshEffect*` | ⬜ (glow needs the glow stage) |
| Post effects | `PostEffects.fxs` | ⬜ |
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
