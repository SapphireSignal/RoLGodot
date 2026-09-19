extends Control
## Entry scene. Placeholder until the client boot flow (splash, login, main menu) is ported; offers the dev viewers.
const GameCursor = preload("res://src/viewer/game_cursor.gd")

const VIEWERS := [["Mesh viewer", "res://src/viewer/mesh_viewer.tscn"], ["Map viewer", "res://src/viewer/map_viewer.tscn"]]


func _ready() -> void:
	GameCursor.Apply(get_tree())
	print("RoLGodot boot: %s" % ProjectSettings.get_setting("application/config/name"))
	var buttons := {}
	var center := get_viewport_rect().size / 2.0
	for i in VIEWERS.size():
		var entry: Array = VIEWERS[i]
		var button := Button.new()
		button.text = entry[0]
		button.position = Vector2(center.x - 80.0, center.y + 40.0 + i * 50.0)
		button.custom_minimum_size = Vector2(160, 40)
		var scene: String = entry[1]
		button.pressed.connect(func() -> void: get_tree().change_scene_to_file(scene))
		add_child(button)
		buttons[String(entry[0]).get_slice(" ", 0).to_lower()] = button
	# Launcher smoke test (tools/run_tests.ps1): press a viewer button like a player would (--smoke-viewer=mesh|map,
	# default mesh); the viewer reports back.
	var smoke := false
	var target := "mesh"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--smoke-test="):
			smoke = true
		elif arg.begins_with("--smoke-viewer="):
			target = arg.get_slice("=", 1)
	if smoke and buttons.has(target):
		(buttons[target] as Button).pressed.emit.call_deferred()
