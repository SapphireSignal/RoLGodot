# Assets (phase 4)

How the original's graphics get into the port, and how they are drawn. Facts about the original's formats:
`original-architecture.md` ("Assets and formats").

## Setup
`assets/graphics/` is generated, git-ignored and needs `reference/`:

    python tools/import_graphics.py          # ~270 MB, idempotent (only changed files are rewritten)
    Godot --headless --path . --import       # tools/run_tests.ps1 does this too

`tools/run_tests.ps1` runs `import_graphics.py --check` (every descriptor resolves). The export includes
`assets/graphics/*.json` (descriptors, map data, decorations), `*.bin` (terrain grids) and `*.msh` (raw meshes)
besides the imported textures.

## Meshes
**The geometry is the engine's raw mesh, not the FBX.** Release builds of the original set `LOAD_RAW_MESH`
(`Engine.Mesh.pas`): `TMeshAnimatedGeometry.CreateFromFile` loads `ChangeFileExt(geometry, '.msh')`, the engine's
own pre-converted file (vertices, bones, skin, bone and morph animations), for every mesh. The port does the same.
(It used Godot's FBX import before; for skinned files Godot's result differs from the `.msh`: the nexus crystal ended
~65 file units lower, under the ground. The `.msh` data has no NaN bones either: the FBX-only NaN repair is gone.)

`tools/import_graphics.py` walks every mesh descriptor `Graphics/**/*.xml` (200, all `TMesh`) and writes, with
**lowercased paths** (the original's references differ in case from the files; the port lowercases every graphics
path, `TMesh.ResolveDescriptor`):
- `<name>.mesh.json`: the descriptor: every published `TRawMesh` property, defaults from
  `SetDefaultMaterialSettings` for missing ones, texture names resolved in the descriptor's folder, `GeometryFile`
  = the `.msh`. The old `Specular` element of 10 descriptors has no property and is skipped, like the deserializer.
- the `.msh`, copied.
- each referenced texture, copied (`.tga` / `.png`) or decoded from the engine cache `.tex` when no source image
  exists (KTF: `decode_ktf`, pixel-identical to the source TGA where both exist), with a `.import` (lossless,
  mipmaps: the original generates mipmaps). Textures the scripts swap in (`BindTextureToTeam` / `UnitProperty` /
  `Resource`, e.g. `NexusDiffuse2.tga` of the red team) are found by scanning the scripts' `TMeshComponent`
  statements; a skinned unit's concatenated path (`'...VoidBowman' + SkinFileSuffix + '\VoidBowman.xml'`) matches
  every skin folder by file name.
- one script loads a geometry file directly (`Environment\Stones1\Stones1.fbx`): `TRawMesh.CreateFromFile` with a
  geometry file takes default material settings and textures by name convention (`<name>Diffuse.tga`, ...); the
  importer writes that as a descriptor (201 in all).
Stale `.fbx` copies of earlier versions are deleted from `assets/graphics/`.

**The raw mesh** (`TEngineRawMesh`, `t_engine_raw_mesh.gd`, `Engine.Core.Mesh.pas`): header, 184-byte vertices
(Position[0..7] = base + morph offsets, uv, normal, tangent, binormal, bone weights, bone indices as singles,
smoothed normal), colors, UInt32 indices, bones (depth first, `string[128]`, `RMatrix4x3`, child count), skin links
(bone name, offset matrix), animations (ShortString name; channels of keys `Time, Translation, Scale, Quaternion
x y z w` + target), morph target names. All 201 files read to their exact end. `RMatrix4x3` memory is
`_11 _12 _13 _41 _21 _22 _23 _42 _31 _32 _33 _43`, column i = `(_i1, _i2, _i3)`; the port keeps it as a Transform3D.

**Drawing** (`TMesh`, `TMesh.TGeometry` cached per file like the original's device cache): one surface (the raw mesh
holds the collapsed subsets), the file's index order, file units (the Footman is ~86 units tall; the scripts' size
factors expect raw units: `SIZE_FACTOR_3DSMAX = 2 / 125`, `eiModelSize`). **Skinning** is done in the shader as
`Standardshader.fx` does (`ROL_SKINNING`): weights and indices in `CUSTOM0` / `CUSTOM1`, `bone_transforms[66]` =
`CombinedMatrix * BoneSpaceOffsetMatrix` per skin link (`TSkin.ComputeAnimatedMatrices`), uploaded each frame;
Godot's skeletons are not used (they cannot hold the sheared matrices the original's math allows). **Morph targets**
(7 meshes: VoidBowman, Ballista, SaplingFarm, two golems, rootnetwork) are relative blend shapes, weights = the morph
driver's / 100, applied before skinning like the shader's `pos += Position_Morph_k * weight`. Culling uses the
file's bounding sphere as `TMesh.Render` does (`custom_aabb`), not the animated pose.

