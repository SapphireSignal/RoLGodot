class_name TTerrain
extends Node3D
## Engine.Terrain.pas TTerrain: the map's heightmap ground. Loaded from the importer's output of <Map>.ter
## (tools/import_map_graphics.py: <map>.terrain.json settings + <map>.terrain.bin heights). Read docs/assets.md
## ("Terrain").
##
## Grid: Size x Size nodes, local position ((x / (Size - 1)) - 0.5, height, (y / (Size - 1)) - 0.5), world position
## local * Scale + Position (game space). Node normals: GridActionComputeNormal then GridActionSmoothNormal (in place,
## x outer, y inner: later nodes average already smoothed neighbours, like the original).
## Drawn with one surface per chunk texture (TextureSplits 2 -> 4 x 4 chunks; chunk i = layer id row * 4 + col),
## at full detail: the original's geomipmapping (TQuadTreeNode LoD by camera distance) is not ported (docs/assets.md).

const SHADER_PATH := "res://src/runtime/graphics/terrain.gdshader"
const TILESIZE := 64

## Describes the dimension of the terrain in each axis (game space).
var Scale := Vector3(100, 30, 100)
## The center of the terrain (game space).
var Position := Vector3.ZERO
var TextureSplits := 1
var ShadingReduction := 0.0
var Geomipmapdistanceerror := 0.02
var Geomipmapnormalerror := 3.3
## Nodes per axis.
var Size := 0
## Chunk texture file names per chunk id: [diffuse, normal, material] (res:// paths).
var ChunkTextures: Array = []

## Grid data, index x + y * Size (the original's vertex buffer order), local game space.
var _positions := PackedVector3Array()
var _normals := PackedVector3Array()
var _virtual_bounding_box := AABB()


## TTerrain.CreateFromFile: `base_path` is the importer's output without extension, e.g.
## res://assets/graphics/maps/classic/classic (reads .terrain.json and .terrain.bin). Returns null when missing.
static func CreateFromFile(base_path: String) -> TTerrain:
	var settings: Variant = JSON.parse_string(FileAccess.get_file_as_string(base_path + ".terrain.json"))
	var grid := FileAccess.get_file_as_bytes(base_path + ".terrain.bin")
	if not settings is Dictionary or grid.is_empty():
		push_error("TTerrain: cannot load %s" % base_path)
		return null
	var terrain := TTerrain.new()
	terrain.name = "Terrain"
	terrain._load(settings, grid, base_path.get_base_dir(), base_path.get_file())
	return terrain


func _load(settings: Dictionary, grid: PackedByteArray, folder: String, map_file: String) -> void:
	var s: Array = settings.Scale
	var p: Array = settings.Position
	Scale = Vector3(s[0], s[1], s[2])
	Position = Vector3(p[0], p[1], p[2])
	TextureSplits = int(settings.TextureSplits)
	ShadingReduction = float(settings.ShadingReduction)
	Geomipmapdistanceerror = float(settings.Geomipmapdistanceerror)
	Geomipmapnormalerror = float(settings.Geomipmapnormalerror)
	# TChunkTexture.CustomAfterXMLCreate: ChangeFileExt(TerrainFile, ChunkID + 'Diffuse.png') etc.
	ChunkTextures.clear()
	for id: float in settings.ChunkIDs:
		var stem := "%s/%s%d" % [folder, map_file, int(id)]
		ChunkTextures.append([stem + "diffuse.png", stem + "normal.png", stem + "material.png"])
	_set_grid_data(grid.to_float32_array(), int(settings.GridSize))
	GridDataEvaluation()


## setGridData: heights GridData[x][y] (x-major).
func _set_grid_data(heights: PackedFloat32Array, grid_length: int) -> void:
	SetGridSize(grid_length)
	for x in Size:
		for y in Size:
			var i := x + y * Size
			var node := _positions[i]
			node.y = heights[x * grid_length + y]
			_positions[i] = node


## Naechste2erPotenz: the smallest power of two >= value.
static func NextPowerOfTwo(value: int) -> int:
	var result := 1
	while result < value:
		result <<= 1
	return result


## SetGridSize: a power of two gets one more node, anything else rounds down to (power of two / 2) + 1.
func SetGridSize(requested: int) -> void:
	var size := requested + 1 if NextPowerOfTwo(requested) == requested else (NextPowerOfTwo(requested) >> 1) + 1
	Size = size
	_positions.resize(size * size)
	_normals.resize(size * size)
	for x in size:
		for y in size:
			_positions[x + y * size] = Vector3((float(x) / (size - 1)) - 0.5, 0.0, (float(y) / (size - 1)) - 0.5)
			_normals[x + y * size] = Vector3(0, 1, 0)


## getGridNode's clamping.
func _index(x: int, y: int) -> int:
	return clampi(x, 0, Size - 1) + clampi(y, 0, Size - 1) * Size


