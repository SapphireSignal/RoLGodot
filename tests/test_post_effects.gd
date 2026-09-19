extends "res://tests/test_case.gd"
## The post effect stack (TPostEffectManager, docs/assets.md "Post effects"): PostEffects.fxs as loaded, the effects
## the options switch, TTextureBlur's passes, and the glow stage's materials on meshes (TMesh.ApplyMaterial). The
## drawing itself is checked in captures (map viewer --dump-glow=on).

const C = preload("res://src/runtime/dws/dws_const.gd")

var _free: Array = []


func after_each() -> void:
	for obj in _free:
		if obj is TMesh:
			TMesh.Release(obj)
		else:
			obj.Free()
	_free.clear()
	TTimeManager.FakeTime = null
	TOptionManager.ResetOptions()
	super()


func _has_assets() -> bool:
	if TMesh.Exists("Units\\White\\Footman_Default\\Footman.xml") and ResourceLoader.exists("res://assets/graphics/effects/textures/whiteglow.tga"):
		return true
	print("  (assets/graphics missing: run python tools/import_graphics.py)")
	return false


func _manager() -> TPostEffectManager:
	var manager := TPostEffectManager.new()
	manager.LoadFromFile(TPostEffectManager.SOURCE)
	return manager


## The stack as the client has it after the option events: the 13 effects of PostEffects.fxs in RenderOrder; SSAO is
## off by its option's default; of the enabled ones the port draws Toon (1, rsWorldPostEffects), Glow (2), FXAA (7),
## UnsharpMasking (8), ColorCorrection (10).
func test_stack_and_options() -> String:
	var manager := _manager()
	check_eq(manager.FEffects.size(), 13, "13 effects")
	var orders: Array = manager.FEffects.map(func(e: Array) -> int: return int(e[2].RenderOrder))
	var sorted := orders.duplicate()
	sorted.sort()
	check_eq(orders, sorted, "sorted by RenderOrder")
	var enabled: Array = manager.FEffects.filter(func(e: Array) -> bool: return manager.IsEnabled(e)).map(
		func(e: Array) -> String: return e[0])
	check(not enabled.has("SSAO"), "SSAO off (coGraphicsPostEffectSSAO defaults to False)")
	check(not enabled.has("Bloom") and not enabled.has("DrawColor"), "Bloom and the debug views are off in the file")
	for uid in ["Toon", "Glow", "FXAA", "UnsharpMasking", "ColorCorrection", "Distortion", "Outline"]:
		check(enabled.has(uid), "%s on" % uid)
	check_eq(manager.ActiveEffects().map(func(e: Array) -> String: return e[0]),
		["Toon", "Glow", "FXAA", "UnsharpMasking", "ColorCorrection"], "drawn by the port, in order")
	TOptionManager.SetOption(C.coGraphicsPostEffectGlow, "False")
	TOptionManager.SetOption(C.coGraphicsPostEffectFXAA, "False")
	check_eq(manager.ActiveEffects().map(func(e: Array) -> String: return e[0]),
		["Toon", "UnsharpMasking", "ColorCorrection"], "the glow and FXAA options switch them off")
	manager.free()
	return take_failure()


## TPostEffectFXAA as the stack sets it: fmDither with Quality 2 compiles preset 12 (5 search steps 1, 1.5, 2, 4,
## 12); the stack's SubPixelQuality 0.436 and zero edge thresholds replace the constructor's defaults. Other modes:
## fmDither caps the quality digit at 5, fmLessDither takes it as it is, fmNoDither is 39.
func test_fxaa_preset() -> String:
	var manager := _manager()
	manager._size = Vector2i(1600, 900)
	var fields := {}
	for effect: Array in manager.FEffects:
		fields[effect[0]] = effect[2]
	check_eq(TPostEffectManager.FXAAPreset(fields.FXAA), 12, "preset")
	var material := manager.FXAAMaterial(fields.FXAA, null)
	check_eq(material.get_shader_parameter("quality_ps"), 5, "5 steps")
	var steps: PackedFloat32Array = material.get_shader_parameter("quality_p")
	check_eq(Array(steps.slice(0, 5)), [1.0, 1.5, 2.0, 4.0, 12.0], "search steps")
	check_near(material.get_shader_parameter("subpixel_quality"), 0.435999989509583, 1e-7, "sub pixel quality")
	check_eq(material.get_shader_parameter("edge_threshold"), 0.0, "edge threshold")
	check_eq(material.get_shader_parameter("edge_threshold_min"), 0.0, "edge threshold min")
	check_near(material.get_shader_parameter("pixelwidth"), 1.0 / 1600.0, 1e-9, "pixel width")
	check_eq(TPostEffectManager.FXAAPreset({"Mode": "fmDither", "Quality": 9}), 15, "dither caps at 15")
	check_eq(TPostEffectManager.FXAAPreset({"Mode": "fmLessDither", "Quality": 9}), 29, "less dither")
	check_eq(TPostEffectManager.FXAAPreset({"Mode": "fmNoDither", "Quality": 2}), 39, "no dither")
	for preset: int in TPostEffectManager.FXAA_PRESETS:
		check(TPostEffectManager.FXAA_PRESETS[preset].size() <= 12, "preset %d fits the step array" % preset)
	manager.free()
	return take_failure()


