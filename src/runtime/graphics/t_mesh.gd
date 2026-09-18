class_name TMesh
extends Node3D
## Engine.Mesh.pas TMesh / TRawMesh: one mesh, loaded from its descriptor (the original's XML, converted to
## <name>.mesh.json by tools/import_graphics.py) with the FBX geometry Godot imported. Read docs/assets.md.
##
## Space: the original loads the right-handed FBX data unchanged into its left-handed world and mirrors X in the
## world matrix ("all meshes are loaded mirrored along x-axis, so now mirror back"). The port maps a game position
## (x, y, z) to Godot (-x, y, z) (ToGodot), which makes that mirror and the port's mapping cancel: the imported FBX
## is used as is. Materials: one ShaderMaterial (standard_shader.gdshaderinc) on every surface, as the original
## collapses all subsets into one and draws it with one material.

const GRAPHICS_ROOT := "res://assets/graphics/"
const DESCRIPTOR_SUFFIX := ".mesh.json"
const SHADER_INCLUDE := "res://src/runtime/graphics/standard_shader.gdshaderinc"
## The FBX take and its frame rate (Engine.AssetLoader.AssimpLoader: FTimeCorrectionFactor = 1000 / 30).
const FRAMES_PER_SECOND := 30.0

static var _shaders := {}

## Descriptor fields (TRawMesh published properties).
var FileName := ""
var GeometryFile := ""
var DiffuseTexture := ""
var NormalTexture := ""
var MaterialTexture := ""
var GlowTexture := ""
var FurTexture := ""
var TextureSemiTransparency := false
var Cullmode := "cmCCW"
var Alpha := 1.0
var AlphaTestTreshold := 0.0
var SpecularIntensity := 0.0
var SpecularPower := 128.0
var SpecularTint := 1.0
var ShadingReduction := 0.0
var Outline := false
var OnlyOutline := false
var OutlineColor := Color(0, 0, 0, 0)
var Descriptor := {}

## Runtime state (not in the descriptor).
var ShadingReductionOverride := 0.0
var ColorAdjustment := Vector3.ZERO
var AbsoluteHSV := Vector3.ZERO
var ColorOverride := Color(0, 0, 0, 0)

## Game-space placement (TMesh.Position / Front / Up / ScaleImbalanced).
var Position := Vector3.ZERO
var Front := Vector3(0, 0, 1)
var Up := Vector3(0, 1, 0)
var ScaleVector := Vector3.ONE

var Model: Node3D
var MeshInstances: Array[MeshInstance3D] = []
var AnimationPlayerNode: AnimationPlayer
var MeshMaterial: ShaderMaterial


