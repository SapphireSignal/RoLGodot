class_name TVegetationManager
extends Node3D
## Engine.Vegetation.pas TVegetationManager: the map's procedural vegetation, loaded from the importer's
## <map>.vegetation.json (the converted <Map>.veg). The maps use two object kinds (TTree is unused):
##   TVegetationMesh  a raw mesh (.msh, LOAD_RAW_MESH) picked from its Meshes list, rotated and sized by rolls
##   TGrassTuft       three crossed quads built from rolls around the ground normal
## Every object replays its rolls from its stored seed (RandSeed := FRandSeed) with Delphi's RNG (DelphiRandom),
## so the result is the original's. Drawing: src/runtime/graphics/vegetation.gdshader; meshes as one MultiMesh per
## (mesh file, texture), tufts as one mesh per texture. The original's kd-tree chunks only cull; they are not ported.
## Read docs/assets.md ("Vegetation").

const SHADER_PATH := "res://src/runtime/graphics/vegetation.gdshader"
const GRASSSHIELDS := 3

## Each object: the JSON dictionary of the importer (Type, FRandSeed, FPosition, FGroundNormal, ...).
var Objects: Array = []
## FWindDirection (game space); its length is WindStrength.
var WindDirection := Vector3(1, 0, 1).normalized()

var _materials: Array[ShaderMaterial] = []
static var _mesh_cache := {}


