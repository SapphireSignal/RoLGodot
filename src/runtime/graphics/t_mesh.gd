class_name TMesh
extends Node3D
## Engine.Mesh.pas TMesh / TRawMesh / TMeshAnimatedGeometry: one mesh, loaded from its descriptor (the original's XML,
## converted to <name>.mesh.json by tools/import_graphics.py) with the geometry release builds load: the engine's own
## raw mesh (.msh, LOAD_RAW_MESH) next to the FBX, read by TEngineRawMesh. Read docs/assets.md ("Meshes").
##
## Geometry: one surface with the raw vertices (file space), the original's index order, the morph targets as
## relative blend shapes (weights = the morph driver's weights / 100) and, for skinned meshes, the bone weights and
## indices in CUSTOM0 / CUSTOM1: the shader skins like Standardshader.fx (sum of weight * BoneTransforms[index]),
## BoneTransforms[i] = the skin link's bone CombinedMatrix * its BoneSpaceOffsetMatrix (TSkin.ComputeAnimatedMatrices).
## Bones: the raw bone hierarchy (TBone), animated by TSkinnedMeshAnimationDriver (PassAnimationToHierarchy).
##
## Space: the original loads the right-handed file data unchanged into its left-handed world and mirrors X in the
## world matrix ("all meshes are loaded mirrored along x-axis, so now mirror back"). The port maps a game position
## (x, y, z) to Godot (-x, y, z) (ToGodot), which makes that mirror and the port's mapping cancel: file coordinates
## are used as they are. Materials: one ShaderMaterial (standard_shader.gdshaderinc) per mesh.

const GRAPHICS_ROOT := "res://assets/graphics/"
const DESCRIPTOR_SUFFIX := ".mesh.json"
const SHADER_INCLUDE := "res://src/runtime/graphics/standard_shader.gdshaderinc"
## Frames per second of the files' takes (Engine.AssetLoader.AssimpLoader: FTimeCorrectionFactor = 1000 / 30).
const FRAMES_PER_SECOND := 30.0
## FBX_DEFAULT_ANIMATIONTRACK (BaseConflict.Constants.Client.pas): the name of the files' only take.
const FBX_DEFAULT_ANIMATIONTRACK := "AnimStack::Take 001"
## HW_MAX_BONES / MAX_BONES (Engine.Mesh.pas, Shaderglobals.fx)
const HW_MAX_BONES := 66
const MAX_MORPH_TARGET_COUNT := 8

## EnumRenderStage (Engine.Core.Types.pas) values the port uses: stages the mesh effects draw or set up in.
const RS_SHADOW := 3
const RS_WORLD := 5
const RS_EFFECTS := 7
const RS_GLOW := 11
## EnumTextureSlot (Engine.GfxApi.Types.pas) -> the template's sampler uniforms.
const TS_VARIABLE1 := 3
const TS_VARIABLE2 := 4
const TS_VARIABLE3 := 5
const TEXTURE_SLOT_UNIFORMS := {0: "diffuse_texture", 2: "material_texture", 3: "variable_texture_1",
	4: "variable_texture_2", 5: "variable_texture_3"}
## EnumBlendMode (Engine.Vertex.pas)
const BLEND_LINEAR := 0
const BLEND_ADDITIVE := 1
const BLEND_SUBTRACTIVE := 2
const BLEND_REVERSE_SUBTRACTIVE := 3

static var _shaders := {}
## TMeshAnimatedGeometry cache (the original's QueryDeviceForObject): .msh path -> TGeometry.
static var _geometries := {}


## TMeshAnimatedGeometry: the raw mesh, its Godot mesh and the bone hierarchy, shared by every mesh of a file.
class TGeometry:
	var Raw: TEngineRawMesh
	var Surface: ArrayMesh
	## TBone hierarchy flattened depth first (the file's order): names, OriginalMatrix, children, name lookup.
	var BoneNames := PackedStringArray()
	var BoneOriginal: Array[Transform3D] = []
	var BoneChildren: Array[PackedInt32Array] = []
	var BoneLookup := {}  # lower-case name -> index (GetBoneByName; a later duplicate wins, AddOrSetValue)
	var SkinBones := PackedInt32Array()  # per skin link: its bone
	var SkinOffsets: Array[Transform3D] = []
	var HasSkin := false
	var MorphtargetCount := 0


## RMeshShader (Engine.Mesh.pas): a custom shader of the mesh (a mesh effect's blocks), its SetUp (binding, stage,
## pass index), the stages it draws in own passes, how many, whether it hides the mesh's own drawing, its blend mode
## (own passes outside the world stage) and its owner (the effect).
class RMeshShader:
	var ShaderName := ""
	var SetUp := Callable()
	var NeedsOwnPass: Array = []
	var OwnPasses := 0
	var OwnPassHideOriginal := false
	var BlendMode := 0
	var Tag: Object = null

	func _init(ShaderPath: String, SetUp_: Callable, NeedsOwnPass_: Array = [], OwnPasses_ := 0,
			OwnPassHideOriginal_ := false, BlendMode_ := 0, Tag_: Object = null) -> void:
		ShaderName = ShaderPath
		SetUp = SetUp_
		NeedsOwnPass = NeedsOwnPass_
		OwnPasses = OwnPasses_
		OwnPassHideOriginal = OwnPassHideOriginal_
		BlendMode = BlendMode_
		Tag = Tag_

	func RendersInOwnPass() -> bool:
		return not NeedsOwnPass.is_empty()


## The "CurrentShader" a SetUp gets (TShader.SetShaderConstant / SetTexture): one material's parameters.
class ShaderBinding:
	var TargetMaterial: ShaderMaterial

	func _init(material: ShaderMaterial) -> void:
		TargetMaterial = material

	func SetShaderConstant(Name: String, Value) -> void:
		TargetMaterial.set_shader_parameter(Name, Value)

	func SetTexture(Slot: int, Texture: Texture2D) -> void:
		TargetMaterial.set_shader_parameter(TMesh.TEXTURE_SLOT_UNIFORMS[Slot], Texture)


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
## TMesh.CastsNoShadow (shadow mapping is not ported yet: kept for when it is).
var CastsNoShadow := false

## Game-space placement (TMesh.Position / Front / Up / ScaleImbalanced).
var Position := Vector3.ZERO
var Front := Vector3(0, 0, 1)
var Up := Vector3(0, 1, 0)
var Rotation := Vector3.ZERO
var ScaleVector := Vector3.ONE

