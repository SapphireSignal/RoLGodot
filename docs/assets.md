# Assets (phase 4)

How the original's graphics get into the port, and how they are drawn. Facts about the original's formats:
`original-architecture.md` ("Assets and formats").

## Setup
`assets/graphics/` is generated, git-ignored and needs `reference/`:

    python tools/import_graphics.py          # ~270 MB, idempotent (only changed files are rewritten)
    Godot --headless --path . --import       # tools/run_tests.ps1 does this too

`tools/run_tests.ps1` runs `import_graphics.py --check` (every descriptor resolves). The export includes
`assets/graphics/*.json` (descriptors) besides the imported resources; `import/` (editor-only) is excluded.

## Meshes
`tools/import_graphics.py` walks every mesh descriptor `Graphics/**/*.xml` (200, all `TMesh`) and writes, with
**lowercased paths** (the original's references differ in case from the files; the port lowercases every graphics
path, `TMesh.ResolveDescriptor`):
- `<name>.mesh.json`: the descriptor: every published `TRawMesh` property, defaults from
  `SetDefaultMaterialSettings` for missing ones, texture names resolved in the descriptor's folder. The old
  `Specular` element of 10 descriptors has no property and is skipped, like the deserializer does.
- the FBX (copied) and a `.fbx.import` with fixed settings: no LODs, no vertex compression, 30 fps, **no animation
  trimming** (script frame ranges count from the file's first frame), embedded images discarded,
  `import/fbx_post_import.gd` as post-import script.
- each referenced texture, copied (`.tga` / `.png`) or decoded from the engine cache `.tex` when no source image
  exists (KTF: `decode_ktf`, pixel-identical to the source TGA where both exist), with a `.import` (lossless,
  mipmaps: the original generates mipmaps).

**Units.** The FBX files are all Y-up with standard axes but mixed `UnitScaleFactor` (2.54, 100, 200, 0.1). The
original's old assimp ignores it and uses the raw numbers; Godot converts to meters by `UnitScaleFactor / 100`.
The importer sets `nodes/root_scale = 100 / UnitScaleFactor`, so the port sees raw file units (the Footman is
~90 units tall), which the scripts' size factors expect (`SIZE_FACTOR_3DSMAX = 2 / 125`, `eiModelSize`).
`tools/fbx_info.py` reads FBX files (binary and ASCII) to check such facts (`--all` lists every file).

**NaN bones.** ForestGuardian, MeleeGolemTower and AttackBoss animate a `...Stone` bone whose rotation curves and
default rotation are NaN in the file itself. In the original the bone matrix turns NaN and the GPU drops those
triangles: the stone is never drawn. `import/fbx_post_import.gd` gives such bones an identity rotation and a
vanishing scale, which draws the same nothing without NaN errors. (Godot still logs NaN errors while importing
these three files; the imported result is clean.)

**Space.** The original loads right-handed FBX data unchanged into its left-handed world and mirrors X in the
world matrix. The port maps game space (x, y, z) to Godot (-x, y, z) (`TMesh.ToGodot`); the two mirrors cancel,
so imported FBX scenes are used as they are and `TMesh.ComputeTransformationMatrix` conjugates the base:
`basis = G * Base(Left, Up, Front) * G * Scaling`, `G = diag(-1, 1, 1)`. (Pitch/yaw/roll rotation of TMesh waits for
the TMeshComponent port.)

**Animations.** One take per file ("Take 001"), 30 fps. `TMesh.ShowFrame(frame)` shows a frame as the scripts'
`CreateNewAnimation(name, start, end)` count them. The script-defined animation slices, blending and speeds come
with `TMeshComponent` / `TAnimationComponent` (phase 5).

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
- Not yet: glow stage (144 descriptors have a glow texture; needs the bloom post effect), fur (18), outline,
  normal maps (none of the 200 descriptors uses one), shadow mapping (the original's own, first light only).

## Lighting
`TLightManager` (`src/runtime/map/t_light_manager.gd`) ports `BaseConflict.Map.Client.pas`: ambient and
directional lights from the map's `.lig` (converted into the map JSON's `Lights` by `tools/convert_maps.py`),
directions normalized; `ShaderParameters()` / `SynchronizeLightWithGFXD()` push them as the `rol_*` global shader
parameters (declared in `project.godot`): ambient premultiplied by its w, directions negated (to the light) and
mapped to Godot space, colors rgb + intensity a.

## Viewer
`src/viewer/mesh_viewer.tscn` (button on the main scene): every imported mesh with the Classic lights, filterable
list, orbit camera, frame slider / play, unit shading toggle. Capture mode for checks without a person:
`Godot --path . res://src/viewer/mesh_viewer.tscn -- --capture=<substr,...> --capture-out=<abs dir>` writes two
views per mesh and steps every frame (errors show in the log); add `--turntable=<frames>` for numbered video frames.
All 200 meshes load and play without errors.
