class_name TPostEffectManager
extends Node
## Port of TPostEffectManager (Engine/Engine.PostEffects.pas:73, implementation :1574) and the post effects it runs,
## with the render targets the original's render context gives them, built from Godot viewports. Read docs/assets.md,
## "Post effects".
##
## The stack is PostEffects.fxs (src/content/post_effects.json, tools/convert_post_effects.py); the client then fires
## the post effect options (TClientSettingsComponent.HandleOption: SSAO, Toon, Glow, FXAA, UnsharpMasking, Distortion
## follow coGraphicsPostEffect*). Render walks the enabled effects of a stage in ToArray order: the dictionary's
## values (Delphi's TDictionary slot order) sorted by RenderOrder with Delphi's unstable sort.
##
## Godot side: the 3D world renders into WorldViewport (the camera moves there; the root viewport draws no 3D). Every
## pass is a SubViewport drawing a ColorRect with the pass's shader over the previous passes' textures; a pass's
## inputs are its descendants, and Godot draws child viewports before their parents, so the whole chain runs in one
## frame. The final texture is shown under the UI. All targets are 8 bit like the original's A8R8G8B8 targets, and
## the 2D passes work on the gamma-space values the 3D output holds (see docs/assets.md, "Shading").
## The glow stage (rsGlow) is a second camera on the same world (GlowViewport) whose cull mask lacks GLOW_LAYER_BIT
## (every other camera has it by default): the shaders draw black under it, glowing meshes their glow pass
## (TMesh.ApplyMaterial).
## The G-buffer (what rsWorld draws with the GBUFFER flag: normal, distance to the camera, shading reduction) is a third
## camera (GBufferViewport, HDR: 16 bit float like the original's normal buffer) whose cull mask lacks
## GBUFFER_LAYER_BIT: the world shaders write their packed G-buffer under it (toon.gdshaderinc), the rest is not drawn.
## The Toon effect (rsWorldPostEffects) blurs its border buffer from it; the world shaders then apply the result to
## their own fragments (the scene before the effects stage), through the rol_toon_* global shader parameters.
##
## Ported: Toon (ttBorder, the stack's type), Glow, FXAA, UnsharpMasking, ColorCorrection. Not yet: Distortion (no
## contributors are drawn yet: particles), Outline (the outline stage), SSAO (off by default). Bloom and the Draw*
## debug views are disabled in the stack.

const C = preload("res://src/runtime/dws/dws_const.gd")
const SOURCE := "res://src/content/post_effects.json"
const SHADER_ROOT := "res://src/runtime/graphics/post_effects/"
## Layer 20, in every camera's cull mask but the glow camera's: shaders test CAMERA_VISIBLE_LAYERS for it (524288u).
## Nothing is drawn on it.
const GLOW_LAYER_BIT := 1 << 19
## Layer 19, in every camera's cull mask but the G-buffer camera's (262144u in the shaders). Nothing is drawn on it.
const GBUFFER_LAYER_BIT := 1 << 18
## Shaderglobals.fx GAUSS_0..4 and GAUSS_0..4_ADDITIVE (KERNELSIZE + 2 weights each)
const GAUSS := [[0.44198, 0.27901], [0.250301, 0.221461, 0.153388], [0.214607, 0.189879, 0.131514, 0.071303],
	[0.20236, 0.179044, 0.124009, 0.067234, 0.028532], [0.198596, 0.175713, 0.121703, 0.065984, 0.028002, 0.0093]]
const GAUSS_ADDITIVE := [[1.0, 0.63127], [1.0, 0.88478, 0.61281], [1.0, 0.88478, 0.61281, 0.33224],
	[1.0, 0.88478, 0.61281, 0.33224, 0.14099], [1.0, 0.88478, 0.61281, 0.33224, 0.14099, 0.04683]]
