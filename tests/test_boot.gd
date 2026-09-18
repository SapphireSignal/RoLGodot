extends "res://tests/test_case.gd"


func test_main_scene_loads() -> void:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var scene = load(path)
	check(scene is PackedScene, "main scene %s does not load" % path)