var Geometry: TGeometry = null
var MeshInstance: MeshInstance3D = null
var MeshInstances: Array[MeshInstance3D] = []
var MeshMaterial: ShaderMaterial
## TRawMesh.CustomShader: RMeshShader list, sorted by the effects' order values (TMeshEffect.InitializeOnMesh).
var CustomShader: Array[RMeshShader] = []
## [RMeshShader, pass index, ShaderMaterial] per own pass drawn in the world stage (built by ApplyMaterial).
var OwnPassMaterials: Array = []
## The glow stage (rsGlow, drawn only under the glow camera): the mesh's glow pass when it has a glow texture and no
## custom shader hides it, and [RMeshShader, pass index, ShaderMaterial] per own pass in the glow stage.
var GlowMaterial: ShaderMaterial = null
var GlowOwnPassMaterials: Array = []
## [RMeshShader, pass index, ShaderMaterial] per own pass in the effects stage (blended, not in the glow stage).
var EffectsOwnPassMaterials: Array = []
## TRawMesh.AnimationController with the bone driver, then the morph driver.
var AnimationController := TAnimationController.new()
var AnimationDriverBone: TSkinnedMeshAnimationDriver = null
var AnimationDriverMorph: TMeshMorphAnimationDriver = null
## Per bone of this mesh (TBone): the frame's weighted animations [[translation, scale, rotation (x y z w), weight]],
## the frame they belong to, and CombinedMatrix (null = zero, never passed down yet).
var _bone_animations: Array = []
var _bone_frame := -1
var _bone_combined: Array = []
## Meshes of client entities (TMeshComponent) animate every drawn frame; the mesh viewer poses its meshes itself
## (ShowFrame) and leaves this off.
var DrivenByController := false


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


## Port: drops the cached geometries (tests, tools).
static func ClearGeometryCache() -> void:
	_geometries.clear()


func _load(descriptor_path: String, data: Dictionary) -> void:
	FileName = descriptor_path
	Descriptor = data
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
	Geometry = _geometry(descriptor_path.get_base_dir() + "/" + GeometryFile)
	if Geometry == null:
		return
	MeshMaterial = ShaderMaterial.new()
	MeshInstance = MeshInstance3D.new()
	MeshInstance.name = "Geometry"
	MeshInstance.mesh = Geometry.Surface
	MeshInstance.material_override = MeshMaterial
	MeshInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# TMesh.Render culls with the geometry's bounding sphere (not the animated pose)
	var sphere_center := Geometry.Raw.BoundingSphereCenter
	var r := Geometry.Raw.BoundingSphereRadius
	MeshInstance.custom_aabb = AABB(sphere_center - Vector3.ONE * r, Vector3.ONE * 2.0 * r)
	add_child(MeshInstance)
	MeshInstances = [MeshInstance]
	_bone_combined.resize(Geometry.BoneNames.size())
	_bone_animations.resize(Geometry.BoneNames.size())
	for i in _bone_animations.size():
		_bone_animations[i] = []
	AnimationDriverBone = TSkinnedMeshAnimationDriver.new(self)
	AnimationDriverMorph = TMeshMorphAnimationDriver.new(self)
	AnimationController.AddDriver(AnimationDriverBone)
	AnimationController.AddDriver(AnimationDriverMorph)
	ApplyMaterial()
	ComputeTransformationMatrix()
	UploadBoneTransforms()


## TMeshAnimatedGeometry.CreateFromFile (cached) + LoadRawMeshData.
static func _geometry(path: String) -> TGeometry:
	if _geometries.has(path):
		return _geometries[path]
	var raw := TEngineRawMesh.CreateFromFile(path)
	if raw == null:
		push_error("TMesh: can't load geometry %s" % path)
		return null
	var g := TGeometry.new()
	g.Raw = raw
	# every mesh has at least one root bone; loading it loads the children (depth first)
	var parents: Array[int] = []
	for i in raw.BoneData.size():
		var bone: Dictionary = raw.BoneData[i]
		g.BoneNames.append(bone.Name)
		g.BoneOriginal.append(bone.Matrix)
		g.BoneChildren.append(PackedInt32Array())
	_link_bones(g, raw.BoneData, 0)
	for i in g.BoneNames.size():
		g.BoneLookup[g.BoneNames[i].to_lower()] = i
	g.HasSkin = not raw.SkinData.is_empty()
	for link: Dictionary in raw.SkinData:
		var bone: int = g.BoneLookup.get(String(link.TargetBoneName).to_lower(), -1)
		if bone < 0:
			push_error("TMesh: referenced bone \"%s\" not found in %s" % [link.TargetBoneName, path])
			bone = 0
		g.SkinBones.append(bone)
		g.SkinOffsets.append(link.OffsetMatrix)
	if raw.SkinData.size() > HW_MAX_BONES:
		push_error("TMesh: %s has too many bones (%d, max %d)" % [path, raw.SkinData.size(), HW_MAX_BONES])
	g.MorphtargetCount = raw.MorphtargetMapping.size()
	g.Surface = _build_mesh(raw, g.HasSkin)
	_geometries[path] = g
	return g


## TBone.Create(Data): each bone takes its ChildCount children from the rest of the list. Returns the next index.
static func _link_bones(g: TGeometry, data: Array, index: int) -> int:
	var next := index + 1
	for c in int(data[index].ChildCount):
		if next >= data.size():
			break
		g.BoneChildren[index].append(next)
		next = _link_bones(g, data, next)
	return next