## FXAA.fx's quality presets: FXAA_QUALITY__PRESET -> the search steps FXAA_QUALITY__P0.. (their count is
## FXAA_QUALITY__PS)
const FXAA_PRESETS := {
	10: [1.5, 3.0, 12.0], 11: [1.0, 1.5, 3.0, 12.0], 12: [1.0, 1.5, 2.0, 4.0, 12.0],
	13: [1.0, 1.5, 2.0, 2.0, 4.0, 12.0], 14: [1.0, 1.5, 2.0, 2.0, 2.0, 4.0, 12.0],
	15: [1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 12.0],
	20: [1.5, 2.0, 8.0], 21: [1.0, 1.5, 2.0, 8.0], 22: [1.0, 1.5, 2.0, 2.0, 8.0], 23: [1.0, 1.5, 2.0, 2.0, 2.0, 8.0],
	24: [1.0, 1.5, 2.0, 2.0, 2.0, 3.0, 8.0], 25: [1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0],
	26: [1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0], 27: [1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0],
	28: [1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0],
	29: [1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0],
	39: [1.0, 1.0, 1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0]}
## EnumRenderStage values of the post effects' stages
const RS_WORLD_POST_EFFECTS := 6
const RS_POST_EFFECTS := 9
## Effect UID -> the client option that switches it (OPTIONS_POSTEFFECTS)
const OPTIONS := {"SSAO": C.coGraphicsPostEffectSSAO, "Toon": C.coGraphicsPostEffectToon,
	"Glow": C.coGraphicsPostEffectGlow, "FXAA": C.coGraphicsPostEffectFXAA,
	"UnsharpMasking": C.coGraphicsPostEffectUnsharpMasking, "Distortion": C.coGraphicsPostEffectDistortion}
## Effect classes the port draws, and the classes' render stages (the TPostEffect constructors' FStage)
const PORTED := ["TPostEffectToon", "TPostEffectGlow", "TPostEffectFXAA", "TPostEffectUnsharpMasking",
	"TPostEffectColorCorrection"]
const STAGES := {"TPostEffectToon": RS_WORLD_POST_EFFECTS, "TPostEffectSSAO": RS_WORLD_POST_EFFECTS}


## TTextureBlur's settings (Engine.Core.pas:230) as the effects' published properties set them.
class TTextureBlur:
	var Kernelsize := 4
	var ResDiv := 1        # FResDiv = 1 shl (ResolutionDivider - 1)
	var Iterations := 1
	var SampleSpread := 1.0
	var Intensity := 1.0
	var Anamorphic := 0.0  # FTextureBlur.Anamorphic = the property - 5
	var AdditiveBlur := false

	static func FromFields(Fields: Dictionary) -> TTextureBlur:
		var Blur := TTextureBlur.new()
		Blur.Kernelsize = clampi(int(Fields.get("Kernelsize", 4)), 0, 4)
		Blur.ResDiv = 1 << (int(Fields.get("ResolutionDivider", 1)) - 1)
		Blur.Iterations = int(Fields.get("Iterations", 1))
		Blur.SampleSpread = float(Fields.get("SampleSpread", 1.0))
		Blur.Intensity = float(Fields.get("Intensity", 1.0))
		Blur.Anamorphic = float(Fields.get("Anamorphic", 5.0)) - 5.0
		Blur.AdditiveBlur = bool(Fields.get("AdditiveBlur", false))
		return Blur

	func Kernel() -> Array:
		return (GAUSS_ADDITIVE if AdditiveBlur else GAUSS)[Kernelsize]

	## RenderBlur's passes: per iteration a vertical then a horizontal pass, [pixelwidth, pixelheight] each, for a
	## Width x Height screen.
	func Passes(Width: int, Height: int) -> Array:
		var result := []
		if Iterations <= 0:
			return result
		var SpreadX := SampleSpread
		if Anamorphic > 0:
			SpreadX = SpreadX * (1 + Anamorphic)
		var SpreadY := SampleSpread
		if Anamorphic < 0:
			SpreadY = SpreadY * (1 - Anamorphic)
		for i in maxi(0, Iterations - 1) + 1:
			result.append([(i + 1 + SpreadX) / float(Width / ResDiv), 0.0])
			result.append([0.0, (i + 1 + SpreadY) / float(Height / ResDiv)])
		return result