## GridDataEvaluation without the GPU buffers: normals, smoothing, bounding box, then the Godot mesh.
func GridDataEvaluation() -> void:
	_compute_normals()
	_smooth_normals()
	_virtual_bounding_box = AABB(_positions[0], Vector3.ZERO)
	for position in _positions:
		_virtual_bounding_box = _virtual_bounding_box.expand(position)
	_build_mesh()


## GridActionComputeNormal over the whole grid (reads positions only).
func _compute_normals() -> void:
	for x in Size:
		for y in Size:
			var c := _positions[x + y * Size]
			var left := _positions[_index(x - 1, y)] - c
			var top := _positions[_index(x, y - 1)] - c
			var right := _positions[_index(x + 1, y)] - c
			var bottom := _positions[_index(x, y + 1)] - c
			var sum := left.cross(top).normalized() + top.cross(right).normalized()
			sum += right.cross(bottom).normalized() + bottom.cross(left).normalized()
			_normals[x + y * Size] = -sum.normalized()


## GridActionSmoothNormal over the whole grid, in place (DoGridAction: x outer, y inner).
func _smooth_normals() -> void:
	for x in Size:
		for y in Size:
			var sum := Vector3.ZERO
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					sum += _normals[_index(x + dx, y + dy)]
			_normals[x + y * Size] = sum.normalized()


## getGridNode(x, y) (clamped): {Position, Normal} in local game space.
func GetGridNode(x: int, y: int) -> Dictionary:
	var i := _index(x, y)
	return {"Position": _positions[i], "Normal": _normals[i]}


func GridNodeSize() -> float:
	return (Scale.x * 2) / Size


## IndexToPosition: world (game space) position of a grid node (clamped).
func IndexToPosition(x: int, y: int) -> Vector3:
	return _positions[_index(x, y)] * Scale + Position


## IndexToNormal: the node normal divided by Scale (not normalized, like the original).
func IndexToNormal(x: int, y: int) -> Vector3:
	return _normals[_index(x, y)] / Scale


## PositionToIndex: the grid node of the quad a world position lies in (clamped to the grid).
func PositionToIndex(pos: Vector3) -> Vector2i:
	var relative := Vector2(pos.x / Scale.x - Position.x, pos.z / Scale.z - Position.z)
	relative = relative.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	return Vector2i(clampi(int((relative.x + 0.5) * (Size - 1)), 0, Size - 1),
		clampi(int((relative.y + 0.5) * (Size - 1)), 0, Size - 1))


## PositionToRelativeCoord: 0..1 over the terrain.
func PositionToRelativeCoord(pos: Vector3, clamp_to_terrain := true) -> Vector2:
	var relative := Vector2(pos.x / Scale.x - Position.x, pos.z / Scale.z - Position.z)
	if clamp_to_terrain:
		relative = relative.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	return relative + Vector2(0.5, 0.5)


## GetTerrainHeight: the surface point below the game-space xz position (barycentric in the quad's triangle).
## ClampToBorder false keeps the given x and z. With `with_normal` returns [point, normal].
func GetTerrainHeight(xz: Vector2, clamp_to_border := false, with_normal := false) -> Variant:
	var a := PositionToIndex(Vector3(xz.x, 0, xz.y))
	var b := a + Vector2i(1, 1)
	var node1 := IndexToPosition(a.x, a.y)
	var node2 := IndexToPosition(b.x, b.y)
	var u := clampf((xz.x - node1.x) / _prevent_zero(node2.x - node1.x), 0.0, 1.0)
	var v := clampf((xz.y - node1.z) / _prevent_zero(node2.z - node1.z), 0.0, 1.0)
	var result: Vector3
	if 1 > u + v:
		result = _barycentric(IndexToPosition(a.x, a.y), IndexToPosition(a.x + 1, a.y), IndexToPosition(a.x, a.y + 1), u, v)
	else:
		result = _barycentric(IndexToPosition(b.x, b.y), IndexToPosition(b.x - 1, b.y), IndexToPosition(b.x, b.y - 1), 1 - u, 1 - v)
	if not clamp_to_border:
		result.x = xz.x
		result.z = xz.y
	if not with_normal:
		return result
	var normal: Vector3
	if 1 > u + v:
		normal = _barycentric(IndexToNormal(a.x, a.y), IndexToNormal(a.x + 1, a.y), IndexToNormal(a.x, a.y + 1), u, v).normalized()
	else:
		normal = _barycentric(IndexToNormal(b.x, b.y), IndexToNormal(b.x - 1, b.y), IndexToNormal(b.x, b.y - 1), 1 - u, 1 - v).normalized()
	return [result, normal]


static func _prevent_zero(s: float) -> float:
	return 0.001 if s == 0 else s


## RVector3.BaryCentric.
static func _barycentric(v1: Vector3, v2: Vector3, v3: Vector3, f: float, g: float) -> Vector3:
	return v1 + f * (v2 - v1) + g * (v3 - v1)