static func _build_mesh(raw: TEngineRawMesh, skinned: bool) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = raw.Positions
	arrays[Mesh.ARRAY_NORMAL] = raw.Normals
	arrays[Mesh.ARRAY_TEX_UV] = raw.TextureCoordinates
	arrays[Mesh.ARRAY_INDEX] = raw.Indices
	# SMOOTHED_NORMAL (mesh effects) in CUSTOM2
	var smoothed := PackedFloat32Array()
	smoothed.resize(raw.SmoothedNormals.size() * 3)
	for i in raw.SmoothedNormals.size():
		var n := raw.SmoothedNormals[i]
		smoothed[i * 3] = n.x
		smoothed[i * 3 + 1] = n.y
		smoothed[i * 3 + 2] = n.z
	arrays[Mesh.ARRAY_CUSTOM2] = smoothed
	var format := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT
	if skinned:
		arrays[Mesh.ARRAY_CUSTOM0] = raw.BoneWeights
		var indices := PackedFloat32Array()
		indices.resize(raw.BoneIndices.size())
		for i in raw.BoneIndices.size():
			indices[i] = raw.BoneIndices[i]
		arrays[Mesh.ARRAY_CUSTOM1] = indices
		format |= (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var blend_shapes := []
	var mesh := ArrayMesh.new()
	var targets := mini(raw.MorphtargetMapping.size(), raw.MorphPositions.size())
	if targets > 0:
		mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
		for k in targets:
			mesh.add_blend_shape("morph%d" % k)
			var shape := []
			shape.resize(Mesh.ARRAY_MAX)
			var positions := PackedVector3Array()
			positions.resize(raw.Positions.size())
			var offsets: PackedVector3Array = raw.MorphPositions[k]
			for i in positions.size():
				positions[i] = raw.Positions[i] + offsets[i]
			shape[Mesh.ARRAY_VERTEX] = positions
			shape[Mesh.ARRAY_NORMAL] = raw.Normals
			blend_shapes.append(shape)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blend_shapes, {}, format)
	return mesh


func _texture(file: String) -> Texture2D:
	if file == "":
		return null
	# a script's texture name (BindTextureToTeam) is taken from the descriptor's folder like the descriptor's own;
	# the importer lowercases it and writes a .png where only the engine cache .tex exists. A game path
	# (AbsolutePath(PATH_GRAPHICS...), the mesh effects' glow overrides) is resolved from the game root.
	var path := FileName.get_base_dir() + "/" + file.replace("\\", "/").get_file().to_lower()
	if file.begins_with("\\") or file.begins_with("/"):
		path = TClientMap.ResolveGamePath(file)
	if not ResourceLoader.exists(path) and ResourceLoader.exists(path.get_basename() + ".png"):
		path = path.get_basename() + ".png"
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


## Builds the materials and pushes the material settings to them (TRawMesh.GenerateShaderBitmask, ResolveShaderArray
## and Render's SetUpShader, world and effects stages). Call it after changing textures, material values, the cull
## mode or the custom shaders. The drawing (TRawMesh.Render): the mesh with its shader and every custom shader that
## does not render in an own pass, unless a custom shader hides it (OwnPassHideOriginal); then, per custom shader
## drawn in own passes in the world stage, OwnPasses more draws (cull none) with only that shader's blocks. Godot
## draws them as the material's next_pass chain. The glow stage (DrawsAtStage rsGlow) follows in the same chain: the
## glow pass (GenerateShaderBitmask(rsGlow): the glow texture as diffuse, ALPHA, no lighting, the mesh's cull mode)
## when the mesh has a glow texture and nothing hides it, then the own passes in the glow stage; these variants draw
## only under the glow camera (TPostEffectManager), where the world ones draw black.
func ApplyMaterial() -> void:
	if MeshMaterial == null:
		return
	var diffuse := _texture(DiffuseTexture)
	var material := _texture(MaterialTexture)
	var glow := _texture(GlowTexture)
	var flags := _shader_flags(diffuse != null, material != null)
	var skinning := Geometry != null and Geometry.HasSkin
	MeshMaterial.shader = _shader_for(Cullmode, flags, skinning, ResolveShaderArray())
	OwnPassMaterials.clear()
	GlowOwnPassMaterials.clear()
	GlowMaterial = null
	for mesh_shader: RMeshShader in CustomShader:
		if RS_WORLD in mesh_shader.NeedsOwnPass:
			for j in mesh_shader.OwnPasses:
				var pass_material := ShaderMaterial.new()
				pass_material.shader = _shader_for("cmNone", flags, skinning, [mesh_shader.ShaderName])
				OwnPassMaterials.append([mesh_shader, j, pass_material])
	EffectsOwnPassMaterials.clear()
	for mesh_shader: RMeshShader in CustomShader:
		if RS_EFFECTS in mesh_shader.NeedsOwnPass:
			for j in mesh_shader.OwnPasses:
				var pass_material := ShaderMaterial.new()
				pass_material.shader = _shader_for("cmNone", _effects_flags(flags), skinning, [mesh_shader.ShaderName],
					mesh_shader.BlendMode)
				EffectsOwnPassMaterials.append([mesh_shader, j, pass_material])
	var hidden := CustomShaderBlocks()
	if glow != null and not hidden:
		GlowMaterial = ShaderMaterial.new()
		GlowMaterial.shader = _shader_for(Cullmode, _glow_flags(true, false), skinning, ResolveShaderArray())
	for mesh_shader: RMeshShader in CustomShader:
		if RS_GLOW in mesh_shader.NeedsOwnPass:
			for j in mesh_shader.OwnPasses:
				var pass_material := ShaderMaterial.new()
				pass_material.shader = _shader_for("cmNone", _glow_flags(glow != null, true), skinning,
					[mesh_shader.ShaderName], mesh_shader.BlendMode)
				GlowOwnPassMaterials.append([mesh_shader, j, pass_material])
	var chain: Array[ShaderMaterial] = []
	if not hidden:
		chain.append(MeshMaterial)
	for own: Array in OwnPassMaterials:
		chain.append(own[2])
	for own: Array in EffectsOwnPassMaterials:
		chain.append(own[2])
	var world_count := chain.size()
	if GlowMaterial != null:
		chain.append(GlowMaterial)
	for own: Array in GlowOwnPassMaterials:
		chain.append(own[2])
	for i in chain.size():
		chain[i].next_pass = chain[i + 1] if i + 1 < chain.size() else null
		if i < world_count:
			_set_material_parameters(chain[i], diffuse, material)
		else:
			_set_material_parameters(chain[i], glow, null)
			chain[i].set_shader_parameter("use_alpha", true)
	MeshMaterial.set_shader_parameter("glow_replaces", GlowMaterial != null)
	if MeshInstance != null:
		MeshInstance.material_override = chain[0] if not chain.is_empty() else null
	UploadBoneTransforms()
	SetUpCustomShaders()


## GenerateShaderBitmask(rsEffects) for own passes of the effects stage: the world flags without the G-buffer, lit
## forward, blended (ROL_ALPHA; the ALPHA flag itself stays the mesh's HasAlpha, use_alpha), no z write.
static func _effects_flags(world_flags: PackedStringArray) -> PackedStringArray:
	var flags := PackedStringArray(["ROL_EFFECTS_STAGE", "ROL_ALPHA"])
	for flag in world_flags:
		if flag in ["DIFFUSETEXTURE", "MATERIAL", "MATERIALTEXTURE"]:
			flags.append(flag)
	return flags