**Space.** The original loads right-handed file data unchanged into its left-handed world and mirrors X in the
world matrix. The port maps game space (x, y, z) to Godot (-x, y, z) (`TMesh.ToGodot`); the two mirrors cancel,
so file coordinates are used as they are and `TMesh.ComputeTransformationMatrix` conjugates the base:
`basis = G * Base(Left, Up, Front) * G * Scaling`, `G = diag(-1, 1, 1)`. `TMesh.TransformationMatrix()` is the
original's game-space matrix (with the mirror) for bone positions and bounds.

**Animations** (`t_animation_controller.gd` = `Engine.Animation.pas`; the skinned driver is C++,
`native/src/graphics/t_skinned_mesh_animation_driver.*`, parsed once per geometry and copied per mesh like the
original's `GetCopy`, with the original's cap of 9 animations per bone and frame; the morph driver is in `t_mesh.gd`). One take per file
(`AnimStack::Take 001`, `TMesh.FBX_DEFAULT_ANIMATIONTRACK`), keys every 1000 / 30 ms. `TAnimationController`: a stack
of playing animations with 500 ms fades and a looping default animation, one update per frame (`GFXD.GetFrameCount()`, C++ `native/src/graphics/gfxd.*`),
times from `TTimeManager`. `TSkinnedMeshAnimationDriver`: per animation the channels with their times normalized by
its length; `CreateNewAnimation` (ExtractPart) cuts frames start..end (both included) out of the take; each update
finds the two keys around the time key, lerps / slerps (`RVector4.SLerp`) and adds the weighted result to the bone;
`PassAnimationToHierarchy` sums translation and scale by weight, slerps the rotations in order (its weight sum stays
the first one's, as written) and multiplies down the hierarchy. `TMeshMorphAnimationDriver`: weight curves per
target, slices by time (`CreateSlice`, including its final-key lerp as written), weights summed per frame.
`TMesh.ShowFrame(frame)` (mesh viewer) poses a frame of the take directly.

## Shading
`src/runtime/graphics/standard_shader.gdshaderinc` ports `Standardshader.fx` and, for opaque meshes, the deferred
light pass `DeferredDirectionalAmbientLight.fx`; `TMesh` builds one variant per cull mode (`cmCCW` back,
`cmNone` disabled, `cmCW` front) and alpha. Key facts:
- **Gamma space.** The original has no sRGB textures or targets. The shader works on raw values and writes
  `ALBEDO = srgb_to_linear(result)` in an unshaded material, so Godot's final linear -> sRGB step gives back the
  original's value exactly (tonemap must stay linear). Alpha blending still happens in Godot's linear space (a
  small difference for the ~10 semi-transparent meshes).
- **Opaque (deferred):** material buffer `(Specularintensity * M.r, max(M.g, Specularpower / 255), Speculartint * M.b,
  max(M.a, Shadingreduction))` (material texture M: r intensity, g power, b tint, a shading reduction); per light
  (up to 4, the first 4 entries, enabled only): Lambert + Blinn specular with power `g * 255 + 1`;
  `color * lerp(LI + Ambient, 1, sr) + Specular * LI`. Color adjustment (HSV) applies to the albedo before lighting.
  A diffuse alpha below 0.001 leaves the pixel unlit (discard).
- **Alpha (`HasAlpha`: Alpha < 1 or TextureSemiTransparency): forward path**, first light only, per-vertex halfway,
  power `max(M.g * 255, Specularpower) + 1` with texture / `Specularpower` without; adjustment after lighting.
- **Shading reduction override**: `TMeshComponent` sets `ShadingReductionOverride` to the client option
  `coEngineGlobalShadingReduction`, default 0.5, used when the mesh's own ShadingReduction is 0; it also makes
  every unit mesh "have material settings".
- Not yet: fur (18), outline, normal maps (none of the 200 descriptors uses one), shadow mapping (the original's own,
  first light only). The glow stage: see "Post effects".
- The shader is a **template**, never `#include`d: TMesh composes each variant (below) and puts `shader_type`,
  the render mode and the flag defines in front: `GBUFFER` (+ `DRAW_COLOR/NORMAL/MATERIAL`) for opaque meshes (lit
  by the ported deferred pass at the end), `ROL_ALPHA` for the forward path, `DIFFUSETEXTURE`, `MATERIAL`,
  `MATERIALTEXTURE`, `CULLNONE`, `ROL_SKINNING`; `ROL_GLOW_STAGE` (the glow pass, `_glow_flags`) and
  `ROL_EFFECTS_STAGE` (own passes of the effects stage, `_effects_flags`). The fragment keeps the original's
  `pso.Color` / `pso.MaterialBuffer` / `pso.NormalBuffer` as `pso_*` locals so effect blocks port line by line.
- **Headless Godot does not compile shaders.** `tests/check_shaders.gd` (run by the test runner with a window)
  builds all ~1400 mesh variants and the post effect shaders and fails on any that does not parse.

## Mesh effects
`TMeshEffect*` (`src/runtime/components/t_mesh_effect*.gd`, `BaseConflict.EntityComponents.Client.Visuals.pas`) change
how a mesh is drawn. **Shader composition** (`TShader`, `t_shader.gd` = `Engine.GfxApi.pas` LoadShader / ParseBlocks /
ApplyBlocks): the standard shader has named sections (a line holding the block keyword starts one, so comments never
name it); an effect's shader file overrides sections, `#inherited` = what it replaces. The block files are walked
last to first, so the first custom shader is outermost; a block without `#inherited` drops what it replaces (as
`SpawnShader_Blue.fx` does with `vs_worldposition`). The ported block files are `src/runtime/graphics/effect_shaders/
<original file name lowercased>.gdshaderinc`, hand ports of the `.fx` (same blocks; `vs_worldposition` works on
`Worldposition` in game space, `pos` is the model-space vertex).

**On the mesh** (`TMesh`): `CustomShader` is the RMeshShader list (shader name, SetUp, own-pass stages, pass count,
hides the original, blend mode, owning effect), sorted by the effects' order values (spawn 1, tint 5000, matcap 9993,
hide and glow 9997, glow 9998, soul gain 9999, metal 10000). `ApplyMaterial` builds one `next_pass` chain: the main
material from the list's non-own-pass shaders, per shader drawn in own passes `OwnPasses` materials with only that
shader (cull none) in the world stage, then in the effects stage (blended by the blend mode, no z write), then the
glow pass and the glow stage's own passes (see "Post effects"); an `OwnPassHideOriginal` shader drops the main one
(and the glow pass). Each frame `SetUpCustomShaders` calls the SetUps with each material's stage:
`ShaderBinding.SetShaderConstant` / `SetTexture` (slots `tsVariable1..3` = `variable_texture_1..3`). The raw mesh's
smoothed normals ride in `CUSTOM2` (`SMOOTHED_NORMAL`).