## TPostEffectToon as the stack sets it (ttBorder, 1 iteration, spread 0.384, range 0.56, normal bias 0, threshold 0.7):
## the G-buffer camera (HDR viewport, without the G-buffer layer bit), two border passes (x then y, the first on the
## cleared white buffer) drawn before the world, and the rol_toon_* globals the world shaders apply. Built as Rebuild
## does, on a manager outside the tree (the runner has none).
func test_toon_border_passes() -> String:
	var manager := _manager()
	var camera := Camera3D.new()
	manager.Camera = camera
	manager._size = Vector2i(1600, 900)
	camera.cull_mask |= TPostEffectManager.GLOW_LAYER_BIT | TPostEffectManager.GBUFFER_LAYER_BIT
	manager.WorldViewport = manager._viewport("World")
	var fields := {}
	for effect: Array in manager.FEffects:
		fields[effect[0]] = effect[2]
	manager._toon(fields.Toon)
	check(manager.GBufferViewport != null and manager.GBufferViewport.use_hdr_2d, "HDR G-buffer viewport")
	var bit := TPostEffectManager.GBUFFER_LAYER_BIT
	check(camera.cull_mask & bit != 0 and camera.cull_mask & TPostEffectManager.GLOW_LAYER_BIT != 0,
		"the main camera has both stage bits")
	check(manager.GBufferCamera.cull_mask & bit == 0, "the G-buffer camera lacks its bit")
	check(manager.GBufferCamera.cull_mask & TPostEffectManager.GLOW_LAYER_BIT != 0, "but draws the world variants")
	var size := Vector2(manager.WorldViewport.size)
	var x_pass := manager.WorldViewport.find_child("ToonBorder0x", true, false) as SubViewport
	var y_pass := manager.WorldViewport.get_node_or_null("ToonBorder0y") as SubViewport
	check(x_pass != null and y_pass != null, "two passes, the last one a child of the world viewport")
	if x_pass != null and y_pass != null:
		var x_material: ShaderMaterial = x_pass.get_child(0).material
		var y_material: ShaderMaterial = y_pass.get_child(0).material
		check(x_material.get_shader_parameter("clear_input"), "the first pass reads the cleared buffer")
		check(not y_material.get_shader_parameter("clear_input"), "the second the first's result")
		check_eq(y_material.get_shader_parameter("color_texture"), x_pass.get_texture(), "chained")
		check_near(x_material.get_shader_parameter("pixelwidth"), 0.38400000333786 / size.x, 1e-9, "x offset")
		check_eq(x_material.get_shader_parameter("pixelheight"), 0.0, "x pass: no y offset")
		check_near(y_material.get_shader_parameter("pixelheight"), 0.38400000333786 / size.y, 1e-9, "y offset")
		check_near(x_material.get_shader_parameter("range"), 0.560000002384186, 1e-7, "range")
		check_eq(x_material.get_shader_parameter("normalbias"), 0.0, "normal bias")
		check_near(x_material.get_shader_parameter("border_threshold"), 0.699999988079071, 1e-7, "threshold")
		check_eq(manager.ToonBorder, y_pass.get_texture(), "the border buffer is the last pass")
	var globals := manager.ShaderGlobals
	check_eq(globals.get("rol_toon_enabled"), true, "toon on")
	check_eq(globals.get("rol_toon_border"), manager.ToonBorder, "border buffer")
	var color: Vector3 = globals.get("rol_toon_border_color", Vector3.ZERO)
	check(color.is_equal_approx(Vector3(0.096000000834465, 0.164000004529953, 0.172000005841255)), "border color")
	check_near(globals.get("rol_toon_border_gradient", 0.0), 3.96799993515015, 1e-6, "gradient")
	check_near(globals.get("rol_toon_border_threshold", 0.0), 0.699999988079071, 1e-7, "threshold for the G-buffer camera")
	RenderingServer.global_shader_parameter_set("rol_toon_enabled", false)
	manager.WorldViewport.free()
	camera.free()
	manager.free()
	return take_failure()