## TVegetationManager.CreateFromFile; an empty manager when the file is missing.
static func CreateFromFile(json_path: String) -> TVegetationManager:
	var manager := TVegetationManager.new()
	manager.name = "Vegetation"
	if FileAccess.file_exists(json_path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if data is Dictionary:
			if data.WindDirection != null:
				var w: Array = data.WindDirection
				manager.WindDirection = Vector3(w[0], w[1], w[2])
			manager.Objects = data.Objects
	manager.BuildBuffers()
	return manager


static func _vec3(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


## HMeshLoaderHelper.GetMeshData: the raw mesh of a mesh entry, cached per file.
static func GetMeshData(game_path: String) -> TEngineRawMesh:
	var path := TClientMap.ResolveGamePath(game_path.get_basename() + ".msh")
	if not _mesh_cache.has(path):
		_mesh_cache[path] = TEngineRawMesh.CreateFromFile(path) if FileAccess.file_exists(path) else null
		if _mesh_cache[path] == null:
			push_warning("HMeshLoaderHelper.LoadAndConvertMesh: File %s does not exist!" % path)
	return _mesh_cache[path]


## HMeshLoaderHelper's class destructor: drops the cached raw meshes.
static func ClearMeshCache() -> void:
	_mesh_cache.clear()


## TVegetationMesh.BuildMeshList: the Meshes memo split at line breaks.
static func MeshList(obj: Dictionary) -> PackedStringArray:
	return String(obj.get("Meshes", "")).replace("\r\n", "\n").split("\n")


## TVegetationMesh.ComputeAndSave's rolls: {Mesh: game path, Basis: rotation * size (game space), Origin}.
## Returns {} when the mesh is missing (the original skips the object).
static func RollVegetationMesh(obj: Dictionary) -> Dictionary:
	DelphiRandom.RandSeed = int(obj.FRandSeed)
	var meshes := MeshList(obj)
	var mesh_path := meshes[DelphiRandom.RandomRange(meshes.size())]
	var data := GetMeshData(mesh_path)
	if data == null:
		return {}
	var rotation := DelphiRandom.VariedVector3(obj.Rotation)
	var final_size := DelphiRandom.VariedSingle(obj.Size) * float(obj.Scale) / (data.BoundingSphereRadius * 2)
	# Transform = Translation(Position) * RotationPitchYawRoll(rotation) * Scaling(FinalSize)
	return {"Mesh": mesh_path, "Basis": RotationPitchYawRoll(rotation) * Basis.from_scale(Vector3.ONE * final_size),
		"Origin": _vec3(obj.FPosition), "Rotation": rotation, "Size": final_size}


## RMatrix.CreateRotationPitchYawRoll as a Basis acting on game-space column vectors (RMatrix.RotationPitchYawRoll).
static func RotationPitchYawRoll(pitch_yaw_roll: Vector3) -> Basis:
	return RMatrix.RotationPitchYawRoll(pitch_yaw_roll)


## RVector3.RotateAxis (Rodrigues).
static func RotateAxis(v: Vector3, axis: Vector3, angle: float) -> Vector3:
	var n := axis.normalized()
	var c := cos(angle)
	return v * c + n.cross(v) * sin(angle) + n * n.dot(v) * (1 - c)


## RVector3.GetArbitaryOrthogonalVector.
static func ArbitaryOrthogonalVector(v: Vector3) -> Vector3:
	var result := v.cross(Vector3(0, 1, 0)).normalized()
	if result == Vector3.ZERO:
		result = v.cross(Vector3(1, 0, 0)).normalized()
	return result


## TGrassTuft.ComputeAndSave: the 12 vertices (game space) of one tuft: per shield lt, rt, lb, rb, each
## {Position, TextureCoordinate, Normal, Custom}; indices per shield 0 2 1, 1 2 3.
static func GrassTuftVertices(obj: Dictionary) -> Array:
	DelphiRandom.RandSeed = int(obj.FRandSeed)
	var rotation := DelphiRandom.Random() * 2 * PI
	var ground := _vec3(obj.FGroundNormal)
	var position := _vec3(obj.FPosition)
	var scale := float(obj.Scale)
	var mid_offset := float(obj.MidOffset)
	var top := ground
	var side := ArbitaryOrthogonalVector(top).normalized()
	var front := top.cross(side).normalized()
	top = RotateAxis(top, side, DelphiRandom.VariedSingle(obj.Angle) - PI / 2).normalized()
	var real_size := DelphiRandom.VariedVector2(obj.Size)
	var real_trapezial := DelphiRandom.VariedSingle(obj.Trapezial) - 0.5
	var time_offset := DelphiRandom.Random()
	var result := []
	for i in GRASSSHIELDS:
		var angle := (float(i) / GRASSSHIELDS) * 2 * PI + rotation
		var normal := RotateAxis(top.cross(side).normalized(), ground, angle).lerp(ground, float(obj.NormalAdjustment)).normalized()
		var depth := front * real_size.x * mid_offset / 2
		var lt := RotateAxis((side * real_size.x / 2 + top * real_size.y + depth) * scale, ground, angle) + position
		var rt := RotateAxis((-side * real_size.x / 2 + top * real_size.y + depth) * scale, ground, angle) + position
		var lb := RotateAxis((side * real_size.x / 2 + depth) * scale, ground, angle) + position
		var rb := RotateAxis((-side * real_size.x / 2 + depth) * scale, ground, angle) + position
		var temp := lt
		lt = lt.lerp(rt, real_trapezial)
		rt = rt.lerp(temp, real_trapezial)
		result.append({"Position": lt, "TextureCoordinate": Vector2(0, 0), "Normal": normal, "Custom": Vector4(time_offset, 0, 1, 1)})
		result.append({"Position": rt, "TextureCoordinate": Vector2(1, 0), "Normal": normal, "Custom": Vector4(time_offset, 0, 1, 1)})
		result.append({"Position": lb, "TextureCoordinate": Vector2(0, 1), "Normal": normal, "Custom": Vector4(time_offset, 0, 0, 1)})
		result.append({"Position": rb, "TextureCoordinate": Vector2(1, 1), "Normal": normal, "Custom": Vector4(time_offset, 0, 0, 1)})
	return result


## BuildBuffers: groups the objects by texture (and, for meshes, mesh file) and builds the Godot nodes.
func BuildBuffers() -> void:
	for child in get_children():
		child.queue_free()
	_materials.clear()
	var instances := {}  # "texture|mesh" -> Array of rolls
	var tufts := {}      # texture -> Array of vertices
	for obj: Dictionary in Objects:
		match obj.Type:
			"TVegetationMesh":
				var roll := RollVegetationMesh(obj)
				if not roll.is_empty():
					var key := "%s|%s" % [obj.Diffuse, roll.Mesh]
					if not instances.has(key):
						instances[key] = []
					instances[key].append(roll)
			"TGrassTuft":
				if not tufts.has(obj.Diffuse):
					tufts[obj.Diffuse] = []
				tufts[obj.Diffuse].append_array(GrassTuftVertices(obj))
			_:
				push_warning("TVegetationManager: %s is not ported (unused by the original's maps)" % obj.Type)
	for key: String in instances:
		var parts := key.split("|")
		_add_multimesh(parts[0], parts[1], instances[key])
	for texture: String in tufts:
		_add_tufts(texture, tufts[texture])


func _material(texture_path: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	var path := TClientMap.ResolveGamePath(texture_path)
	if ResourceLoader.exists(path):
		material.set_shader_parameter("diffuse_texture", load(path))
	else:
		push_error("TVegetationManager: texture %s not found (%s)" % [texture_path, path])
	material.set_shader_parameter("wind_direction", WindDirection)
	_materials.append(material)
	return material


static func _custom_array(values: Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(values.size() * 4)
	for i in values.size():
		var v: Vector4 = values[i]
		result[i * 4] = v.x
		result[i * 4 + 1] = v.y
		result[i * 4 + 2] = v.z
		result[i * 4 + 3] = v.w
	return result


func _add_multimesh(texture_path: String, mesh_path: String, rolls: Array) -> void:
	var data := GetMeshData(mesh_path)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(data.Positions.size())
	normals.resize(data.Normals.size())
	for i in data.Positions.size():
		vertices[i] = TMesh.ToGodot(data.Positions[i])
		normals[i] = TMesh.ToGodot(data.Normals[i])
	# the original's index order (front faces stay front faces after the X mirror; drawn two-sided anyway)
	var indices := data.Indices
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = data.TextureCoordinates
	arrays[Mesh.ARRAY_CUSTOM0] = _custom_array(data.Colors)
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, _material(texture_path))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = rolls.size()
	var mirror := Basis.from_scale(Vector3(-1, 1, 1))
	for i in rolls.size():
		var roll: Dictionary = rolls[i]
		multimesh.set_instance_transform(i, Transform3D(mirror * (roll.Basis as Basis) * mirror, TMesh.ToGodot(roll.Origin)))
	var instance := MultiMeshInstance3D.new()
	instance.name = mesh_path.get_file().get_basename()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _add_tufts(texture_path: String, tuft_vertices: Array) -> void:
	var count := tuft_vertices.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var customs := []
	vertices.resize(count)
	normals.resize(count)
	uvs.resize(count)
	for i in count:
		var v: Dictionary = tuft_vertices[i]
		vertices[i] = TMesh.ToGodot(v.Position)
		normals[i] = TMesh.ToGodot(v.Normal)
		uvs[i] = v.TextureCoordinate
		customs.append(v.Custom)
	var indices := PackedInt32Array()
	for quad in range(0, count, 4):
		# PushIndex 0 2 1, 1 2 3
		indices.append_array([quad, quad + 2, quad + 1, quad + 1, quad + 2, quad + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = _custom_array(customs)
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, _material(texture_path))
	var instance := MeshInstance3D.new()
	instance.name = "GrassTufts"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## The shaders' time: TimeManager.GetFloatingTimestamp / 1000 at draw time.
func _process(_delta: float) -> void:
	var seconds := TTimeManager.GetFloatingTimestamp() / 1000.0
	for material in _materials:
		material.set_shader_parameter("time", seconds)
