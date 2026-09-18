extends "res://tests/test_case.gd"
## Phase 4 map graphics: Delphi's RNG (DelphiRandom), the raw mesh reader (TEngineRawMesh, Engine.Core.Mesh.pas),
## TTerrain (Engine.Terrain.pas), TWaterSurface (Engine.Water.pas), TVegetationManager (Engine.Vegetation.pas) and
## TClientMap (BaseConflict.Map.Client.pas). Tests with map data run only when tools/import_graphics.py has filled
## assets/graphics. Expected roll values come from an independent Python replay of the original's formulas with the
## importer's data (seeds and parameters of the first Classic palm and tuft); grid values from Classic.ter decoded by
## tools/import_map_graphics.py.

const CLASSIC := "res://assets/graphics/maps/classic/classic"
const PALM := "res://assets/graphics/environment/palmtrees/palmtree1.msh"

var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		node.free()
	_nodes.clear()
	TVegetationManager.ClearMeshCache()


func _has_assets() -> bool:
	if FileAccess.file_exists(CLASSIC + ".terrain.json"):
		return true
	print("  (assets/graphics missing: run python tools/import_graphics.py)")
	return false


func _terrain() -> TTerrain:
	var terrain := TTerrain.CreateFromFile(CLASSIC)
	if terrain:
		_nodes.append(terrain)
	return terrain


func _near(a: float, b: float, eps := 1e-4) -> bool:
	return absf(a - b) <= eps


func _near3(a: Vector3, b: Vector3, eps := 1e-4) -> bool:
	return (a - b).length() <= eps


func test_delphi_random_matches_the_rtl_lcg() -> String:
	DelphiRandom.RandSeed = 0
	# RandSeed 0 -> 1: the first Random is 1 / 2^32
	check(_near(DelphiRandom.Random(), 2.3283064365386963e-10, 1e-15), "first Random after RandSeed 0")
	check(_near(DelphiRandom.Random(), 0.031379939522594213, 1e-12), "second Random")
	check_eq(DelphiRandom.RandomRange(100), 86, "Random(100)")
	check_eq(DelphiRandom.RandSeed, -596792289, "RandSeed stays a signed Int32")
	return take_failure()


func test_delphi_random_varied_values_roll_every_axis() -> String:
	DelphiRandom.RandSeed = 12345
	# zero variance still consumes a roll per axis: x, y (variance 1), z
	var v := DelphiRandom.VariedVector3({"Mean": [0, 0, 0], "Variance": [0, 1, 0]})
	check_eq(v.x, 0.0, "x has no variance")
	check_eq(v.z, 0.0, "z has no variance")
	DelphiRandom.RandSeed = 12345
	DelphiRandom.Random()
	var y_roll := DelphiRandom.Random()
	check(_near(v.y, y_roll * 2 - 1), "y is the second roll")
	check_eq(DelphiRandom.RandSeed != 12345, true, "three rolls were used")
	return take_failure()


func test_raw_mesh_reads_the_palm() -> String:
	if not FileAccess.file_exists(PALM):
		print("  (assets/graphics missing: run python tools/import_graphics.py)")
		return ""
	var mesh := TEngineRawMesh.CreateFromFile(PALM)
	check(mesh != null, "palmtree1.msh loads")
	if mesh == null:
		return take_failure()
	check_eq(mesh.MorphTargetCount, 1, "morph targets")
	check_eq(mesh.Positions.size(), 241, "vertices")
	check_eq(mesh.Indices.size(), 876, "indices")
	check(_near(mesh.BoundingSphereRadius, 13.931459426879883), "bounding sphere radius")
	check(_near3(mesh.Positions[0], Vector3(-1.9126167297363281, 2.7234303951263428, -0.3894316256046295)), "first position")
	check(_near3(mesh.Normals[0], Vector3(-0.9514443278312683, -0.23921573162078857, -0.19372543692588806)), "first normal")
	check(mesh.TextureCoordinates[0].is_equal_approx(Vector2(0.6016252040863037, 0.858135461807251)), "first uv")
	check(mesh.Colors[0].is_equal_approx(Vector4(0.12156864255666733, 0.0, 0.025705190375447273, 1.0)), "first color")
	return take_failure()


func test_grid_size_rounds_like_the_original() -> String:
	var t := TTerrain.new()
	_nodes.append(t)
	t.SetGridSize(512)
	check_eq(t.Size, 513, "power of two gets one more node")
	t.SetGridSize(513)
	check_eq(t.Size, 513, "513 rounds down to 512 / 2... + 1")
	t.SetGridSize(100)
	check_eq(t.Size, 65, "100 -> 128 / 2 + 1")
	check_eq(t.GetGridNode(0, 0).Position, Vector3(-0.5, 0, -0.5), "first node at the corner")
	check_eq(t.GetGridNode(64, 64).Position, Vector3(0.5, 0, 0.5), "last node at the other corner")
	return take_failure()