## [UID, class name, fields] per effect in ToArray order.
var FEffects: Array = []
var Camera: Camera3D = null
var WorldViewport: SubViewport = null
var GlowViewport: SubViewport = null
var GlowCamera: Camera3D = null
var GBufferViewport: SubViewport = null
var GBufferCamera: Camera3D = null
## TPostEffectToon's BlurredScene2: the border buffer the world shaders read (null without Toon)
var ToonBorder: Texture2D = null
## The global shader parameters this manager set last (headless Godot does not keep them)
var ShaderGlobals := {}
var _chain_root: SubViewport = null
var _display: TextureRect = null
var _size := Vector2i.ZERO


## Moves Camera into the pipeline's world viewport and shows the chain's result under the UI of Host's viewport.
func Create(Host: Node, Camera_: Camera3D) -> TPostEffectManager:
	name = "PostEffects"
	Camera = Camera_
	LoadFromFile(SOURCE)
	Host.add_child(self)
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	_display = TextureRect.new()
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_display)
	get_viewport().disable_3d = true
	Rebuild()
	get_viewport().size_changed.connect(Rebuild)
	RenderingServer.frame_pre_draw.connect(_sync_cameras)
	return self


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_cameras):
		RenderingServer.frame_pre_draw.disconnect(_sync_cameras)
	_set_global("rol_toon_enabled", false)
	if get_viewport() != null:
		get_viewport().disable_3d = false


## LoadFromFile: the effects in file order into a Delphi dictionary; ToArray: its values sorted by RenderOrder.
func LoadFromFile(Path: String) -> void:
	var Items: Array = JSON.parse_string(FileAccess.get_file_as_string(Path))
	var Dictionary_ := DelphiDictionary.new().Create(DelphiHash.StringHash,
		func(Left: String, Right: String) -> bool: return Left == Right)
	for Item: Dictionary in Items:
		Dictionary_.Add(Item.Key, [Item.Key, Item.Class, Item.Fields])
	FEffects = []
	var Slot := Dictionary_.NextSlot(-1)
	while Slot >= 0:
		FEffects.append(Dictionary_.ValueAt(Slot))
		Slot = Dictionary_.NextSlot(Slot)
	DelphiSort.Sort(FEffects, func(Left: Array, Right: Array) -> int:
		return int(Left[2].RenderOrder) - int(Right[2].RenderOrder))


## TPostEffect.Enabled after the option events: the stack's value, or the client option for the switchable ones.
func IsEnabled(Effect: Array) -> bool:
	if OPTIONS.has(Effect[0]):
		return TOptionManager.GetBooleanOption(OPTIONS[Effect[0]])
	return bool(Effect[2].Enabled)


## The enabled effects the port draws, in render order (world post effects first, then the post effects).
func ActiveEffects() -> Array:
	var result := []
	for Stage in [RS_WORLD_POST_EFFECTS, RS_POST_EFFECTS]:
		for Effect: Array in FEffects:
			if IsEnabled(Effect) and STAGES.get(Effect[1], RS_POST_EFFECTS) == Stage and Effect[1] in PORTED:
				result.append(Effect)
	return result