## GenerateShaderBitmask(rsGlow) as defines: ROL_GLOW_STAGE, DIFFUSETEXTURE (the glow texture); own passes blend
## (ROL_ALPHA).
static func _glow_flags(has_glow: bool, own_pass: bool) -> PackedStringArray:
	var flags := PackedStringArray(["ROL_GLOW_STAGE"])
	if own_pass:
		flags.append("ROL_ALPHA")
	if has_glow:
		flags.append("DIFFUSETEXTURE")
	return flags


func _set_material_parameters(m: ShaderMaterial, diffuse: Texture2D, material: Texture2D) -> void:
	m.set_shader_parameter("diffuse_texture", diffuse)
	m.set_shader_parameter("material_texture", material)
	m.set_shader_parameter("specular_intensity", SpecularIntensity)
	m.set_shader_parameter("specular_power", SpecularPower)
	m.set_shader_parameter("specular_tint", SpecularTint)
	m.set_shader_parameter("shading_reduction", ShadingReduction if ShadingReduction > 0.0 else ShadingReductionOverride)
	m.set_shader_parameter("use_alpha", HasAlpha())
	m.set_shader_parameter("alpha", Alpha)
	m.set_shader_parameter("alpha_test_ref", AlphaTestTreshold)
	m.set_shader_parameter("replacement_color", ColorOverride if HasColorOverride() else Color(0, 0, 0, 0))
	m.set_shader_parameter("color_adjustment", ColorAdjustment != Vector3.ZERO)
	m.set_shader_parameter("absolute_color_adjustment", ColorAdjustment != Vector3.ZERO and AbsoluteHSV != Vector3.ZERO)
	m.set_shader_parameter("hsv_offset", ColorAdjustment)
	m.set_shader_parameter("absolute_hsv", AbsoluteHSV)


## The shader bitmask's flags the effect blocks test, as defines: GBUFFER (opaque meshes, lit by the deferred pass;
## with it DRAW_COLOR / DRAW_NORMAL / DRAW_MATERIAL, the G-buffer's targets), DIFFUSETEXTURE, MATERIAL,
## MATERIALTEXTURE, ROL_ALPHA (HasAlpha: blended, the forward path).
func _shader_flags(has_diffuse: bool, has_material_texture: bool) -> PackedStringArray:
	var flags := PackedStringArray()
	if HasAlpha():
		flags.append("ROL_ALPHA")
	else:
		flags.append_array(["GBUFFER", "DRAW_COLOR", "DRAW_NORMAL", "DRAW_MATERIAL"])
	if has_diffuse:
		flags.append("DIFFUSETEXTURE")
	if HasMaterialSettings():
		flags.append("MATERIAL")
	if has_material_texture:
		flags.append("MATERIALTEXTURE")
	return flags


## TRawMesh.ResolveShaderArray: the custom shaders that do not render in an own pass, in list order.
func ResolveShaderArray() -> Array:
	var result := []
	for mesh_shader: RMeshShader in CustomShader:
		if not mesh_shader.RendersInOwnPass():
			result.append(mesh_shader.ShaderName)
	return result


## TRawMesh.Render CustomShaderBlocks: a custom shader hides the mesh's own drawing.
func CustomShaderBlocks() -> bool:
	for mesh_shader: RMeshShader in CustomShader:
		if mesh_shader.OwnPassHideOriginal:
			return true
	return false


## Render's SetUpShader for the world stage: the custom shaders' SetUp on the main material (last to first, those not
## in an own pass), then per own pass material its shader's SetUp with the pass index. The original runs this every
## drawn frame; the port from _process.
func SetUpCustomShaders() -> void:
	if CustomShader.is_empty():
		return
	var main := ShaderBinding.new(MeshMaterial)
	for i in range(CustomShader.size() - 1, -1, -1):
		var mesh_shader: RMeshShader = CustomShader[i]
		if not mesh_shader.RendersInOwnPass() and mesh_shader.SetUp.is_valid():
			mesh_shader.SetUp.call(main, RS_WORLD, 0)
	for own: Array in OwnPassMaterials:
		var mesh_shader: RMeshShader = own[0]
		if mesh_shader.SetUp.is_valid():
			mesh_shader.SetUp.call(ShaderBinding.new(own[2]), RS_WORLD, own[1])
	for own: Array in EffectsOwnPassMaterials:
		var mesh_shader: RMeshShader = own[0]
		if mesh_shader.SetUp.is_valid():
			mesh_shader.SetUp.call(ShaderBinding.new(own[2]), RS_EFFECTS, own[1])
	if GlowMaterial != null:
		var glow_binding := ShaderBinding.new(GlowMaterial)
		for i in range(CustomShader.size() - 1, -1, -1):
			var mesh_shader: RMeshShader = CustomShader[i]
			if not mesh_shader.RendersInOwnPass() and mesh_shader.SetUp.is_valid():
				mesh_shader.SetUp.call(glow_binding, RS_GLOW, 0)
	for own: Array in GlowOwnPassMaterials:
		var mesh_shader: RMeshShader = own[0]
		if mesh_shader.SetUp.is_valid():
			mesh_shader.SetUp.call(ShaderBinding.new(own[2]), RS_GLOW, own[1])


## The materials this mesh draws with (bone matrices go to each).
func Materials() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = [MeshMaterial]
	for own: Array in OwnPassMaterials:
		result.append(own[2])
	for own: Array in EffectsOwnPassMaterials:
		result.append(own[2])
	if GlowMaterial != null:
		result.append(GlowMaterial)
	for own: Array in GlowOwnPassMaterials:
		result.append(own[2])
	return result


