@tool
extends EditorScenePostImport
## Post-import step for the original's FBX files (set by tools/import_graphics.py in every .fbx.import).
##
## Three files (ForestGuardian, MeleeGolemTower, AttackBoss) animate a "...Stone" bone whose FBX rotation curves
## and default rotation are NaN. The original's assimp passes the NaN on, the bone matrix turns NaN and the GPU drops
## every triangle that bone moves, so the stone is never drawn. Godot would instead fill the logs with NaN errors
## every frame. This step gives such bones a finite identity rotation and a vanishing scale (rest pose and every
## key), which draws the same thing: nothing. Read docs/assets.md ("NaN bones").

const VANISHED := Vector3(1e-6, 1e-6, 1e-6)


func _post_import(scene: Node) -> Object:
	var broken := {}
	for skeleton: Skeleton3D in scene.find_children("*", "Skeleton3D", true, false):
		for bone in skeleton.get_bone_count():
			var rest := skeleton.get_bone_rest(bone)
			if not rest.basis.is_finite():
				skeleton.set_bone_rest(bone, Transform3D(Basis.from_scale(VANISHED), rest.origin))
				skeleton.reset_bone_pose(bone)
				broken[skeleton.get_bone_name(bone)] = true
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name)
			for animation_name in library.get_animation_list():
				_repair(library.get_animation(animation_name), broken)
	return scene


func _repair(animation: Animation, broken: Dictionary) -> void:
	var paths := {}
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(animation.track_get_path(track).get_concatenated_subnames())
		var finite := not broken.has(bone)
		for key in animation.track_get_key_count(track):
			finite = finite and (animation.track_get_key_value(track, key) as Quaternion).is_finite()
		if not finite:
			paths[animation.track_get_path(track)] = true
	for track in animation.get_track_count():
		if not paths.has(animation.track_get_path(track)):
			continue
		var type := animation.track_get_type(track)
		for key in animation.track_get_key_count(track):
			if type == Animation.TYPE_ROTATION_3D:
				animation.track_set_key_value(track, key, Quaternion.IDENTITY)
			elif type == Animation.TYPE_SCALE_3D:
				animation.track_set_key_value(track, key, VANISHED)