## TTextureBlur.RenderBlur's passes: per iteration vertical then horizontal, offset (i + 1 + spread) pixels; the
## Anamorphic property is stored minus 5 and stretches the spread of one axis. Glow: spread 0.68, anamorphic -0.44
## (y * 1.44), 2 iterations, additive kernel GAUSS_4_ADDITIVE; UnsharpMasking: spread 0.12, anamorphic -0.12, 1 pass.
func test_blur_passes() -> String:
	var manager := _manager()
	var fields := {}
	for effect: Array in manager.FEffects:
		fields[effect[0]] = effect[2]
	var glow := TPostEffectManager.TTextureBlur.FromFields(fields.Glow)
	glow.AdditiveBlur = true
	var passes := glow.Passes(1600, 900)
	check_eq(passes.size(), 4, "2 iterations x 2")
	var spread := 0.680000007152557
	var spread_y := spread * (1.0 + 0.44000005722046)
	check_near(passes[0][0], (1.0 + spread) / 1600.0, 1e-9, "first vertical")
	check_eq(passes[0][1], 0.0, "only x")
	check_near(passes[1][1], (1.0 + spread_y) / 900.0, 1e-7, "first horizontal")
	check_near(passes[2][0], (2.0 + spread) / 1600.0, 1e-9, "second vertical")
	check_near(passes[3][1], (2.0 + spread_y) / 900.0, 1e-7, "second horizontal")
	check_eq(glow.Kernel(), TPostEffectManager.GAUSS_ADDITIVE[4], "additive kernel of size 4")
	var unsharp := TPostEffectManager.TTextureBlur.FromFields(fields.UnsharpMasking)
	check_eq(unsharp.Passes(1600, 900).size(), 2, "one iteration")
	check_eq(unsharp.Kernel(), TPostEffectManager.GAUSS[4], "normal kernel")
	check_near(unsharp.Passes(1600, 900)[1][1], (1.0 + 0.119999997317791 * 1.12000000476837) / 900.0, 1e-7, "anamorphic y")
	var sum := 0.0
	for i in unsharp.Kernel().size():
		sum += unsharp.Kernel()[i] * (1.0 if i == 0 else 2.0)
	check_near(sum, 1.0, 1e-5, "a normal kernel keeps the brightness")
	manager.free()
	return take_failure()


## A mesh with a glow texture draws its glow pass after the world pass (the glow texture as diffuse, ALPHA on); its
## world pass leaves the glow camera to it (glow_replaces). A mesh without one has no glow pass.
func test_glow_pass_materials() -> String:
	if not _has_assets():
		return ""
	var crystal := TMesh.CreateFromFile("Units\\Neutral\\Nexus\\NexusCrystal.xml")
	var footman := TMesh.CreateFromFile("Units\\White\\Footman_Default\\Footman.xml")
	_free.append(crystal)
	_free.append(footman)
	check(crystal.GlowMaterial != null, "the crystal glows")
	check(crystal.MeshMaterial.next_pass == crystal.GlowMaterial, "after the world pass")
	check_eq(crystal.MeshMaterial.get_shader_parameter("glow_replaces"), true, "the world pass leaves the glow camera")
	var glow_texture = crystal.GlowMaterial.get_shader_parameter("diffuse_texture")
	check(glow_texture is Texture2D and (glow_texture as Texture2D).resource_path.get_file() == "nexusglow.tga",
		"the glow texture is the glow pass's diffuse: %s" % glow_texture)
	check_eq(crystal.GlowMaterial.get_shader_parameter("use_alpha"), true, "ALPHA")
	check(crystal.GlowMaterial.shader.code.contains("#define ROL_GLOW_STAGE"), "the glow stage variant")
	check(not crystal.GlowMaterial.shader.code.contains("#define GBUFFER"), "unlit, no G-buffer")
	check(crystal.Materials().has(crystal.GlowMaterial), "bone matrices reach it")
	check(footman.GlowMaterial == null, "no glow texture, no glow pass")
	check_eq(footman.MeshMaterial.get_shader_parameter("glow_replaces"), false, "the footman is black under the glow camera")
	check(footman.MeshMaterial.next_pass == null, "only the world pass")
	return take_failure()


