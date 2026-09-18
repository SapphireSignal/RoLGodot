extends SceneTree
## Lists what Godot's FBX import made of every mesh in assets/graphics (not a test: run it by hand after
## tools/import_graphics.py and an --import).
##   Godot_console.exe --headless --path . --log-file <abs> --script res://tests/inspect_meshes.gd
## One line per FBX: root scale, meshes, skeleton bones, animations (name, frames at 30 fps), the AABB of the
## meshes in scene space, and tracks holding non-finite values. INSPECT_ONLY (env) filters by path substring.


func _init() -> void:
	var only := OS.get_environment("INSPECT_ONLY").to_lower()
	var files: Array[String] = []
	_collect("res://assets/graphics", files)
	files.sort()
	for path in files:
		if only != "" and not path.contains(only):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			print("LOAD FAILED ", path)
			continue
		var root := scene.instantiate()
		print(_describe(path, root))
		root.free()
	quit(0)


func _collect(dir: String, into: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + sub, into)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".fbx"):
			into.append(dir + "/" + file)


func _describe(path: String, root: Node) -> String:
	var meshes: Array[MeshInstance3D] = []
	var skeletons: Array[Skeleton3D] = []
	var players: Array[AnimationPlayer] = []
	_walk(root, meshes, skeletons, players)
	var aabb := AABB()
	var first := true
	for mi in meshes:
		var box := _global_of(mi) * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	var bones := 0
	for sk in skeletons:
		bones += sk.get_bone_count()
	var anims: Array[String] = []
	var bad_tracks := 0
	for player in players:
		for name in player.get_animation_list():
			var anim := player.get_animation(name)
			anims.append("%s:%d" % [name, roundi(anim.length * 30.0)])
			bad_tracks += _non_finite_tracks(anim)
	var scale := (root as Node3D).transform.basis.get_scale() if root is Node3D else Vector3.ONE
	return "%s | root %s | %d meshes %d surfaces | %d bones | anims %s | aabb %s | non-finite tracks %d" % [
		path.trim_prefix("res://assets/graphics/"), scale, meshes.size(), _surfaces(meshes), bones, anims, aabb, bad_tracks]


func _walk(node: Node, meshes: Array[MeshInstance3D], skeletons: Array[Skeleton3D], players: Array[AnimationPlayer]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
	if node is Skeleton3D:
		skeletons.append(node)
	if node is AnimationPlayer:
		players.append(node)
	for child in node.get_children():
		_walk(child, meshes, skeletons, players)


func _global_of(node: Node3D) -> Transform3D:
	var t := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		t = (parent as Node3D).transform * t
		parent = parent.get_parent()
	return t


func _surfaces(meshes: Array[MeshInstance3D]) -> int:
	var n := 0
	for mi in meshes:
		n += mi.mesh.get_surface_count() if mi.mesh else 0
	return n


func _non_finite_tracks(anim: Animation) -> int:
	var bad := 0
	for t in anim.get_track_count():
		for k in anim.track_get_key_count(t):
			var v: Variant = anim.track_get_key_value(t, k)
			var s := str(v)
			if s.contains("nan") or s.contains("inf"):
				bad += 1
				break
	return bad
