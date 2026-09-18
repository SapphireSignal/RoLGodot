class_name TWaterSurface
extends MeshInstance3D
## Engine.Water.pas TWaterSurface: one water surface, a GeometryResolution x GeometryResolution grid over
## GeometrySize (game space xz) around Position, drawn by src/runtime/graphics/water.gdshader (a port of
## Watershader.fx with DEFERRED_SHADING, REFLECTIONS, REFRACTION, CAUSTICS). Read docs/assets.md ("Water").

const SHADER_PATH := "res://src/runtime/graphics/water.gdshader"

# TWaterSurface.Create defaults; the map file overrides them.
var WaveHeight := 1.2
var Roughness := 0.68
var Size := 90.0
var FresnelOffset := 0.2
var Transparency := 0.0
var DepthTransparencyRange := 1.5
var RefractionIndex := 1 / 1.333
var RefractionStepLength := 10.0
var RefractionSteps := 14.0
var ColorExtinctionRange := 150.0
var CausticsRange := 15.0
var Exposure := 0.35
var Specularpower := 40.0
var Specularintensity := 0.8
var CausticsScale := 1.0
## RColor as Vector4 (rgba).
var WaterColor := Vector4(0x0C / 255.0, 0x19 / 255.0, 0x40 / 255.0, 0.0)
var SkyColor := Vector4(0x34 / 255.0, 0x59 / 255.0, 0x71 / 255.0, 0.0)
var FallbackWaterColor := Vector4.ZERO
var Reflections := true
var Refraction := true
var Position := Vector3.ZERO
var GeometrySize := Vector2(50, 50)
var GeometryResolution := 200
## Game-root relative paths, like the file stores them.
var WaveTexture := ""
var SkyTexture := ""
var CausticsTexture := ""

var _material: ShaderMaterial


## From one surface of the importer's <map>.water.json.
static func CreateFromData(data: Dictionary) -> TWaterSurface:
	var surface := TWaterSurface.new()
	surface.name = "WaterSurface"
	for key: String in data:
		var value: Variant = data[key]
		match key:
			"WaterColor", "SkyColor", "FallbackWaterColor":
				surface.set(key, Vector4(value[0], value[1], value[2], value[3]))
			"Position":
				surface.Position = Vector3(value[0], value[1], value[2])
			"GeometrySize":
				surface.GeometrySize = Vector2(value[0], value[1])
			"GeometryResolution":
				surface.GeometryResolution = int(value)
			_:
				surface.set(key, value)
	surface.GenerateGeometry()
	surface._build_material()
	return surface


## GenerateGeometry: vertex (x, z) at (x / (res - 1) - 0.5, 0, z / (res - 1) - 0.5), texture coordinate
## (x / (res - 1), z / (res - 1)); quads (topLeft, bottomLeft, bottomRight) (bottomRight, topRight, topLeft).
## The world transform Translation(Position) * Scaling(GeometrySize.X0Y) is applied to the vertices here, in Godot
## space (x negated). The index order stays the original's: its clockwise front faces (D3D, left-handed) are still
## front faces in Godot after the mirror (checked in a capture, docs/assets.md).
func GenerateGeometry() -> void:
	var res := GeometryResolution
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(res * res)
	uvs.resize(res * res)
	for z in res:
		for x in res:
			var local := Vector3(float(x) / (res - 1) - 0.5, 0.0, float(z) / (res - 1) - 0.5)
			vertices[z * res + x] = TMesh.ToGodot(local * Vector3(GeometrySize.x, 0.0, GeometrySize.y) + Position)
			uvs[z * res + x] = Vector2(float(x) / (res - 1), float(z) / (res - 1))
	var indices := PackedInt32Array()
	indices.resize((res - 1) * (res - 1) * 6)
	var n := 0
	for z in res - 1:
		for x in res - 1:
			var top_left := z * res + x
			var top_right := top_left + 1
			var bottom_left := top_left + res
			var bottom_right := bottom_left + 1
			indices[n] = top_left
			indices[n + 1] = bottom_left
			indices[n + 2] = bottom_right
			indices[n + 3] = bottom_right
			indices[n + 4] = top_right
			indices[n + 5] = top_left
			n += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = array_mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader lifts the waves by up to WaveHeight / 2.
	custom_aabb = array_mesh.get_aabb().grow(WaveHeight)


func _build_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	var wave: Texture2D = _load_texture(WaveTexture)
	if wave == null:
		# LoadWaveTexture: a 32 x 32 texture filled with RColor.CDEFAULTNORMAL
		var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		image.fill(Color8(0x80, 0x80, 0xFF, 0xFF))
		wave = ImageTexture.create_from_image(image)
	_material.set_shader_parameter("wave_vs", wave)
	_material.set_shader_parameter("wave_ps", wave)
	_material.set_shader_parameter("caustics_texture", _load_texture(CausticsTexture))
	# DEFERRED_SHADING: WaterColor and Transparency (FallbackWaterColor is the forward path's).
	_material.set_shader_parameter("water_color", Vector3(WaterColor.x, WaterColor.y, WaterColor.z))
	_material.set_shader_parameter("transparency_value", Transparency)
	_material.set_shader_parameter("sky_color", Vector3(SkyColor.x, SkyColor.y, SkyColor.z))
	_material.set_shader_parameter("wave_height", WaveHeight)
	_material.set_shader_parameter("roughness", Roughness)
	_material.set_shader_parameter("specular_power", Specularpower)
	_material.set_shader_parameter("specular_intensity", Specularintensity)
	_material.set_shader_parameter("size", Size)
	_material.set_shader_parameter("fresnel_offset", FresnelOffset)
	_material.set_shader_parameter("texture_normalization", GeometrySize / 2000.0)
	_material.set_shader_parameter("depth_transparency_range", DepthTransparencyRange)
	_material.set_shader_parameter("refraction_index", RefractionIndex)
	_material.set_shader_parameter("refraction_step_length", RefractionStepLength)
	_material.set_shader_parameter("refraction_steps", RefractionSteps)
	_material.set_shader_parameter("color_extinction_range", ColorExtinctionRange)
	_material.set_shader_parameter("caustics_range", CausticsRange)
	_material.set_shader_parameter("caustics_scale", CausticsScale)
	var xz := Vector2(Position.x, Position.z)
	_material.set_shader_parameter("min_max", Vector4(xz.x - GeometrySize.x / 2, xz.y - GeometrySize.y / 2,
		xz.x + GeometrySize.x / 2, xz.y + GeometrySize.y / 2))
	material_override = _material
	UpdateTime()


static func _load_texture(game_path: String) -> Texture2D:
	if game_path == "":
		return null
	var path := TClientMap.ResolveGamePath(game_path)
	if not ResourceLoader.exists(path):
		push_error("TWaterSurface: texture %s not found (%s)" % [game_path, path])
		return null
	return load(path)


## The shader's TimeTick: TimeManager.GetFloatingTimestamp / 1000 at draw time.
func UpdateTime() -> void:
	_material.set_shader_parameter("time_tick", TTimeManager.GetFloatingTimestamp() / 1000.0)


func _process(_delta: float) -> void:
	UpdateTime()
