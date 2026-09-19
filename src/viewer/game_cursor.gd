extends RefCounted
## The game's mouse cursors (BaseConflictMainUnit.pas:162 LoadCursor: Graphics/GUI/Cursors, imported by
## tools/import_graphics.py). Windows hardware cursors like the original's: crIngame (Default) in the game window,
## crIngameHover (Hover) over clickable and writable GUI elements (TGameStateManager, BaseConflict.Classes.Gamestates.pas
## :2316-2343). Apply(tree) sets them and gives every button and text field the hover shape, also those added later.

const FOLDER := "res://assets/graphics/gui/cursors/"


static func Apply(tree: SceneTree) -> void:
	if not FileAccess.file_exists(FOLDER + "cursors.json"):
		push_warning("GameCursor: %s is missing (run tools/import_graphics.py)" % FOLDER)
		return
	var hotspots: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "cursors.json"))
	var default_cursor: Texture2D = load(FOLDER + "default.png")
	var hover_cursor: Texture2D = load(FOLDER + "hover.png")
	Input.set_custom_mouse_cursor(default_cursor, Input.CURSOR_ARROW, _hotspot(hotspots, "default"))
	for shape in [Input.CURSOR_POINTING_HAND, Input.CURSOR_IBEAM]:
		Input.set_custom_mouse_cursor(hover_cursor, shape, _hotspot(hotspots, "hover"))
	_mark(tree.root)
	if not tree.node_added.is_connected(_mark_one):
		tree.node_added.connect(_mark_one)


static func _hotspot(hotspots: Dictionary, name: String) -> Vector2:
	var pair: Array = hotspots.get(name, [0, 0])
	return Vector2(pair[0], pair[1])


static func _mark(node: Node) -> void:
	_mark_one(node)
	for child in node.get_children():
		_mark(child)


## Clickable (buttons, check boxes, sliders) -> the hover cursor; writable (text fields) -> the hover cursor too.
static func _mark_one(node: Node) -> void:
	if node is BaseButton or node is Slider:
		(node as Control).mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	elif node is LineEdit or node is TextEdit:
		(node as Control).mouse_default_cursor_shape = Control.CURSOR_IBEAM