## One compiled shader per render mode, flag and custom shader combination: the standard shader template with the
## custom shaders' blocks (TShader.Compose), the render mode and the flag defines in front.
static func _shader_for(cullmode: String, flags: PackedStringArray, skinning: bool, custom_shaders: Array,
		blend_mode := BLEND_LINEAR) -> Shader:
	var key := "%s|%s|%s|%s|%d" % [cullmode, ",".join(flags), skinning, "+".join(custom_shaders), blend_mode]
	if _shaders.has(key):
		return _shaders[key]
	var cull := "cull_back"
	if cullmode == "cmNone":
		cull = "cull_disabled"
	elif cullmode == "cmCW":
		cull = "cull_front"
	var has_alpha := flags.has("ROL_ALPHA")
	var modes := "unshaded, %s, %s" % [cull, "blend_mix, depth_draw_opaque" if has_alpha else "depth_draw_opaque"]
	if has_alpha and (flags.has("ROL_GLOW_STAGE") or flags.has("ROL_EFFECTS_STAGE")):
		# own passes outside the world stage: no z write, blended (Render: SrcAlpha / One with the blend op, or the
		# linear SrcAlpha / InvSrcAlpha)
		var blend := "blend_mix"
		if blend_mode == BLEND_ADDITIVE:
			blend = "blend_add"
		elif blend_mode == BLEND_REVERSE_SUBTRACTIVE:
			blend = "blend_sub"
		modes = "unshaded, %s, %s, depth_draw_never" % [cull, blend]
	var defines := ""
	for flag in flags:
		defines += "#define %s\n" % flag
	if cullmode == "cmNone":
		defines += "#define CULLNONE\n"
	if skinning:
		defines += "#define ROL_SKINNING\n"
	var blocks := []
	for name: String in custom_shaders:
		blocks.append(TShader.LoadBlockFile(name))
	var body := TShader.Compose(TShader.LoadBaseFile(SHADER_INCLUDE), blocks)
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode %s;\n%s%s" % [modes, defines, body]
	_shaders[key] = shader
	return shader


## TMesh.ComputeTransformationMatrix: Translation(Position) * Base(Left, Up, Front) * RotationPitchYawRoll(Rotation)
## * Scaling, then the X mirror. In Godot space the mirror and ToGodot conjugate the rest:
## basis = G * Base * Rotation * G * Scaling, G = diag(-1, 1, 1).
func ComputeTransformationMatrix() -> void:
	var left := Up.cross(Front).normalized()
	var up := Front.cross(left).normalized()
	var base := Basis.IDENTITY
	if left != Vector3.ZERO and up != Vector3.ZERO and Front != Vector3.ZERO:
		base = Basis(left, up, Front)
	var g := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	transform = Transform3D(g * base * RMatrix.RotationPitchYawRoll(Rotation) * g * Basis.from_scale(ScaleVector),
		ToGodot(Position))


## TMesh.Rotation (pitch, yaw, roll), applied inside the base.
func SetRotation(value: Vector3) -> void:
	Rotation = value
	ComputeTransformationMatrix()


func SetPosition(value: Vector3) -> void:
	Position = value
	ComputeTransformationMatrix()


func SetScale(value: float) -> void:
	ScaleVector = Vector3(value, value, value)
	ComputeTransformationMatrix()


## TMesh.Scale (read): the x of the scale vector.
func GetScale() -> float:
	return ScaleVector.x


## TMesh.SetFront / SetUp: a zero vector is ignored, others are normalized. Call ComputeTransformationMatrix after
## changing the placement (the original's FTransformDirty).
func SetFront(value: Vector3) -> void:
	if value == Vector3.ZERO:
		return
	Front = value.normalized()


func SetUp(value: Vector3) -> void:
	if value == Vector3.ZERO:
		return
	Up = value.normalized()


## TMesh.Left = Front x Up
func Left() -> Vector3:
	return Front.cross(Up).normalized()


## TMesh.Visible
func SetVisible(value: bool) -> void:
	visible = value


## The original's FTransformationMatrix in game space: Translation * Base(Left, Up, Front) * Scaling * Mirror(-1, 1, 1).
func TransformationMatrix() -> Transform3D:
	var left := Up.cross(Front).normalized()
	var up := Front.cross(left).normalized()
	var base := Basis.IDENTITY
	if left != Vector3.ZERO and up != Vector3.ZERO and Front != Vector3.ZERO:
		base = Basis(left, up, Front)
	return Transform3D(base * Basis.from_scale(ScaleVector) * Basis.from_scale(Vector3(-1, 1, 1)), Position)


## Untransformed bounding box of the geometry (TMesh.GetUntransformedBoundingBox: the raw mesh's box), file units.
func GetUntransformedBoundingBox() -> AABB:
	return Geometry.Raw.BoundingBox if Geometry != null else AABB()


## TMesh.BoundingBoxTransformed: the file's bounding box through the transformation matrix (game space).
func BoundingBoxTransformed() -> AABB:
	return TransformationMatrix() * GetUntransformedBoundingBox()


## TMesh.BoundingSphereTransformed: [center, radius] in game space (the box's sphere).
func BoundingSphereTransformed() -> Array:
	var box := BoundingBoxTransformed()
	return [box.get_center(), box.size.length() / 2.0]


# ---- bones (TMeshAnimatedGeometry.TBone, TSkin) --------------------------------------------------------------

## TBone.AddBoneAnimation: collects the frame's weighted animations of a bone.
func AddBoneAnimation(Bone: int, Translation: Vector3, Scale: Vector3, Rotation: Vector4, Weight: float) -> void:
	_clear_bone_animations_if_old()
	_bone_animations[Bone].append([Translation, Scale, Rotation, Weight])


func _clear_bone_animations_if_old() -> void:
	# new frame? -> all old animated matrices not longer useful
	if GFXD.FrameCount != _bone_frame:
		for list: Array in _bone_animations:
			list.clear()
		_bone_frame = GFXD.FrameCount


## TBone.PassAnimationToHierarchy from the root with the identity: a bone with animations sums translation and scale
## by weight and slerps the rotations in order (the weight sum stays the first one's, as in the original).
func PassAnimationToHierarchy() -> void:
	_clear_bone_animations_if_old()
	if not Geometry.BoneNames.is_empty():
		_pass_bone(0, Transform3D.IDENTITY)


func _pass_bone(Bone: int, Parent: Transform3D) -> void:
	var animated: Transform3D
	var list: Array = _bone_animations[Bone]
	if not list.is_empty():
		var translation := Vector3.ZERO
		var scale_ := Vector3.ZERO
		for entry: Array in list:
			translation += entry[3] * entry[0]
			scale_ += entry[3] * entry[1]
		var rotation: Vector4 = list[0][2]
		var weight_sum: float = list[0][3]
		for i in range(1, list.size()):
			rotation = QuaternionSlerp(rotation, list[i][2], list[i][3] / (list[i][3] + weight_sum))
		animated = Transform3D(QuaternionToBasis(rotation) * Basis.from_scale(scale_), translation)
	else:
		animated = Geometry.BoneOriginal[Bone]
	var combined := Parent * animated
	_bone_combined[Bone] = combined
	for child in Geometry.BoneChildren[Bone]:
		_pass_bone(child, combined)