func test_normals_of_a_slope_point_up_the_right_way() -> String:
	var t := TTerrain.new()
	_nodes.append(t)
	t.Scale = Vector3(100, 30, 100)
	t.SetGridSize(16)
	# local height = 0.25 * local x: a slope rising towards +x
	var heights := PackedFloat32Array()
	for x in t.Size:
		for y in t.Size:
			heights.append(0.25 * ((float(x) / (t.Size - 1)) - 0.5))
	t._set_grid_data(heights, t.Size)
	t._compute_normals()
	t._smooth_normals()
	var n: Vector3 = t.GetGridNode(8, 8).Normal
	check(_near3(n, Vector3(-0.25, 1, 0).normalized(), 1e-5), "interior normal of the slope in local space, got %s" % n)
	# GetTerrainHeight is exact on a plane; world height = local * Scale.y
	var p: Vector3 = t.GetTerrainHeight(Vector2(12.3, -7.0))
	check(_near(p.y, 0.25 * (12.3 / 100.0) * 30.0), "height on the slope, got %s" % p.y)
	return take_failure()


func test_classic_terrain_loads_the_grid() -> String:
	if not _has_assets():
		return ""
	var t := _terrain()
	check(t != null, "Classic terrain loads")
	if t == null:
		return take_failure()
	check_eq(t.Size, 513, "grid size")
	check_eq(t.Scale, Vector3(300, 50, 300), "scale")
	check_eq(t.TextureSplits, 2, "texture splits")
	check_eq(t.ChunkTextures.size(), 16, "chunks")
	check_eq(t.get_child_count(), 16, "one mesh per chunk")
	# GridData[256][256] of Classic.ter
	check(_near(t.GetGridNode(256, 256).Position.y, -0.25673431158065796, 1e-7), "center height (local)")
	check(_near3(t.IndexToPosition(256, 256), Vector3(0, -0.25673431158065796 * 50, 0), 1e-4), "center in world space")
	check(_near(t.GetGridNode(0, 0).Normal.length(), 1.0, 1e-5), "normals are unit")
	return take_failure()


func test_chunks_are_row_major_and_mapped_zero_to_one() -> String:
	if not _has_assets():
		return ""
	var t := _terrain()
	check_eq(t._chunk_rect(5), Rect2i(128, 128, 128, 128), "chunk 5 = row 1, column 1")
	check_eq(t._chunk_rect(2), Rect2i(256, 0, 128, 128), "chunk 2 = row 0, column 2 (x)")
	var chunk: MeshInstance3D = t.get_child(5)
	var uvs: PackedVector2Array = chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	check(uvs[0].is_equal_approx(Vector2(0, 0)), "chunk uv starts at 0, got %s" % uvs[0])
	check(uvs[uvs.size() - 1].is_equal_approx(Vector2(1, 1)), "chunk uv ends at 1, got %s" % uvs[uvs.size() - 1])
	check(chunk.get_active_material(0).get_shader_parameter("diffuse_texture").resource_path.ends_with("classic5diffuse.png"), "chunk 5 texture")
	return take_failure()


## Godot's front faces wind clockwise seen from the front: the right-hand cross product of the first triangle's
## edges points away from a viewer above, i.e. down. The original's index order keeps that after the X mirror
## (a capture showed the terrain culled with the order reversed).
func _first_triangle_faces_up(mesh: Mesh) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var i: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return (v[i[1]] - v[i[0]]).cross(v[i[2]] - v[i[0]]).y < 0


func test_terrain_and_water_face_up_in_godot() -> String:
	if not _has_assets():
		return ""
	check(_first_triangle_faces_up((_terrain().get_child(0) as MeshInstance3D).mesh), "terrain triangle faces up")
	var water := TWaterManager.CreateFromFile(CLASSIC + ".water.json")
	_nodes.append(water)
	check(_first_triangle_faces_up(water.Surfaces(0).mesh), "water triangle faces up")
	return take_failure()