## Builds the viewports for the current window size and effect switches.
func Rebuild() -> void:
	_size = get_window().size if get_window() != null else Vector2i(1600, 900)
	if Camera.get_parent() != null:
		Camera.get_parent().remove_child(Camera)
	if _chain_root != null:
		_chain_root.queue_free()
		_chain_root = null
	WorldViewport = _viewport("World")
	WorldViewport.add_child(Camera)
	Camera.current = true
	Camera.cull_mask |= GLOW_LAYER_BIT | GBUFFER_LAYER_BIT
	GlowViewport = null
	GlowCamera = null
	GBufferViewport = null
	GBufferCamera = null
	ToonBorder = null
	_set_global("rol_toon_enabled", false)
	var Scene: Texture2D = WorldViewport.get_texture()
	var Producers: Array = [WorldViewport]
	for Effect: Array in ActiveEffects():
		match Effect[1]:
			"TPostEffectToon":
				_toon(Effect[2])
			"TPostEffectGlow":
				var Result := _glow(Scene, Producers, Effect[2])
				Scene = Result[0]
				Producers = Result[1]
			"TPostEffectFXAA":
				var Pass := _pass("FXAA", FXAAMaterial(Effect[2], Scene), Producers)
				Scene = Pass.get_texture()
				Producers = [Pass]
			"TPostEffectUnsharpMasking":
				var Result := _unsharp_masking(Scene, Producers, Effect[2])
				Scene = Result[0]
				Producers = Result[1]
			"TPostEffectColorCorrection":
				var Material := _material("color_correction.gdshader")
				Material.set_shader_parameter("color_texture", Scene)
				Material.set_shader_parameter("shadows", float(Effect[2].Shadows))
				Material.set_shader_parameter("midtones", float(Effect[2].Midtones))
				Material.set_shader_parameter("lights", float(Effect[2].Lights))
				var Pass := _pass("ColorCorrection", Material, Producers)
				Scene = Pass.get_texture()
				Producers = [Pass]
	# the last producer holds the chain
	_chain_root = Producers[0]
	for i in range(1, Producers.size()):
		_chain_root.add_child(Producers[i])
	add_child(_chain_root)
	_display.texture = Scene


func _viewport(Name_: String) -> SubViewport:
	var Viewport_ := SubViewport.new()
	Viewport_.name = Name_
	Viewport_.size = _size
	Viewport_.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Viewport_.transparent_bg = false
	Viewport_.msaa_3d = Viewport.MSAA_DISABLED
	Viewport_.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	Viewport_.use_hdr_2d = false
	return Viewport_


func _material(ShaderFile: String) -> ShaderMaterial:
	var Material := ShaderMaterial.new()
	Material.shader = load(SHADER_ROOT + ShaderFile)
	return Material


## A pass: a viewport drawing Material over its whole area; Producers (the viewports whose textures it reads) become
## its children so they are drawn first.
func _pass(Name_: String, Material: ShaderMaterial, Producers: Array) -> SubViewport:
	var Viewport_ := _viewport(Name_)
	var Rect := ColorRect.new()
	Rect.material = Material
	Rect.position = Vector2.ZERO
	Rect.size = Vector2(_size)
	Viewport_.add_child(Rect)
	for Producer: Node in Producers:
		Viewport_.add_child(Producer)
	return Viewport_


## TTextureBlur.RenderBlur of Input: the passes' viewports; the last pass adds onto Base when AddToBase (the additive
## blur's One / One blend onto the current target). Returns [texture, producers].
func _blur(Name_: String, Blur: TTextureBlur, Input: Texture2D, InputProducers: Array, Base: Texture2D,
		BaseProducers: Array, AddToBase: bool) -> Array:
	var Kernel: Array = Blur.Kernel()
	var Weights := PackedFloat32Array(Kernel)
	Weights.resize(6)
	var Texture_ := Input
	var Producers := InputProducers
	var Passes := Blur.Passes(_size.x, _size.y)
	for i in Passes.size():
		var Material := _material("gaussian_blur.gdshader")
		Material.set_shader_parameter("color_texture", Texture_)
		Material.set_shader_parameter("pixelwidth", Passes[i][0])
		Material.set_shader_parameter("pixelheight", Passes[i][1])
		Material.set_shader_parameter("intensity", Blur.Intensity)
		Material.set_shader_parameter("kernel", Weights)
		Material.set_shader_parameter("kernel_length", Kernel.size())
		var Last := i == Passes.size() - 1
		if Last and AddToBase:
			Material.set_shader_parameter("add_to_base", true)
			Material.set_shader_parameter("base_texture", Base)
		var Pass := _pass("%s%d" % [Name_, i], Material, Producers + (BaseProducers if Last else []))
		Texture_ = Pass.get_texture()
		Producers = [Pass]
	if Passes.is_empty() and AddToBase:
		return [Base, BaseProducers]
	return [Texture_, Producers]