## RVector4Helper.QuaternionToMatrix4x3 (the rotation of an unnormalized x y z w quaternion).
static func QuaternionToBasis(q: Vector4) -> Basis:
	var sqw := q.w * q.w
	var sqx := q.x * q.x
	var sqy := q.y * q.y
	var sqz := q.z * q.z
	var invs := sqx + sqy + sqz + sqw
	invs = 1.0 if invs == 0.0 else 1.0 / invs
	var m11 := (sqx - sqy - sqz + sqw) * invs
	var m22 := (-sqx + sqy - sqz + sqw) * invs
	var m33 := (-sqx - sqy + sqz + sqw) * invs
	var m12 := 2.0 * (q.x * q.y + q.z * q.w) * invs
	var m21 := 2.0 * (q.x * q.y - q.z * q.w) * invs
	var m13 := 2.0 * (q.x * q.z - q.y * q.w) * invs
	var m31 := 2.0 * (q.x * q.z + q.y * q.w) * invs
	var m23 := 2.0 * (q.y * q.z + q.x * q.w) * invs
	var m32 := 2.0 * (q.y * q.z - q.x * q.w) * invs
	# Column[i] = (_i1, _i2, _i3)
	return Basis(Vector3(m11, m12, m13), Vector3(m21, m22, m23), Vector3(m31, m32, m33))


## RVector4.SLerp (its sin(Dot) for sin(om) cancels in the final normalization).
static func QuaternionSlerp(a: Vector4, b: Vector4, s: float) -> Vector4:
	var q1 := a.normalized()
	var q2 := b.normalized()
	var dot := q1.dot(q2)
	if dot < 0:
		q2 = -q2
		dot = -dot
	var scale0 := 1.0 - s
	var scale1 := s
	if (1.0 - dot) > 0.00001:
		var om := acos(dot)
		var sinom := sin(dot)
		scale0 = sin((1.0 - s) * om) / sinom
		scale1 = sin(s * om) / sinom
	return (scale0 * q1 + scale1 * q2).normalized()


## TSkin.ComputeAnimatedMatrices -> the shader's bone_transforms (TSkinnedMeshAnimationDriver.SetShaderSettings);
## the morph driver's weights -> the blend shapes (TMeshMorphAnimationDriver.SetShaderSettings: weight / 100).
func UploadBoneTransforms() -> void:
	if Geometry == null:
		return
	if Geometry.HasSkin:
		var matrices: Array[Projection] = []
		for i in HW_MAX_BONES:
			matrices.append(Projection(_skin_matrix(i) if i < Geometry.SkinBones.size() else Transform3D()))
		for m in Materials():
			m.set_shader_parameter("bone_transforms", matrices)
	if AnimationDriverMorph != null and AnimationDriverMorph.HasMorph():
		for k in mini(Geometry.MorphtargetCount, Geometry.Surface.get_blend_shape_count()):
			MeshInstance.set_blend_shape_value(k, AnimationDriverMorph.CurrentMorphweights[k] / 100.0)


## TRawMesh.TryGetBonePosition: the game-space matrix of a bone (the transformation matrix * its CombinedMatrix, or
## its OriginalMatrix if never animated), base columns normalized; null if the mesh has no such bone.
func TryGetBonePosition(BoneName: String):
	if Geometry == null or not Geometry.BoneLookup.has(BoneName.to_lower()):
		return null
	var bone: int = Geometry.BoneLookup[BoneName.to_lower()]
	AnimationController.UpdateAnimations()
	var combined = _bone_combined[bone]
	var bone_matrix: Transform3D = combined if combined != null else Geometry.BoneOriginal[bone]
	var result := TransformationMatrix() * bone_matrix
	result.basis = Basis(result.basis.x.normalized(), result.basis.y.normalized(), result.basis.z.normalized())
	return result


## TMeshComponent.CreateNewAnimationFrom's call on both drivers.
func CreateNewAnimation(NewAnimationName: String, SourceAnimation: String, Startframe: int, Endframe: int) -> void:
	if AnimationDriverMorph != null:
		AnimationDriverMorph.CreateNewAnimation(NewAnimationName, SourceAnimation, Startframe, Endframe)
	if AnimationDriverBone != null:
		AnimationDriverBone.CreateNewAnimation(NewAnimationName, SourceAnimation, Startframe, Endframe)


## Updates the animations (once per frame, TRawMesh render) and hands the result to the shader.
func Animate() -> void:
	AnimationController.UpdateAnimations()
	UploadBoneTransforms()


func _process(_delta: float) -> void:
	if ProfUs == null:
		if DrivenByController:
			Animate()
		SetUpCustomShaders()
		return
	var t0 := Time.get_ticks_usec()
	if DrivenByController:
		Animate()
	var t1 := Time.get_ticks_usec()
	SetUpCustomShaders()
	ProfUs[0] += t1 - t0
	ProfUs[1] += Time.get_ticks_usec() - t1
	ProfUs[2] += 1


## Port, a development aid (main thread only): set ProfUs = [0, 0, 0] to sum the per-frame mesh work
## [Animate us, SetUpCustomShaders us, mesh frames].
static var ProfUs = null


## Frees a mesh (the owner's FreeAndNil): the controller drops its drivers first. A static function, as a node can't
## free itself inside one of its own methods.
static func Release(mesh: TMesh) -> void:
	mesh.AnimationController.Clear()
	mesh.AnimationDriverBone = null
	mesh.AnimationDriverMorph = null
	if mesh.is_inside_tree():
		mesh.queue_free()
	else:
		mesh.free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		AnimationController.Clear()


# ---- tools (mesh viewer) -------------------------------------------------------------------------------------

## Names of the file's animations (the take).
func AnimationNames() -> PackedStringArray:
	var names := PackedStringArray()
	if Geometry != null:
		for animation: Dictionary in Geometry.Raw.BoneAnimationData:
			names.append(animation.Name)
	return names


## Frames of the file's take (its last keyframe index).
func FrameCount() -> int:
	if AnimationDriverBone == null or not AnimationDriverBone.AnimationData.has(FBX_DEFAULT_ANIMATIONTRACK):
		return 0
	return AnimationDriverBone.AnimationData[FBX_DEFAULT_ANIMATIONTRACK].FrameCount - 1