## A spawning unit without a glow texture gets its color's (WhiteGlow.tga for white) while the spawn effect runs:
## the glow pass carries the spawn shader too, set up with glow = 1 (the world pass: 0). When it expires, both go.
func test_spawn_effect_glows() -> String:
	if not _has_assets():
		return ""
	TTimeManager.FakeTime = 0.0
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = C.nsClient
	_free.append(bus)
	var entity := TEntity.new().Create(bus)
	_free.push_front(entity)
	entity.Eventbus.Write(C.eiColorIdentity, [C.ecWhite])
	var component := TMeshComponent.new().CreateGrouped(entity, [0], "Units\\White\\Footman_Default\\Footman.xml") as TMeshComponent
	var mesh := component.FMesh
	check(mesh.GlowMaterial == null, "no glow before")
	var spawn := TMeshEffectSpawn.new().Create()
	spawn.AssignToEntity(entity)
	check(mesh.GlowTexture.to_lower().ends_with("whiteglow.tga"), "WhiteGlow.tga while spawning: %s" % mesh.GlowTexture)
	check(mesh.GlowMaterial != null, "a glow pass")
	if mesh.GlowMaterial == null:
		return take_failure()
	check(mesh.GlowMaterial.shader.code.contains("uniform float glow;"), "with the spawn shader's blocks")
	mesh.SetUpCustomShaders()
	check_eq(mesh.GlowMaterial.get_shader_parameter("glow"), 1.0, "glow stage: glow 1")
	check_eq(mesh.MeshMaterial.get_shader_parameter("glow"), 0.0, "world stage: glow 0")
	TTimeManager.FakeTime = 2501.0
	component.Idle()
	check_eq(mesh.GlowTexture, "", "the glow texture goes with the effect")
	check(mesh.GlowMaterial == null, "and the glow pass")
	return take_failure()


## A white client entity with a mesh (the footman) for the effect tests.
func _footman(color: int) -> TMeshComponent:
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = C.nsClient
	_free.append(bus)
	var entity := TEntity.new().Create(bus)
	_free.push_front(entity)
	entity.Eventbus.Write(C.eiColorIdentity, [color])
	return TMeshComponent.new().CreateGrouped(entity, [0], "Units\\White\\Footman_Default\\Footman.xml") as TMeshComponent


## TMeshEffectGlow (GlowOvershoot.fx): the timeline's value as the overshoot, go_is_glow_stage 1 only on the glow
## pass, the glow color of the color identity (or FixedColorIdentity); it brings the glow override too.
func test_glow_effect() -> String:
	if not _has_assets():
		return ""
	TTimeManager.FakeTime = 0.0
	var component := _footman(C.ecGreen)
	var mesh := component.FMesh
	var glow: TMeshEffectGlow = TMeshEffectGlow.new().Create(1100).AddKey(0, 1.0).AddKey(250, 0.6).AddKey(1100, 0.0)
	glow.AssignToEntity(component.Owner)
	check(mesh.GlowTexture.to_lower().ends_with("greenglow.tga"), "green glow override")
	check(mesh.GlowMaterial != null, "a glow pass")
	if mesh.GlowMaterial == null:
		return take_failure()
	TTimeManager.FakeTime = 125.0
	mesh.SetUpCustomShaders()
	check_near(mesh.MeshMaterial.get_shader_parameter("go_overshoot"), 0.8, 1e-5, "overshoot from the keys")
	check_eq(mesh.MeshMaterial.get_shader_parameter("go_is_glow_stage"), 0.0, "world stage")
	check_eq(mesh.GlowMaterial.get_shader_parameter("go_is_glow_stage"), 1.0, "glow stage")
	var green := TMeshEffect.RColor(TMeshEffectSpawn.GLOW_COLOR_MAP[C.ecGreen])
	check(mesh.MeshMaterial.get_shader_parameter("go_color").is_equal_approx(Vector3(green.r, green.g, green.b)), "green glow color")
	var fixed: TMeshEffectGlow = TMeshEffectGlow.new().Create(-1).FixedColorIdentity(C.ecRed)
	var clone: TMeshEffectGlow = fixed.Clone(null)
	check(clone.FFixedColorIdentity and clone.FFixedColor == C.ecRed, "the clone keeps the fixed color")
	return take_failure()