## IntersectRayTerrain: steps along the ray by GridNodeSize, then refines in 20 substeps (game space).
func IntersectRayTerrain(start: Vector3, direction: Vector3) -> Vector3:
	var result := Vector3.ZERO
	direction = direction.normalized()
	start += direction * (start.distance_to(Position) - (Scale.length() / 2))
	direction = direction.normalized() * GridNodeSize()
	for step in 1000:
		start += direction
		result = GetTerrainHeight(Vector2(start.x, start.z))
		if result.y >= start.y:
			start -= direction
			direction /= 20
			for i in 21:
				start += direction
				result = GetTerrainHeight(Vector2(start.x, start.z))
				if result.y >= start.y:
					break
			return result
	return result


## GetBoundingBox (game space).
func GetBoundingBox() -> AABB:
	return AABB(_virtual_bounding_box.position * Scale + Position, _virtual_bounding_box.size * Scale)


## The chunk layer ids the quadtree assigns at depth TextureSplits: row-major over (1 shl TextureSplits)^2 tiles.
func _chunk_rect(chunk: int) -> Rect2i:
	var per_row := 1 << TextureSplits
	var cells := (Size - 1) / per_row
	return Rect2i((chunk % per_row) * cells, (chunk / per_row) * cells, cells, cells)


## One MeshInstance3D per chunk. Vertices in Godot space (TMesh.ToGodot of the world position); per vertex the
## shader gets the world normal (Normal / Scale, WorldInverseTranspose), tangent and binormal (* Scale, World):
## GridNodeToVertex's Tangent = -Normal x UNITX, Binormal = Normal x Tangent, both normalized.
func _build_mesh() -> void:
	for child in get_children():
		child.queue_free()
	var shader: Shader = load(SHADER_PATH)
	for chunk in ChunkTextures.size():
		var rect := _chunk_rect(chunk)
		var side := rect.size.x + 1
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var tangents := PackedFloat32Array()
		var binormals := PackedFloat32Array()
		var uvs := PackedVector2Array()
		vertices.resize(side * side)
		normals.resize(side * side)
		uvs.resize(side * side)
		tangents.resize(side * side * 4)
		binormals.resize(side * side * 4)
		# TQuadTreeNode.RenderTiles: TextureOffset = -LeftTop / Size, TextureScale = 1 / Size of the relative rect.
		var rel_pos := Vector2(rect.position) / (Size - 1)
		var rel_size := Vector2(rect.size) / (Size - 1)
		for ly in side:
			for lx in side:
				var i := (rect.position.x + lx) + (rect.position.y + ly) * Size
				var local := _positions[i]
				var normal := _normals[i]
				var tangent := (-normal.cross(Vector3(1, 0, 0))).normalized()
				var binormal := normal.cross(tangent).normalized()
				var v := lx + ly * side
				vertices[v] = TMesh.ToGodot(local * Scale + Position)
				normals[v] = TMesh.ToGodot((normal / Scale).normalized())
				var t := TMesh.ToGodot((tangent * Scale).normalized())
				var b := TMesh.ToGodot((binormal * Scale).normalized())
				tangents[v * 4] = t.x
				tangents[v * 4 + 1] = t.y
				tangents[v * 4 + 2] = t.z
				tangents[v * 4 + 3] = 1.0
				binormals[v * 4] = b.x
				binormals[v * 4 + 1] = b.y
				binormals[v * 4 + 2] = b.z
				binormals[v * 4 + 3] = 0.0
				# TextureCoordinate = Position.xz + 0.5, then the texture transform
				uvs[v] = (Vector2(local.x, local.z) + Vector2(0.5, 0.5) - rel_pos) / rel_size
		var indices := PackedInt32Array()
		indices.resize(rect.size.x * rect.size.y * 6)
		var n := 0
		for ly in rect.size.y:
			for lx in rect.size.x:
				var a := lx + ly * side
				# getIndexbuffer's quad (x,y) (x,y+1) (x+1,y) | (x+1,y) (x,y+1) (x+1,y+1), unchanged: the original's
				# clockwise front faces (D3D, left-handed) stay front faces in Godot after the X mirror.
				indices[n] = a
				indices[n + 1] = a + side
				indices[n + 2] = a + 1
				indices[n + 3] = a + 1
				indices[n + 4] = a + side
				indices[n + 5] = a + side + 1
				n += 6
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_CUSTOM0] = binormals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		var format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
		var material := ShaderMaterial.new()
		material.shader = shader
		var files: Array = ChunkTextures[chunk]
		material.set_shader_parameter("diffuse_texture", load(files[0]))
		material.set_shader_parameter("normal_texture", load(files[1]))
		material.set_shader_parameter("material_texture", load(files[2]))
		material.set_shader_parameter("shading_reduction", ShadingReduction)
		mesh.surface_set_material(0, material)
		var instance := MeshInstance3D.new()
		instance.name = "Chunk%d" % chunk
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # TClientMap.Idle: CastsNoShadow
		add_child(instance)
