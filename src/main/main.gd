extends Control
## Entry scene. Placeholder until the client boot flow (splash, login, main menu) is ported; offers the dev viewers.


func _ready() -> void:
	print("RoLGodot boot: %s" % ProjectSettings.get_setting("application/config/name"))
	var viewer := Button.new()
	viewer.text = "Mesh viewer"
	viewer.position = Vector2(get_viewport_rect().size.x / 2.0 - 80.0, get_viewport_rect().size.y / 2.0 + 40.0)
	viewer.custom_minimum_size = Vector2(160, 40)
	viewer.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://src/viewer/mesh_viewer.tscn"))
	add_child(viewer)
	# Launcher smoke test (tools/run_tests.ps1): press the button like a player would; the viewer reports back.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--smoke-test="):
			viewer.pressed.emit.call_deferred()