## The G-buffer camera's viewport (built once per Rebuild, on first use): the world stage's packed G-buffer.
func _gbuffer() -> Texture2D:
	if GBufferViewport == null:
		GBufferViewport = _viewport("GBuffer")
		GBufferViewport.use_hdr_2d = true
		GBufferCamera = _synced_camera("GBufferCamera", Camera.cull_mask & ~GBUFFER_LAYER_BIT)
		GBufferViewport.add_child(GBufferCamera)
		GBufferCamera.current = true
		_sync_cameras()
	return GBufferViewport.get_texture()


## A camera of an extra stage: black background (the cleared targets), the linear tonemap (values pass unchanged).
func _synced_camera(Name_: String, CullMask: int) -> Camera3D:
	var Camera_ := Camera3D.new()
	Camera_.name = Name_
	Camera_.cull_mask = CullMask
	var Environment_ := Environment.new()
	Environment_.background_mode = Environment.BG_COLOR
	Environment_.background_color = Color(0, 0, 0)
	Environment_.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	Camera_.environment = Environment_
	return Camera_


## TPostEffectToon.Render (ttBorder): BlurredScene2 cleared white, then per border iteration the border shader along x
## (pixelwidth = BorderSpread / width) into BlurredScene and along y back into BlurredScene2, against the G-buffer. The
## last pass is drawn before the world (a child of WorldViewport), whose shaders apply it (rol_toon_*).
func _toon(Fields: Dictionary) -> void:
	if str(Fields.get("ToonType", "ttBoth")) != "ttBorder":
		push_warning("TPostEffectManager: Toon type %s is not ported (the stack uses ttBorder)" % Fields.ToonType)
		return
	if int(Fields.BorderIterations) <= 0:
		# BlurredScene2 stays cleared white: no border
		return
	var GBuffer := _gbuffer()
	var Spread := float(Fields.BorderSpread)
	var Texture_: Texture2D = null
	var Producers: Array = [GBufferViewport]
	for i in int(Fields.BorderIterations):
		for Direction in 2:
			var Material := _material("black_border.gdshader")
			Material.set_shader_parameter("clear_input", Texture_ == null)
			Material.set_shader_parameter("color_texture", Texture_)
			Material.set_shader_parameter("gbuffer_texture", GBuffer)
			Material.set_shader_parameter("pixelwidth", Spread / _size.x if Direction == 0 else 0.0)
			Material.set_shader_parameter("pixelheight", Spread / _size.y if Direction == 1 else 0.0)
			Material.set_shader_parameter("range", float(Fields.Range))
			Material.set_shader_parameter("normalbias", float(Fields.NormalBias))
			Material.set_shader_parameter("border_threshold", float(Fields.BorderShadingReductionThreshold))
			var Pass := _pass("ToonBorder%d%s" % [i, "xy"[Direction]], Material, Producers)
			Texture_ = Pass.get_texture()
			Producers = [Pass]
	WorldViewport.add_child(Producers[0])
	ToonBorder = Texture_
	var Color_: Array = Fields.BorderColor
	_set_global("rol_toon_border", Texture_)
	_set_global("rol_toon_border_color", Vector3(Color_[0], Color_[1], Color_[2]))
	_set_global("rol_toon_border_gradient", float(Fields.BorderGradient))
	_set_global("rol_toon_border_threshold", float(Fields.BorderShadingReductionThreshold))
	_set_global("rol_toon_enabled", true)


func _set_global(Name_: String, Value: Variant) -> void:
	ShaderGlobals[Name_] = Value
	RenderingServer.global_shader_parameter_set(Name_, Value)


