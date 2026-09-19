extends "res://tests/test_case.gd"
## Phase 4 graphics: TMesh (Engine.Mesh.pas) path resolution, material flags and placement, TLightManager
## (BaseConflict.Map.Client.pas) and the light upload. Mesh loading runs only when tools/import_graphics.py has
## filled assets/graphics (it is generated on setup, not committed).

const FOOTMAN := "Units\\White\\Footman_Default\\Footman.xml"
const CRYSTAL := "Units\\Neutral\\Nexus\\NexusCrystal.xml"

var _meshes: Array[Node] = []


func after_each() -> void:
	for m in _meshes:
		m.free()
	_meshes.clear()
	TMesh.ClearGeometryCache()


func _load(path: String) -> TMesh:
	var mesh := TMesh.CreateFromFile(path)
	if mesh:
		_meshes.append(mesh)
	return mesh


func test_resolve_descriptor_is_case_and_slash_insensitive() -> String:
	check_eq(TMesh.ResolveDescriptor(FOOTMAN), "res://assets/graphics/units/white/footman_default/footman.mesh.json", "backslashes")
	check_eq(TMesh.ResolveDescriptor("\\units//WHITE\\Footman_Default/footman.XML"),
		"res://assets/graphics/units/white/footman_default/footman.mesh.json", "doubled slashes, case")
	return take_failure()


func test_to_godot_mirrors_x() -> String:
	check_eq(TMesh.ToGodot(Vector3(1, 2, 3)), Vector3(-1, 2, 3), "mirror")
	return take_failure()


func test_material_flags_follow_trawmesh() -> String:
	var m := TMesh.new()
	_meshes.append(m)
	check(not m.HasAlpha(), "opaque by default")
	m.Alpha = 0.99999998430675
	check(m.HasAlpha(), "Alpha < 1 is alpha (6 descriptors store 0.99999998)")
	m.Alpha = 1.0
	m.TextureSemiTransparency = true
	check(m.HasAlpha(), "TextureSemiTransparency is alpha")
	check(not m.HasMaterialSettings(), "no material settings")
	m.ShadingReductionOverride = 0.5
	check(m.HasMaterialSettings(), "the override counts (TMeshComponent sets 0.5)")
	return take_failure()


func test_placement_conjugates_the_base() -> String:
	var m := TMesh.new()
	_meshes.append(m)
	m.Position = Vector3(3, 0, 5)
	m.Front = Vector3(1, 0, 0)  # game +X
	m.ScaleVector = Vector3(2, 2, 2)
	m.ComputeTransformationMatrix()
	check_eq(m.transform.origin, Vector3(-3, 0, 5), "origin")
	# Local +Z (the model's front) points to game +X, which is Godot -X.
	check(m.transform.basis.z.is_equal_approx(Vector3(-2, 0, 0)), "front: %s" % m.transform.basis.z)
	check(m.transform.basis.y.is_equal_approx(Vector3(0, 2, 0)), "up: %s" % m.transform.basis.y)
	return take_failure()


func test_light_manager_reads_the_classic_lig() -> String:
	var lights := TLightManager.CreateFromMap("Classic")
	check(lights.Ambient.is_equal_approx(Vector4(1, 1, 1, 0.772000014781952)), "ambient %s" % lights.Ambient)
	check_eq(lights.DirectionalLights.size(), 3, "lights")
	check(lights.DirectionalLights[0].Enabled and not lights.DirectionalLights[1].Enabled, "enabled flags")
	var d: Vector3 = lights.DirectionalLights[0].Direction
	check(d.is_equal_approx(Vector3(-0.024, -0.672, -0.368).normalized()), "normalized direction %s" % d)
	var parameters := lights.ShaderParameters()
	check_eq(parameters.rol_light_count, 1, "only the enabled light")
	check(not parameters.has("rol_light_dir_1"), "disabled lights are skipped")
	var to_light: Vector3 = parameters.rol_light_dir_0
	check(to_light.is_equal_approx(TMesh.ToGodot(-d)), "negated, Godot space: %s" % to_light)
	var ambient: Vector3 = parameters.rol_ambient
	check(ambient.is_equal_approx(Vector3.ONE * 0.772000014781952), "premultiplied ambient %s" % ambient)
	return take_failure()


func test_footman_mesh_loads_with_its_descriptor() -> String:
	if not TMesh.Exists(FOOTMAN):
		print("  (assets/graphics missing: run python tools/import_graphics.py)")
		return ""
	var mesh := _load(FOOTMAN)
	check(mesh != null, "loaded")
	check_eq(mesh.DiffuseTexture, "footmandiffuse.tga", "diffuse")
	check_eq(mesh.MaterialTexture, "footmanmaterial.tga", "material texture")
	check_eq(mesh.SpecularPower, 128.0, "specular power")
	check_eq(mesh.GeometryFile, "footman.msh", "the raw mesh release builds load (LOAD_RAW_MESH)")
	check_eq(mesh.MeshInstances.size(), 1, "one surface (the raw mesh holds the collapsed subsets)")
	check_eq(mesh.FrameCount(), 122, "take length (the script's walk ends at frame 122)")
	check_eq(mesh.AnimationDriverBone.SkinLinkCount(), 24, "24 skin links")
	# footman.msh header: RAABB Min (-37.77591, 0.120251, -12.4349), size y 86.14995 (file units)
	var box := mesh.GetUntransformedBoundingBox()
	check(absf(box.size.y - 86.14995) < 0.001, "raw height %s" % box.size.y)
	return take_failure()


## TEngineRawMesh: nexuscrystal.msh (Graphics\Units\Neutral\Nexus) read to its end: 9 bones from RootNode, one skin
## link, one take of 201 keyframes. Its raw vertices lie below the ground (y -70.2 .. -35.8); the take's bones lift it
## over the nexus base (whose box ends at y 14.175, nexus.msh): the crystal floats.
func test_raw_mesh_bones_lift_the_nexus_crystal() -> String:
	if not TMesh.Exists(CRYSTAL):
		return ""
	var mesh := _load(CRYSTAL)
	check_eq(mesh.AnimationDriverBone.BoneCount(), 9, "bones")
	check_eq(mesh.AnimationDriverBone.BoneIndex("RootNode"), 0, "root")
	check_eq(mesh.AnimationDriverBone.SkinLinkCount(), 1, "skin links")
	check_eq(mesh.FrameCount(), 200, "keyframes 0..200")
	var raw := mesh.GetUntransformedBoundingBox()
	check(absf(raw.position.y - (-70.16459)) < 0.001, "raw bottom %s" % raw.position.y)
	mesh.ShowFrame(0)
	var posed := mesh.GetPosedBoundingBox()
	check(posed.position.y > 14.175, "posed above the base: %s" % posed.position.y)
	check(absf(posed.size.y - raw.size.y) < 0.01, "moved, not stretched")
	return take_failure()


## TMesh.Release of a skinned mesh in a scene: the controller drops its drivers at once, the node leaves the tree at the
## end of the frame, and that frame's animation and bone upload must still run without errors (the runner fails on any
## script error). The runner's tree does not run frames, so the test takes Release's steps before the deferred free.
func test_released_skinned_mesh_draws_its_last_frame() -> String:
	if not TMesh.Exists(FOOTMAN):
		return ""
	var mesh := _load(FOOTMAN)
	mesh.AnimationController.Clear()
	mesh.AnimationDriverMorph = null
	GFXD.NextFrame()
	mesh.Animate()
	mesh.SetUpCustomShaders()
	check(mesh.TryGetBonePosition("RootNode") != null, "the bones answer until the mesh is gone")
	return take_failure()