## TMeshEffectHideAndGlow (HideAndGlow.fx): first timeline hag_overshoot, second hag_visibility, the mask texture in
## variable texture 3 (a script's skinned path, imported from every skin folder).
func test_hide_and_glow_effect() -> String:
	if not _has_assets():
		return ""
	TTimeManager.FakeTime = 0.0
	var component := _footman(C.ecWhite)
	var mesh := component.FMesh
	var effect: TMeshEffectHideAndGlow = TMeshEffectHideAndGlow.new().Create(3500, "\\Graphics\\Units\\White\\PatronSaint_Default\\PatronSaintSpawnMask.tga")
	effect.AddKey(0, 0.0).AddKey(2700, 0.0).AddKey(3300, 1.0).AddKey(3500, 0.0).AddNextTimeLine().AddKey(0, 0.0).AddKey(3500, 1.0)
	check(effect.FEffectTexture != null, "the mask is imported")
	effect.AssignToEntity(component.Owner)
	TTimeManager.FakeTime = 3000.0
	mesh.SetUpCustomShaders()
	check_near(mesh.MeshMaterial.get_shader_parameter("hag_overshoot"), 0.5, 1e-5, "first timeline")
	check_near(mesh.MeshMaterial.get_shader_parameter("hag_visibility"), 3000.0 / 3500.0, 1e-5, "second timeline")
	var mask = mesh.MeshMaterial.get_shader_parameter("variable_texture_3")
	check(mask is Texture2D and (mask as Texture2D).resource_path.get_file() == "patronsaintspawnmask.tga", "mask bound")
	check(mesh.GlowMaterial == null, "no glow override: the footman has no glow pass")
	return take_failure()


## TMeshEffectSoulGain (SoulGain.fx): one own pass in the effects stage (blended, additive when asked), not in the
## glow stage; progress, radius and the soul color reach it.
func test_soul_gain_effect() -> String:
	if not _has_assets():
		return ""
	TTimeManager.FakeTime = 0.0
	var component := _footman(C.ecWhite)
	var mesh := component.FMesh
	var effect: TMeshEffectSoulGain = TMeshEffectSoulGain.new().Create(400).Color(1090453400).Radius(0.5).AddKey(0, 0.0).AddKey(400, 1.0).Additive()
	effect.AssignToEntity(component.Owner)
	check_eq(mesh.EffectsOwnPassMaterials.size(), 1, "one own pass in the effects stage")
	if mesh.EffectsOwnPassMaterials.is_empty():
		return take_failure()
	var pass_material: ShaderMaterial = mesh.EffectsOwnPassMaterials[0][2]
	check(pass_material.shader.code.contains("blend_add") and pass_material.shader.code.contains("depth_draw_never"),
		"additive, no z write")
	check(pass_material.shader.code.contains("#define ROL_EFFECTS_STAGE"), "the effects stage variant")
	check(mesh.MeshMaterial.next_pass == pass_material, "drawn after the mesh")
	check(mesh.GlowOwnPassMaterials.is_empty(), "not in the glow stage")
	TTimeManager.FakeTime = 100.0
	mesh.SetUpCustomShaders()
	check_near(pass_material.get_shader_parameter("soul_gain_progress"), 0.25, 1e-5, "progress")
	check_near(pass_material.get_shader_parameter("soul_gain_radius"), 0.5, 1e-6, "radius")
	var color: Vector4 = pass_material.get_shader_parameter("soul_color")
	check(color.is_equal_approx(Vector4(0xFE / 255.0, 0xFF / 255.0, 0x98 / 255.0, 0x40 / 255.0)), "soul color $40FEFF98: %s" % color)
	return take_failure()