func test_classic_water_surface() -> String:
	if not _has_assets():
		return ""
	var water := TWaterManager.CreateFromFile(CLASSIC + ".water.json")
	_nodes.append(water)
	check_eq(water.SurfaceCount(), 1, "one surface")
	var s := water.Surfaces(0)
	check(_near(s.WaveHeight, 0.400000005960464), "WaveHeight from the file")
	check_eq(s.GeometryResolution, 200, "resolution")
	check_eq(s.CausticsTexture, "\\Maps\\Classic\\Caustics.tga", "caustics path as stored")
	var vertices: PackedVector3Array = s.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check_eq(vertices.size(), 200 * 200, "vertex grid")
	var corner := s.Position + Vector3(-0.5 * s.GeometrySize.x, 0, -0.5 * s.GeometrySize.y)
	check(_near3(vertices[0], TMesh.ToGodot(corner)), "first vertex at the (-x, -z) corner in Godot space")
	var material: ShaderMaterial = s.material_override
	check(material.get_shader_parameter("caustics_texture") != null, "caustics texture resolved")
	check(material.get_shader_parameter("texture_normalization").is_equal_approx(s.GeometrySize / 2000.0), "TextureNormalization")
	return take_failure()


func test_resolve_game_path() -> String:
	check_eq(TClientMap.ResolveGamePath("Graphics\\Environment\\Grass\\Grass.tga"), "res://assets/graphics/environment/grass/grass.tga", "graphics path")
	check_eq(TClientMap.ResolveGamePath("\\Maps\\Classic\\WaterTexture.tga"), "res://assets/graphics/maps/classic/watertexture.tga", "map path")
	return take_failure()


func _first(objects: Array, type: String) -> Dictionary:
	for obj: Dictionary in objects:
		if obj.Type == type:
			return obj
	return {}


func test_vegetation_mesh_roll_replays_the_seed() -> String:
	if not _has_assets():
		return ""
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CLASSIC + ".vegetation.json"))
	var palm := _first(data.Objects, "TVegetationMesh")
	var roll := TVegetationManager.RollVegetationMesh(palm)
	check(String(roll.Mesh).ends_with("Palmtree2.fbx"), "Random(2) picks the second mesh, got %s" % roll.Mesh)
	check(_near3(roll.Rotation, Vector3(0, -2.319451786385855, 0)), "rotation roll, got %s" % roll.Rotation)
	check(_near(roll.Size, 0.15659759674890114, 1e-6), "size = Size.Random * Scale / (radius * 2), got %s" % roll.Size)
	return take_failure()


func test_grass_tuft_replays_the_seed() -> String:
	if not _has_assets():
		return ""
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CLASSIC + ".vegetation.json"))
	var tuft := _first(data.Objects, "TGrassTuft")
	var vertices := TVegetationManager.GrassTuftVertices(tuft)
	check_eq(vertices.size(), 12, "3 shields x 4 vertices")
	check(_near3(vertices[0].Position, Vector3(-105.86936652306862, 0.4687135282849587, 43.724968767766434), 1e-4),
		"first shield's lt, got %s" % vertices[0].Position)
	check(_near(vertices[0].Custom.x, 0.8389928573742509, 1e-6), "time offset is the last roll")
	check_eq(vertices[2].Custom.z, 0.0, "bottom vertices do not sway")
	return take_failure()


func test_rotation_pitch_yaw_roll_follows_the_original_matrix() -> String:
	# RotationY rows [[c, 0, -s], [0, 1, 0], [s, 0, c]]: +x turns towards +z for a positive yaw
	var b := TVegetationManager.RotationPitchYawRoll(Vector3(0, PI / 2, 0))
	check(_near3(b * Vector3(1, 0, 0), Vector3(0, 0, 1)), "yaw turns x to z, got %s" % (b * Vector3(1, 0, 0)))
	# RotationX rows [[1, 0, 0], [0, c, s], [0, -s, c]]
	var p := TVegetationManager.RotationPitchYawRoll(Vector3(PI / 2, 0, 0))
	check(_near3(p * Vector3(0, 1, 0), Vector3(0, 0, -1)), "pitch turns y to -z, got %s" % (p * Vector3(0, 1, 0)))
	return take_failure()


func test_client_map_builds_every_layer() -> String:
	if not _has_assets():
		return ""
	var map := TClientMap.CreateFromFile("Single")
	_nodes.append(map)
	check(map.Terrain != null and map.Terrain.get_child_count() == 16, "terrain chunks")
	check_eq(map.Water.SurfaceCount(), 1, "water surface")
	var palms := 0
	var tufts := 0
	for child in map.Vegetation.get_children():
		if child is MultiMeshInstance3D:
			palms += (child as MultiMeshInstance3D).multimesh.instance_count
		elif child is MeshInstance3D:
			tufts += (child as MeshInstance3D).mesh.surface_get_array_len(0) / 12
	check_eq(palms, 2425, "every palm of Single.veg")
	check_eq(tufts, 1435, "every tuft of Single.veg")
	return take_failure()