## TPostEffectGlow.Render: the glow stage into its own target (cleared black, meshes z-tested against the scene),
## blurred additively onto the scene.
func _glow(Scene: Texture2D, Producers: Array, Fields: Dictionary) -> Array:
	GlowViewport = _viewport("Glow")
	GlowCamera = _synced_camera("GlowCamera", Camera.cull_mask & ~GLOW_LAYER_BIT)
	GlowViewport.add_child(GlowCamera)
	GlowCamera.current = true
	_sync_cameras()
	var Blur := TTextureBlur.FromFields(Fields)
	Blur.AdditiveBlur = true
	return _blur("GlowBlur", Blur, GlowViewport.get_texture(), [GlowViewport], Scene, Producers, true)


## TPostEffectFXAA.BuildShader's preset: Mode fmDither "1" + min(5, Quality), fmLessDither "2" + Quality, fmNoDither 39.
static func FXAAPreset(Fields: Dictionary) -> int:
	var Quality := int(Fields.get("Quality", 2))
	match str(Fields.get("Mode", "fmDither")):
		"fmLessDither":
			return 20 + Quality
		"fmNoDither":
			return 39
	return 10 + mini(5, Quality)


## TPostEffectFXAA.Render: FXAA.fx over the scene (linear, clamped), pixel size 1 / resolution.
func FXAAMaterial(Fields: Dictionary, Scene: Texture2D) -> ShaderMaterial:
	var Steps: Array = FXAA_PRESETS[FXAAPreset(Fields)]
	var P := PackedFloat32Array(Steps)
	P.resize(12)
	var Material := _material("fxaa.gdshader")
	Material.set_shader_parameter("color_texture", Scene)
	Material.set_shader_parameter("pixelwidth", 1.0 / _size.x)
	Material.set_shader_parameter("pixelheight", 1.0 / _size.y)
	Material.set_shader_parameter("subpixel_quality", float(Fields.get("SubPixelQuality", 0.75)))
	Material.set_shader_parameter("edge_threshold", float(Fields.get("EdgeThreshold", 0.166)))
	Material.set_shader_parameter("edge_threshold_min", float(Fields.get("EdgeThresholdMin", 0.0833)))
	Material.set_shader_parameter("quality_ps", Steps.size())
	Material.set_shader_parameter("quality_p", P)
	return Material


## TPostEffectUnsharpMasking.Render: the scene blurred into BlurredScene, then scene + (scene - blurred) * Amount.
func _unsharp_masking(Scene: Texture2D, Producers: Array, Fields: Dictionary) -> Array:
	var Blur := TTextureBlur.FromFields(Fields)
	# the scene's producers are drawn by the blur's first pass already; the combine pass reads the same texture
	var Blurred := _blur("UnsharpBlur", Blur, Scene, Producers, null, [], false)
	var Material := _material("unsharp_masking.gdshader")
	Material.set_shader_parameter("color_texture", Scene)
	Material.set_shader_parameter("normal_texture", Blurred[0])
	Material.set_shader_parameter("amount", float(Fields.Amount))
	var Pass := _pass("UnsharpMasking", Material, Blurred[1])
	return [Pass.get_texture(), [Pass]]


## The glow and G-buffer cameras see what the main camera sees, right before each frame is drawn.
func _sync_cameras() -> void:
	if Camera == null or not is_instance_valid(Camera) or not Camera.is_inside_tree():
		return
	for Camera_: Camera3D in [GlowCamera, GBufferCamera]:
		if Camera_ == null or not Camera_.is_inside_tree():
			continue
		Camera_.global_transform = Camera.global_transform
		Camera_.fov = Camera.fov
		Camera_.near = Camera.near
		Camera_.far = Camera.far
		Camera_.projection = Camera.projection
		# a Node3D's transform reaches the renderer with the scene tree's transform notifications, which run in the
		# next frame when set this late: the stage would draw from the last frame's camera (outlines and glow trailing
		# the picture while the view moves). The renderer takes it now.
		RenderingServer.camera_set_transform(Camera_.get_camera_rid(), Camera.global_transform)