**Stack** (`TMeshComponent.AddMeshEffect` / `RemoveMeshEffect` / `Idle`): one effect per class is mounted at a time,
others wait; expired ones go each frame; when a mounted one goes, the next waiting one of its class mounts, but only
if the removed one had no own passes (as written). `TMeshEffectComponent` gives managed clones to its group's meshes
(at once unless it waits for die / fire: `ActivateOnLose` effects run at creation too, as written) and takes them back
when freed. Textures: `import_graphics.py` copies `Graphics/Effects/Textures` matcaps, spawn mask, glow textures and
`Effects/Metal` to `assets/graphics/effects/`, and every image a script passes to a `TMeshEffect*.Create` (masks such
as `PatronSaintSpawnMask.tga`) from every folder holding that file (all skins).

Ported: Matcap (nexus / tower crystals: `MatcapCrystal<team>.png`), Metal (the snapshot has only White, Blue, Generic:
green / black / red metal units get no texture, the original warns too), Spawn (every drop: `Modifiers\Drop.dws`; white,
colorless, green, black, black legendary, blue with 20 own passes in the world and glow stages; red uses white;
`OverrideEffectTime` is undone by `InitializeOnMesh`, as written; a mesh without a glow texture gets its color's
`<Color>Glow.tga` meanwhile: flat color, alpha 0, so only the spawn shader's alpha term glows), Tint, Glow
(`GlowOvershoot.fx`, glow override too), HideAndGlow (two timelines, a mask), SoulGain (an own pass in the effects
stage). Deviations: the default order value (the class's RTTI address) is a name hash; timekeys at a time before every
key read uninitialized values in the original, the port takes the first key. Not yet: Ghost, Warp, Wobble, Ice,
Stone, Void, Spherify, Invisible (still stubs: they sit on the stack without a shader).

**Death decay** (`TUnitDecayManagerComponent`, `TClientGame.DecayManager`): on `eiDie` a client unit or building
(`udHasDeathEffect`, set by `UnitTemplate` / `BuildingTemplate`) pops its effects and hands its mesh over; the mesh
plays `death` (no script makes one, so every pose freezes) and draws with only `DeathShader.fx` (swell, fly apart
along the smoothed normals, flatten, noise holes, glow color `GLOW_COLOR_MAP` of its color identity) or, black,
`DeathShader_Black.fx` (noise holes, darkening) for 500 ms, then is freed. The noise takes the game space position.
Map viewer capture: `--play=... --death-burst=N` shoots N frames at the first death.

Unused effects: ColorOverlay, TeamColor (`ApplyTeamColoring`), SlidingTexture, SoulExtract, SpawnerSpawn
(`docs/unused-features.md`).

## Post effects
`TPostEffectManager` (`src/runtime/graphics/t_post_effect_manager.gd`, `Engine.PostEffects.pas`) runs the original's
post effect stack. **The stack** is `PostEffects.fxs`, converted by `tools/convert_post_effects.py` into
`src/content/post_effects.json` (checked by the test runner); the client then fires `OPTIONS_POSTEFFECTS`, so SSAO,
Toon, Glow, FXAA, UnsharpMasking and Distortion follow `coGraphicsPostEffect*` (defaults: SSAO off, the rest on);
ColorCorrection and Outline are always on, Bloom and the Draw* debug views off. `ToArray` = the dictionary's values
(`DelphiDictionary` slot order) sorted by RenderOrder with `DelphiSort`: Toon (1, stage rsWorldPostEffects), then in
rsPostEffects Glow (2), FXAA (7), UnsharpMasking (8), ColorCorrection / Distortion (10, hash order), Outline (11).

**The Godot pipeline.** The camera renders the 3D world into `WorldViewport` (a SubViewport; the root viewport draws
no 3D). Each pass is a SubViewport drawing a full ColorRect with a canvas shader (`src/runtime/graphics/post_effects/`)
over earlier textures; a pass's inputs are its descendants and Godot draws child viewports first, so one frame runs
the chain in order (checked: without effects the result is pixel-identical to drawing directly). The last texture is
shown under the UI (a CanvasLayer at -1). All targets are 8 bit (the original's A8R8G8B8, clamping between passes) and
hold the gamma-space values (the 3D output is converted to sRGB before 2D, see "Shading"), so the passes compute on the
original's values. The map viewer installs it (`--post-effects=off` / `none` for comparison captures).

**Glow stage (rsGlow).** `GlowViewport` has a second camera on the same world, synced to the main one before each
frame. It lacks cull layer 20 (`GLOW_LAYER_BIT`), which every other camera has by default; the shaders test
`CAMERA_VISIBLE_LAYERS` for it (`ROL_GLOW_CAMERA`). Under the glow camera terrain, vegetation, water and the meshes'
world passes draw black (the scene depth the original z-tests the glow against), a mesh with a glow pass leaves its
world pass out (`glow_replaces`) and the glow pass draws instead: `GenerateShaderBitmask(rsGlow)` = the glow texture
as diffuse, ALPHA, no lighting, the effect blocks in their non-G-buffer branch, the SetUps called with rsGlow. The
original alpha-blends it (SrcAlpha / InvSrcAlpha) onto the black-cleared target without z write; the port draws it
opaque with z write as `rgb * a` (the same over black; where glowing surfaces overlap with alpha < 1 the front one
wins). Own passes in the glow stage blend without z write (linear / additive / reverse subtractive; D3D's subtract has
no Godot mode). Other cameras never draw glow variants. Dump the buffer with `--dump-glow=on`.

**Ported effects.** Glow: the glow buffer blurred by `TTextureBlur` (Kernelsize 4, 2 iterations, spread 0.68,
Anamorphic 4.56 = y spread x 1.44, intensity 0.32, additive: `GAUSS_4_ADDITIVE`, which brightens ~1.6x per pass),
the last pass added onto the scene. UnsharpMasking: the scene blurred (normal kernel, spread 0.12, 1 iteration) and
`scene + (scene - blurred) * 0.36`. ColorCorrection: `pow(saturate((c - 0) / 0.956), 1.008)`. Blur passes: per
iteration i a vertical pass (`pixelwidth = (i + 1 + SpreadX) / width`) then a horizontal one, linear clamped sampling.
FXAA (`fxaa.gdshader`): FXAA 3.11's PC path as compiled there (HLSL 4: no gather, green as luma, discard = keep the
scene), preset 12 (`fmDither`, Quality 2: steps 1, 1.5, 2, 4, 12; `FXAA_PRESETS` holds all), the stack's
SubPixelQuality 0.436 and both edge thresholds 0 (no early exit; a flat cross divides by zero: DX11's saturate gives
0 for NaN, 1 for inf, written out). Not yet: Distortion (nothing draws in rsDistortion yet: particles), Outline (the
outline stage: hover highlights). The mesh viewer draws without post effects.

**G-buffer camera and Toon.** The stack's Toon is `ttBorder`: dark borders where the G-buffer's surface jumps, no
cel lighting. `GBufferViewport` (HDR, so 16 bit float like the original's normal buffer; values pass raw, checked)
has a third camera without cull layer 19 (`GBUFFER_LAYER_BIT`, `ROL_GBUFFER_CAMERA`, `toon.gdshaderinc`). Under it
what the original draws into its G-buffer in rsWorld (opaque mesh variants incl. world own passes, terrain,
vegetation) writes `rol_gbuffer_encode`: r = distance to the camera, g / b = octahedral normal in 0..1, g + 2 when the
8 bit shading reduction is at least `BorderShadingReductionThreshold` (all the border pass uses), b + 2 marks drawn
pixels; the rest (water, alpha meshes, effects-stage and glow passes) is not drawn. `black_border.gdshader` ports
`PosteffectBlackBorder.fx`: per iteration an x then a y pass (offsets `BorderSpread` / size: 0.384 px, point
sampled), the first on the white-cleared buffer; samples count where the depth is within `Range` (0.56) and the
normals face the same half space (`NormalBias` 0); a sample with a high shading reduction keeps the input (lerp by
the count, extrapolating). In captures flat ground stays border-free (neighbours within range), while palms, units,
buildings, rocks and dune silhouettes get 1-2 px lines. The last pass is a child of `WorldViewport` (drawn first) and becomes the global
`rol_toon_border`. The original draws `PosteffectToon.fx` over the scene after the deferred pass, before rsEffects;
the port applies it in the world shaders' own fragments (`rol_toon`: `lerp(border_color, color, pow(border,
gradient))`, skipped where `Color.a - 0.1 + (1 - factor) < 0` as the clip keeps the scene), which is the same since
the visible opaque fragment is what the scene holds; water's screen texture (copied after the opaque pass) thus sees
the borders like the original's Scene. Globals: `rol_toon_enabled` (off without the manager, e.g. the mesh viewer),
`rol_toon_border`, `_color`, `_gradient`, `_threshold` (`project.godot`). Map viewer: `--effects-off=Toon,FXAA`,
`--dump-toon=on` (the border buffer). Where nothing opaque is drawn (off the map) the original would still draw
border color at silhouettes over the background; the port does not.

## Lighting
`TLightManager` (`src/runtime/map/t_light_manager.gd`) ports `BaseConflict.Map.Client.pas`: ambient and
directional lights from the map's `.lig` (converted into the map JSON's `Lights` by `tools/convert_maps.py`),
directions normalized; `ShaderParameters()` / `SynchronizeLightWithGFXD()` push them as the `rol_*` global shader
parameters (declared in `project.godot`): ambient premultiplied by its w, directions negated (to the light) and
mapped to Godot space, colors rgb + intensity a.

## Maps
`TClientMap` (`src/runtime/map/t_client_map.gd`, `BaseConflict.Map.Client.pas`) loads a map's lights, terrain, water
and vegetation. Both maps (Classic, Single) have all three. Which scenario uses which map
(`BaseConflict.Constants.Scenario.pas`): **Single** (one lane) has the normal 1v1..4v4 PvP, ranked 1v1 / 2v2, the
tutorial and the solo PvE attack; **Classic** (two lanes) the "two lane" PvP variants, ranked 3v3 / 4v4, the duo
PvE attack and the Classic sandbox.

**Build grid** (`TBuildGridManagerComponent`, made after the scenario scripts set the build zones): per free field a
`Gameplay\Buildgrid\Buildgrid1..4` tile (random, random 90 degree turn, 0.04 under the ground, scale 2 / 1.84 +
0.08) with `GlowOvershoot.fx` at 0.032: with the glow effect on, the additive glow blur turns that into a clearly
turquoise tile (the glow texture is flat cyan, alpha 0); with glow off the original tints 0.4 instead. A wave spawn
(`eiWaveSpawn`, sent by the server) fades its tile out over 1 s along (0, -2.38, 0.58, 1), which first flashes it
~1.7x; when every field of the zone has spawned they all glow in over 0.5 s. **Where nothing is drawn** the water
reads position (0, 0, 0) (the original's cleared position buffer) and the scene shows the clear color `$23373C`; the
sea past the terrain's edge then turns bright cyan, as the original's formula does, outside the game camera's range.

**Decorations.** Given the client's global bus, `TClientMap.CreateFromFile` also creates the map's decorations, last,
like the original: `<Map>.bcc` `SavedDecorations` (converted to `<map>.decorations.json` by
`import_map_graphics.py`; Classic 54: bridges `Bridge11..333`, 16 `BridgePart1`, 24 `BridgePart2`, `Stones1`, 7
ambient sound emitters that draw nothing; Single 30), each `TEntity.CreateFromScript(ScriptFilename)` on the client
bus, placed by `UpdateDecoEntity` (position, display position / front / up, `eiSize` = the description's size), then
`eiAfterCreate`. `Stones1` has size 0 in the file and is drawn at size zero, like the original. The scenario scripts'
client part adds more (`Game.ClientMap.AddDecoEntity`: the PvE nexus ground). Script paths like
`\Environment\Bridge11.ets` start with a backslash; Windows takes the doubled separator after `\Scripts\` as one, and
so does the port's script lookup.

**Import.** `tools/import_map_graphics.py` (run by `import_graphics.py`) writes `assets/graphics/maps/<map>/`:
`<map>.terrain.json` + `.terrain.bin`, `<map>.water.json`, `<map>.vegetation.json` (compact), the chunk textures, and
copies every referenced file to its lowercased game-root path (`TClientMap.ResolveGamePath`: `Graphics\X` ->
`assets/graphics/x`, `\Maps\X` -> `assets/graphics/maps/x`). Gotchas of the formats:
- The `.ter` grid is `[XMLRawData]`: the original's own base64 (alphabet `0-9A-Za-z+/`, decoding stops at the first
  other character, `Engine.Helferlein.Windows.pas DecodeBase64`), then zlib, then the serializer's raw array format
  (per level a Boolean "has array children" and an Int32 length, then the children or the raw singles).
  `GridData[x][y]`, x-major, 513 x 513 for both maps.
- The engine cache `.tex` of every chunk texture is identical to its PNG (checked), so the PNGs are used.
- Release builds load the vegetation meshes from the raw `.msh` next to the FBX (`LOAD_RAW_MESH`, as every mesh):
  `TEngineRawMesh` reads it; its stored bounding sphere sizes the palms.

**Winding.** Everything is mirrored into Godot space (x negated, see "Space"), and the original's index order is
kept unchanged: D3D's clockwise front faces (left-handed) remain Godot's front faces. Reversing the triangles (what
the mirror seemed to ask for) culled the terrain from above; `test_map_graphics.gd` checks the first triangle faces up.

**Terrain** (`t_terrain.gd`, `terrain.gdshader`). Size 513 (SetGridSize), local node positions in -0.5..0.5, world =
local * Scale + Position (Classic: Scale 300, 50, 300). Normals: ComputeNormal, then SmoothNormal in place in the
original's loop order (x outer, y inner: later nodes see smoothed neighbours). One mesh per chunk texture
(TextureSplits 2: chunk = row * 4 + column, row = grid y, column = grid x; uv 0..1 per chunk, clamped). The shader is
Standardshader with NORMALMAPPING (rows Tangent, Normal, Binormal; normal texture `.rbg * 2 - 1`), MATERIAL +
MATERIALTEXTURE (Specularpower 0, Specularintensity 1, Speculartint never set: 0, ShadingReduction from the file),
through the deferred light pass. The chunk textures' material alpha (shading reduction) is non-zero only in the two
base chunks; the outer ring of chunks is authored in a paler sand than the middle band (a visible band edge in
overviews; it is in the data). Deviation: drawn at full detail; the geomipmapping LoD (`TQuadTreeNode.getLoDLevel`,
Geomipmapdistanceerror / normalerror from the file) is not ported. Loading takes about 1.5 s in GDScript.

**Water** (`t_water_surface.gd`, `t_water_manager.gd`, `water.gdshader`). A 200 x 200 grid; Watershader with
DEFERRED_SHADING, REFLECTIONS, REFRACTION, CAUSTICS (no sky texture). The original ray-marches the G-buffer's
position buffer and samples the lit scene: the port reconstructs positions from Godot's depth texture, takes the
scene from the screen texture (back to gamma space) and the scene normal's y from the normal-roughness texture
(Forward+ only). All shading math runs in game space. Note: `mul(float3x3(Tangent, Normal, Binormal), normal)` in the
water shader dots the rows (unlike Standardshader's `mul(normal, matrix)`); ported as written. Beyond the terrain's
edge the depth is the far plane and the water turns white; the game camera never looks there.

**Vegetation** (`t_vegetation_manager.gd`, `vegetation.gdshader`, C++ `DelphiRandom`). Classic:
3428 palms (`TVegetationMesh`) + 1207 grass tufts (`TGrassTuft`); `TTree` is unused. Each object replays its rolls:
`RandSeed := FRandSeed`, then Delphi's `Random` in the original's call order (palms: `Random(MeshCount)`, three
rotation rolls x, y, z even with zero variance, one size roll; tufts: rotation, angle, two size rolls, trapezial,
time offset). `DelphiRandom` is the Win32 RTL generator (`RandSeed * $08088405 + 1`, unsigned seed / 2^32).
Palm transform `Translation * RotationPitchYawRoll * Scaling(Size.Random * Scale / (radius * 2))` with the original's
matrices (`RotationY(Yaw) * RotationX(Pitch) * RotationZ(Roll)`, see `RotationPitchYawRoll`). Palms are MultiMesh
instances, tufts one mesh; wind sway in the vertex shader from the vertex's custom vector (the palms' vertex colors).
All parts are alpha tested (0.5), two-sided without normal flipping, lit as color * (light + ambient).

## Viewers
`src/viewer/mesh_viewer.tscn` (button on the main scene): every imported mesh with the Classic lights, filterable
list, orbit camera, frame slider / play, unit shading toggle. Capture mode for checks without a person:
`Godot --path . res://src/viewer/mesh_viewer.tscn -- --capture=<substr,...> --capture-out=<abs dir>` writes two
views per mesh and steps every frame (errors show in the log); add `--turntable=<frames>` for numbered video frames.
All 201 meshes load from their `.msh` and pose without errors.

`src/viewer/map_viewer.tscn` (button on the main scene): a scenario's battlefield through the game camera's geometry
(`TClientCameraComponent.ApplyCamera`: eye = target + zoom * 10 * CAMERAOFFSET.Normalize, vertical field of view
0.6853981635 rad, near 1, far 10000, game zoom 2.6..3.8). Three scenarios: the 1 lane sandbox (Single, the default),
the 2 lane sandbox (Classic) and the PvE sandbox (Single, golem base on its nexus ground). Each runs live as a game:
a server `TGameThread` runs the scenario scripts, a `TClientGame` joins it over the in-process network
(`JoinLocal`, `docs/game-loop.md` "Network"), loads the map with its decorations, runs the scenario's client part and
receives the server's entities and events. Server frames every 32 ms, a client frame per drawn frame
(`GFXD.MainScene` is its entities node). Card buttons (blue / red footmen drop, blue / red footman spawner) play the
sandbox deck's cards through the client's commanders (after the 10 s warm-up). Layer toggles (Terrain, Water,
Vegetation, Entities), named views per map. Capture mode:
`-- --capture-out=<abs dir> [--maps=Single,Classic] [--hide=...] [--view=x,z,zoom[,rotation]] [--play=<button
labels>] [--wait=ms]` writes each named view per scenario (`--play` once the game has started, then `--wait` ms of
game). The test runner's second launcher smoke test opens it through `play.bat` and checks decorations, entities and
drawn meshes. `play.bat` runs a quick headless `--import` first (about 2 s): without it a new `class_name` since the
last import left the class cache stale and the viewers failed to compile (a black window).