## Game space (left-handed, the original's world) to Godot space. See the class comment.
static func ToGodot(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## "Units\White\Footman_Default\Footman.xml" (relative to Graphics\, any case, either slash) -> descriptor path.
static func ResolveDescriptor(mesh_path: String) -> String:
	var path := mesh_path.replace("\\", "/").to_lower()
	while path.contains("//"):
		path = path.replace("//", "/")
	path = path.trim_prefix("/").trim_prefix("graphics/")
	return GRAPHICS_ROOT + path.get_basename() + DESCRIPTOR_SUFFIX


static func Exists(mesh_path: String) -> bool:
	return FileAccess.file_exists(ResolveDescriptor(mesh_path))


## TMesh.CreateFromFile: mesh_path as the scripts write it (relative to Graphics\) or a res:// descriptor path.
static func CreateFromFile(mesh_path: String) -> TMesh:
	var descriptor_path := mesh_path if mesh_path.begins_with("res://") else ResolveDescriptor(mesh_path)
	var text := FileAccess.get_file_as_string(descriptor_path)
	if text == "":
		push_error("TMesh.CreateFromFile: can't find mesh %s (%s)" % [mesh_path, descriptor_path])
		return null
	var mesh := TMesh.new()
	mesh.name = descriptor_path.get_file().trim_suffix(DESCRIPTOR_SUFFIX)
	mesh._load(descriptor_path, JSON.parse_string(text))
	return mesh


func _load(descriptor_path: String, data: Dictionary) -> void:
	FileName = descriptor_path
	Descriptor = data
	var folder := descriptor_path.get_base_dir() + "/"
	GeometryFile = data.GeometryFile
	DiffuseTexture = data.DiffuseTexture
	NormalTexture = data.NormalTexture
	MaterialTexture = data.MaterialTexture
	GlowTexture = data.GlowTexture
	FurTexture = data.FurTexture
	TextureSemiTransparency = data.TextureSemiTransparency
	Cullmode = data.Cullmode
	Alpha = data.Alpha
	AlphaTestTreshold = data.AlphaTestTreshold
	SpecularIntensity = data.SpecularIntensity
	SpecularPower = data.SpecularPower
	SpecularTint = data.SpecularTint
	ShadingReduction = data.ShadingReduction
	Outline = data.Outline
	OnlyOutline = data.OnlyOutline
	var oc: Array = data.OutlineColor
	OutlineColor = Color(oc[0], oc[1], oc[2], oc[3])
	var scene := load(folder + GeometryFile) as PackedScene
	if scene == null:
		push_error("TMesh: can't load geometry %s" % (folder + GeometryFile))
		return
	Model = scene.instantiate() as Node3D
	add_child(Model)
	_collect(Model)
	MeshMaterial = ShaderMaterial.new()
	for mi in MeshInstances:
		mi.material_override = MeshMaterial
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ApplyMaterial()
	ComputeTransformationMatrix()


func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		MeshInstances.append(node)
	elif node is AnimationPlayer and AnimationPlayerNode == null:
		AnimationPlayerNode = node
	for child in node.get_children():
		_collect(child)


func _texture(file: String) -> Texture2D:
	if file == "":
		return null
	var path := FileName.get_base_dir() + "/" + file
	if not ResourceLoader.exists(path):
		# TRawMesh.Set*Texture logs "Can't find texture" and draws without it.
		push_warning("TMesh: can't find texture %s" % path)
		return null
	return load(path) as Texture2D


## TRawMesh.HasAlpha
func HasAlpha() -> bool:
	return Alpha < 1.0 or TextureSemiTransparency


## TRawMesh.HasMaterialSettings
func HasMaterialSettings() -> bool:
	return MaterialTexture != "" or SpecularIntensity > 0.0 or ShadingReduction > 0.0 or ShadingReductionOverride > 0.0


## TRawMesh.HasColorOverride: replaces the diffuse if it is not transparent black.
func HasColorOverride() -> bool:
	return ColorOverride.a > 0.0 or ColorOverride.r > 0.0 or ColorOverride.g > 0.0 or ColorOverride.b > 0.0


## Pushes the material settings to the shader (TRawMesh.GenerateShaderBitmask + Render's SetUpShader, world and
## effects stages).
func ApplyMaterial() -> void:
	if MeshMaterial == null:
		return
	MeshMaterial.shader = _shader_for(Cullmode, HasAlpha())
	var diffuse := _texture(DiffuseTexture)
	var material := _texture(MaterialTexture)
	MeshMaterial.set_shader_parameter("has_diffuse_texture", diffuse != null)
	MeshMaterial.set_shader_parameter("diffuse_texture", diffuse)
	MeshMaterial.set_shader_parameter("has_material_texture", material != null)
	MeshMaterial.set_shader_parameter("material_texture", material)
	MeshMaterial.set_shader_parameter("has_material_settings", HasMaterialSettings())
	MeshMaterial.set_shader_parameter("specular_intensity", SpecularIntensity)
	MeshMaterial.set_shader_parameter("specular_power", SpecularPower)
	MeshMaterial.set_shader_parameter("specular_tint", SpecularTint)
	MeshMaterial.set_shader_parameter("shading_reduction", ShadingReduction if ShadingReduction > 0.0 else ShadingReductionOverride)
	MeshMaterial.set_shader_parameter("forward_path", HasAlpha())
	MeshMaterial.set_shader_parameter("use_alpha", HasAlpha())
	MeshMaterial.set_shader_parameter("alpha", Alpha)
	MeshMaterial.set_shader_parameter("alpha_test_ref", AlphaTestTreshold)
	MeshMaterial.set_shader_parameter("replacement_color", ColorOverride if HasColorOverride() else Color(0, 0, 0, 0))
	MeshMaterial.set_shader_parameter("color_adjustment", ColorAdjustment != Vector3.ZERO)
	MeshMaterial.set_shader_parameter("absolute_color_adjustment", ColorAdjustment != Vector3.ZERO and AbsoluteHSV != Vector3.ZERO)
	MeshMaterial.set_shader_parameter("hsv_offset", ColorAdjustment)
	MeshMaterial.set_shader_parameter("absolute_hsv", AbsoluteHSV)


## One compiled shader per render-mode combination.
static func _shader_for(cullmode: String, has_alpha: bool) -> Shader:
	var key := "%s|%s" % [cullmode, has_alpha]
	if _shaders.has(key):
		return _shaders[key]
	var cull := "cull_back"
	if cullmode == "cmNone":
		cull = "cull_disabled"
	elif cullmode == "cmCW":
		cull = "cull_front"
	var modes := "unshaded, %s, %s" % [cull, "blend_mix, depth_draw_opaque" if has_alpha else "depth_draw_opaque"]
	var code := "shader_type spatial;\nrender_mode %s;\n%s#include \"%s\"\n" % [modes, "#define ROL_ALPHA\n" if has_alpha else "", SHADER_INCLUDE]
	var shader := Shader.new()
	shader.code = code
	_shaders[key] = shader
	return shader


## TMesh.ComputeTransformationMatrix: Translation(Position) * Base(Left, Up, Front) * Scaling, then the X mirror.
## In Godot space the mirror and ToGodot conjugate the base: basis = G * Base * G * Scaling, G = diag(-1, 1, 1).
func ComputeTransformationMatrix() -> void:
	var left := Up.cross(Front).normalized()
	var up := Front.cross(left).normalized()
	var base := Basis.IDENTITY
	if left != Vector3.ZERO and up != Vector3.ZERO and Front != Vector3.ZERO:
		base = Basis(left, up, Front)
	var g := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	transform = Transform3D(g * base * g * Basis.from_scale(ScaleVector), ToGodot(Position))


func SetPosition(value: Vector3) -> void:
	Position = value
	ComputeTransformationMatrix()


func SetScale(value: float) -> void:
	ScaleVector = Vector3(value, value, value)
	ComputeTransformationMatrix()


## Names of the animations in the file (the FBX take, usually "Take 001").
func AnimationNames() -> PackedStringArray:
	return AnimationPlayerNode.get_animation_list() if AnimationPlayerNode else PackedStringArray()


## Frames in the file's take at 30 fps.
func FrameCount() -> int:
	var names := AnimationNames()
	if names.is_empty():
		return 0
	return roundi(AnimationPlayerNode.get_animation(names[0]).length * FRAMES_PER_SECOND)


## Shows one frame of the file's take (frame numbers as CreateNewAnimation counts them).
func ShowFrame(frame: float) -> void:
	var names := AnimationNames()
	if names.is_empty():
		return
	if AnimationPlayerNode.current_animation != names[0]:
		AnimationPlayerNode.play(names[0])
		AnimationPlayerNode.pause()
	AnimationPlayerNode.seek(frame / FRAMES_PER_SECOND, true)


## Bounds of the geometry as currently posed (skinned on the CPU), in file units, untransformed by this node.
## For tools (the viewer's framing); slow on big meshes.
func GetPosedBoundingBox() -> AABB:
	var box := AABB()
	var first := true
	for mi in MeshInstances:
		var to_root := _to_root(mi)
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var skin := mi.skin
		var bind_matrices: Array[Transform3D] = []
		if skeleton and skin:
			var skeleton_to_mesh := to_root.affine_inverse() * _to_root(skeleton)
			for b in skin.get_bind_count():
				var bone := skin.get_bind_bone(b)
				if bone < 0:
					bone = skeleton.find_bone(skin.get_bind_name(b))
				var pose := skeleton.get_bone_global_pose(bone) if bone >= 0 else Transform3D.IDENTITY
				bind_matrices.append(skeleton_to_mesh * pose * skin.get_bind_pose(b))
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: Variant = arrays[Mesh.ARRAY_BONES]
			var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
			var skinned: bool = not bind_matrices.is_empty() and bones != null and weights != null and not verts.is_empty()
			var per := (bones as PackedInt32Array).size() / verts.size() if skinned else 0
			for v in verts.size():
				var p := verts[v]
				if skinned:
					var q := Vector3.ZERO
					for k in per:
						var w: float = weights[v * per + k]
						if w > 0.0:
							q += (bind_matrices[bones[v * per + k]] * p) * w
					p = q
				p = to_root * p
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
	return box


func _to_root(node: Node3D) -> Transform3D:
	var t := node.transform
	var parent := node.get_parent()
	while parent != null and parent != self:
		if parent is Node3D:
			t = (parent as Node3D).transform * t
		parent = parent.get_parent()
	return t


## Untransformed bounding box of the geometry (TMesh.GetUntransformedBoundingBox), in file units.
func GetUntransformedBoundingBox() -> AABB:
	var box := AABB()
	var first := true
	for mi in MeshInstances:
		var t := mi.transform
		var parent := mi.get_parent()
		while parent != null and parent != self:
			if parent is Node3D:
				t = (parent as Node3D).transform * t
			parent = parent.get_parent()
		var b := t * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