## Shows one frame of the file's take (frame numbers as CreateNewAnimation counts them), weight 1.
func ShowFrame(frame: float) -> void:
	if AnimationDriverBone == null or not AnimationDriverBone.AnimationData.has(FBX_DEFAULT_ANIMATIONTRACK):
		return
	var frames := maxi(FrameCount(), 1)
	GFXD.NextFrame()
	AnimationDriverBone.UpdateAnimation(FBX_DEFAULT_ANIMATIONTRACK, 0.0, clampf(frame / frames, 0.0, 1.0), 1.0)
	UploadBoneTransforms()


## Bounds of the geometry as currently posed (skinned on the CPU like the shader), file units.
func GetPosedBoundingBox() -> AABB:
	if Geometry == null:
		return AABB()
	var raw := Geometry.Raw
	if not Geometry.HasSkin:
		return raw.BoundingBox
	var skin: Array[Transform3D] = []
	for i in Geometry.SkinBones.size():
		skin.append(_skin_matrix(i))
	var box := AABB()
	for v in raw.Positions.size():
		var x := Vector3.ZERO
		var y := Vector3.ZERO
		var z := Vector3.ZERO
		var t := Vector3.ZERO
		for j in 4:
			var w: float = raw.BoneWeights[v * 4 + j]
			if w != 0.0:
				var s: Transform3D = skin[raw.BoneIndices[v * 4 + j]]
				x += s.basis.x * w
				y += s.basis.y * w
				z += s.basis.z * w
				t += s.origin * w
		var p: Vector3 = Transform3D(Basis(x, y, z), t) * raw.Positions[v]
		box = AABB(p, Vector3.ZERO) if v == 0 else box.expand(p)
	return box


## BoneTransforms[link] = CombinedMatrix * BoneSpaceOffsetMatrix (a bone never passed down has a zero matrix).
func _skin_matrix(link: int) -> Transform3D:
	var combined = _bone_combined[Geometry.SkinBones[link]]
	if combined == null:
		return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
	return (combined as Transform3D) * Geometry.SkinOffsets[link]


# ---- drivers ---------------------------------------------------------------------------------------------------

## TSkinnedMeshAnimationDriver with TSkinnedMeshAnimationData: per animation the channels of existing bones with
## keyframes, their times normalized by the animation's length (the latest last keyframe; a channel without keyframes
## resets it to 0, as the original's GetAnimationLength does).
class TSkinnedMeshAnimationDriver:
	var FMesh: TMesh
	## name -> {Name, Length, FrameCount, Sub: [{Bone, Times (0..1), Translations, Scales, Rotations}]}
	var AnimationData := {}

	func _init(mesh: TMesh) -> void:
		FMesh = mesh
		for animation: Dictionary in mesh.Geometry.Raw.BoneAnimationData:
			var length := 0
			for channel: Dictionary in animation.Channels:
				if channel.Times.size() > 0:
					length = maxi(channel.Times[channel.Times.size() - 1], length)
				else:
					length = 0
			var data := {"Name": animation.Name, "Length": length, "FrameCount": 0, "Sub": []}
			for channel: Dictionary in animation.Channels:
				var bone: int = mesh.Geometry.BoneLookup.get(String(channel.TargetBone).to_lower(), -1)
				if bone < 0 or channel.Times.size() == 0:
					continue
				data.FrameCount = maxi(data.FrameCount, channel.Times.size())
				var times := PackedFloat32Array()
				for t in channel.Times:
					# normalize data in range 0..1
					times.append(float(t) / length if length != 0 else 0.0)
				data.Sub.append({"Bone": bone, "Times": times, "Translations": channel.Translations,
					"Scales": channel.Scales, "Rotations": channel.Rotations})
			AnimationData[animation.Name] = data

	func HasSkin() -> bool:
		return FMesh.Geometry.HasSkin

	## TAnimationDriver.CreateNewAnimation + TSkinnedMeshAnimationData.ExtractPart: frames Startframe..Endframe (both
	## included, clamped to every channel's keyframes) become a new animation; its length is the time between the
	## two keyframes of the first channel.
	func CreateNewAnimation(NewAnimationName: String, SourceAnimation: String, StartFrame: int, EndFrame: int) -> void:
		if AnimationData.has(NewAnimationName):
			push_warning("TAnimationDriver: Animation \"%s\" already exists!" % NewAnimationName)
			return
		if not AnimationData.has(SourceAnimation):
			return
		var source: Dictionary = AnimationData[SourceAnimation]
		for sub: Dictionary in source.Sub:
			StartFrame = mini(StartFrame, sub.Times.size() - 1)
			EndFrame = mini(EndFrame, sub.Times.size() - 1)
		var data := {"Name": NewAnimationName, "Length": 0, "FrameCount": 0, "Sub": []}
		if not source.Sub.is_empty():
			var first: Dictionary = source.Sub[0]
			data.Length = roundi(source.Length * (first.Times[EndFrame] - first.Times[StartFrame]))
			for sub: Dictionary in source.Sub:
				var times := PackedFloat32Array()
				for frame in range(StartFrame, EndFrame + 1):
					times.append(float(frame - StartFrame) / (EndFrame - StartFrame) if EndFrame != StartFrame else NAN)
				data.Sub.append({"Bone": sub.Bone, "Times": times, "Translations": sub.Translations.slice(StartFrame, EndFrame + 1),
					"Scales": sub.Scales.slice(StartFrame, EndFrame + 1), "Rotations": sub.Rotations.slice(StartFrame, EndFrame + 1)})
		AnimationData[NewAnimationName] = data

	## TAnimationDriver.UpdateAnimation -> TSkinnedMeshAnimationData.UpdateAnimation (only the end of the time
	## frame matters), then the hierarchy is passed down.
	func UpdateAnimation(Animation_: String, _StartKey: float, EndKey: float, Weight: float) -> void:
		if AnimationData.has(Animation_):
			for sub: Dictionary in AnimationData[Animation_].Sub:
				_update_sub(sub, EndKey, Weight)
		if HasSkin():
			FMesh.PassAnimationToHierarchy()

	func UpdateWithoutAnimation() -> void:
		if HasSkin():
			FMesh.PassAnimationToHierarchy()

	## RSkinnedMeshSubAnimationData.UpdateAnimation: the two keyframes around the time key (guessed, then searched),
	## translation and scale lerped, rotation slerped.
	func _update_sub(sub: Dictionary, Timekey: float, Weight: float) -> void:
		var times: PackedFloat32Array = sub.Times
		var count := times.size()
		if count == 0:
			return
		var first := 0
		var sec := count - 1
		if count > 2:
			sec = int((count - 1) * Timekey)
			first = maxi(sec - 1, 0)
			while not (times[first] <= Timekey and Timekey <= times[sec]):
				var direction := signi(int(signf(Timekey - times[sec])))
				sec = clampi(sec + direction, 0, count - 1)
				first = clampi(sec - 1, 0, count - 1)
				if first <= 0 or sec >= count - 1 or direction == 0:
					break
		var a := 1.0
		if first != sec:
			a = 1.0 - ((Timekey - times[first]) / absf(times[sec] - times[first]))
		a = clampf(a, 0.0, 1.0)
		var translation: Vector3 = sub.Translations[first].lerp(sub.Translations[sec], 1.0 - a)
		var scale_: Vector3 = sub.Scales[first].lerp(sub.Scales[sec], 1.0 - a)
		var rotation := TMesh.QuaternionSlerp(sub.Rotations[first], sub.Rotations[sec], 1.0 - a)
		FMesh.AddBoneAnimation(sub.Bone, translation, scale_, rotation, Weight)


## TMeshMorphAnimationDriver with TMorphAnimationData: per animation one weight curve per morph target (times in ms);
## the frame's weights of all playing animations add up (CurrentMorphweights, 0..100).
class TMeshMorphAnimationDriver:
	var FMesh: TMesh
	var FMorphtargetCount := 0
	var FLastFrameKey := -1
	var CurrentMorphweights := PackedFloat32Array()
	## name -> {Name, Length, FrameCount, Curves: {target index: [[time, weight], ...]}}
	var AnimationData := {}

	func _init(mesh: TMesh) -> void:
		FMesh = mesh
		var raw := mesh.Geometry.Raw
		FMorphtargetCount = raw.MorphtargetMapping.size()
		CurrentMorphweights.resize(TMesh.MAX_MORPH_TARGET_COUNT)
		for animation: Dictionary in raw.MorphAnimationData:
			var data := {"Name": animation.Name, "Length": 0, "FrameCount": 0, "Curves": {}}
			for channel: Dictionary in animation.Channels:
				var target := raw.MorphtargetMapping.find(String(channel.MorphTarget))
				if target < 0 or data.Curves.has(target) or target >= TMesh.MAX_MORPH_TARGET_COUNT:
					push_error("TMeshMorphAnimationDriver: bad morph target %s" % channel.MorphTarget)
					continue
				var keys: Array = []
				for k in channel.Times.size():
					keys.append([float(channel.Times[k]), channel.Weights[k]])
					data.Length = maxi(data.Length, roundi(float(channel.Times[k])))
				data.Curves[target] = keys
				data.FrameCount = maxi(data.FrameCount, keys.size())
			AnimationData[animation.Name] = data

	func HasMorph() -> bool:
		return FMorphtargetCount > 0

	func _clear_data_if_old() -> void:
		if GFXD.FrameCount != FLastFrameKey:
			CurrentMorphweights.fill(0.0)
			FLastFrameKey = GFXD.FrameCount

	## TAnimationDriver.CreateNewAnimation + TMorphAnimationData.CreateSlice: the keys between the frames' times
	## (frame * 1000 / 30), with lerped keys at the borders, shifted to start at 0.
	func CreateNewAnimation(NewAnimationName: String, SourceAnimation: String, StartFrame: int, EndFrame: int) -> void:
		if AnimationData.has(NewAnimationName):
			push_warning("TAnimationDriver: Animation \"%s\" already exists!" % NewAnimationName)
			return
		if not AnimationData.has(SourceAnimation):
			return
		var source: Dictionary = AnimationData[SourceAnimation]
		var data := {"Name": "Slice", "Length": 0, "FrameCount": EndFrame - StartFrame, "Curves": {}}
		var start := float(roundi(StartFrame * 1000.0 / 30.0))
		var end := float(roundi(EndFrame * 1000.0 / 30.0))
		data.Length = int(end - start)
		for key: int in source.Curves:
			var prev_keys: Array = source.Curves[key]
			var keys: Array = []
			for i in prev_keys.size():
				var keyframe: Array
				if i < prev_keys.size() - 1 and prev_keys[i][0] < start and prev_keys[i + 1][0] > start:
					# lerp starting key
					keyframe = _lerp(prev_keys[i], prev_keys[i + 1], (start - prev_keys[i][0]) / (prev_keys[i + 1][0] - prev_keys[i][0]))
				elif prev_keys[i][0] >= start and prev_keys[i][0] <= end:
					keyframe = prev_keys[i]
				elif i > 0 and prev_keys[i][0] > end and prev_keys[i - 1][0] < end:
					# lerp final key (from this key toward the previous one, as written)
					keyframe = _lerp(prev_keys[i], prev_keys[i - 1], (end - prev_keys[i - 1][0]) / (prev_keys[i][0] - prev_keys[i - 1][0]))
				else:
					continue
				keys.append([keyframe[0] - start, keyframe[1]])
			data.Curves[key] = keys
		AnimationData[NewAnimationName] = data

	static func _lerp(a: Array, b: Array, factor: float) -> Array:
		return [a[0] * (1 - factor) + b[0] * factor, a[1] * (1 - factor) + b[1] * factor]

	## TMorphAnimationData.UpdateAnimation: each curve at EndKey * Length (HArray.InterpolateLinear), times Weight,
	## added to this frame's weights.
	func UpdateAnimation(Animation_: String, _StartKey: float, EndKey: float, Weight: float) -> void:
		_clear_data_if_old()
		if not AnimationData.has(Animation_) or Weight <= 0.0:
			return
		var data: Dictionary = AnimationData[Animation_]
		for index: int in data.Curves:
			var weight := _interpolate(data.Curves[index], EndKey * data.Length)
			if index < CurrentMorphweights.size():
				CurrentMorphweights[index] += weight * Weight

	func UpdateWithoutAnimation() -> void:
		_clear_data_if_old()

	## HArray.InterpolateLinear on [time, weight] keys: before the first key the first, after the last the last.
	static func _interpolate(keys: Array, target: float) -> float:
		if keys.is_empty():
			return 0.0
		if keys.size() == 1:
			return keys[0][1]
		var prev: Array = keys[0]
		if prev[0] > target:
			return prev[1]
		var current: Array = prev
		for i in range(1, keys.size()):
			current = keys[i]
			if prev[0] <= target and current[0] > target:
				return prev[1] + (current[1] - prev[1]) * ((target - prev[0]) / (current[0] - prev[0]))
			prev = current
		return current[1]
