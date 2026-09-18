extends Node3D
## Mesh viewer (phase 4 check): every mesh the importer brought over, drawn with the port's TMesh and the Classic
## map's lights. Left: the list (type to filter). Drag with the left mouse button to orbit, wheel to zoom.
## Space plays / pauses the file's animation take, the slider picks a frame.
## Capture mode (for checking renders without a person): run with
##   -- --capture=<substring>[,<substring>...] --capture-out=<absolute folder>
## to write one PNG per matching mesh (and a few turned views of it), then quit.

const ALL_MESHES_ROOT := "res://assets/graphics"

var _paths: Array[String] = []
var _mesh: TMesh
var _pivot: Node3D
var _camera: Camera3D
var _yaw := 0.6
var _pitch := -0.35
var _distance := 4.0
var _dragging := false
var _playing := false
var _frame := 0.0

var _list: ItemList
var _filter: LineEdit
var _info: Label
var _slider: HSlider
var _frame_label: Label
var _play_button: Button
var _reduction: CheckBox


func _ready() -> void:
	TLightManager.CreateFromMap("Classic").SynchronizeLightWithGFXD()
	_collect(ALL_MESHES_ROOT, _paths)
	_paths.sort()
	_build_scene()
	_build_ui()
	_refresh_list()
	var capture := _user_arg("capture")
	if capture != "" and _user_arg("turntable") != "":
		_run_turntable.call_deferred(capture.split(","), _user_arg("capture-out"), int(_user_arg("turntable")))
	elif capture != "":
		_run_capture.call_deferred(capture.split(","), _user_arg("capture-out"))
	elif not _paths.is_empty():
		_show(_paths[0])


func _user_arg(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.substr(name.length() + 3)
	return ""


func _collect(dir: String, into: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + sub, into)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(TMesh.DESCRIPTOR_SUFFIX):
			into.append(dir + "/" + file)


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.2, 0.24)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(env)
	_pivot = Node3D.new()
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.near = 0.01
	_camera.far = 500.0
	add_child(_camera)
	_update_camera()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.custom_minimum_size = Vector2(380, 0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var back := Button.new()
	back.text = "Back to main"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://src/main/main.tscn"))
	box.add_child(back)
	_filter = LineEdit.new()
	_filter.placeholder_text = "filter (e.g. white/footman)"
	_filter.text_changed.connect(func(_t: String) -> void: _refresh_list())
	box.add_child(_filter)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(360, 520)
	_list.item_selected.connect(func(i: int) -> void: _show(_list.get_item_metadata(i)))
	box.add_child(_list)
	_reduction = CheckBox.new()
	_reduction.text = "unit shading (ShadingReductionOverride 0.5)"
	_reduction.button_pressed = true
	_reduction.toggled.connect(func(_on: bool) -> void: _apply_reduction())
	box.add_child(_reduction)
	var anim := HBoxContainer.new()
	box.add_child(anim)
	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.pressed.connect(_toggle_play)
	anim.add_child(_play_button)
	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(220, 0)
	_slider.step = 1.0
	_slider.value_changed.connect(func(v: float) -> void:
		_frame = v
		_show_frame())
	anim.add_child(_slider)
	_frame_label = Label.new()
	anim.add_child(_frame_label)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(360, 0)
	box.add_child(_info)


func _refresh_list() -> void:
	_list.clear()
	var needle := _filter.text.to_lower()
	for path in _paths:
		var short := path.trim_prefix(ALL_MESHES_ROOT + "/").trim_suffix(TMesh.DESCRIPTOR_SUFFIX)
		if needle == "" or short.contains(needle):
			var i := _list.add_item(short)
			_list.set_item_metadata(i, path)


func _show(path: String) -> void:
	if _mesh:
		_mesh.queue_free()
	_mesh = TMesh.CreateFromFile(path)
	if _mesh == null:
		return
	_pivot.add_child(_mesh)
	_apply_reduction()
	# Fit the view: scale the file units so the mesh is about 2 units big, centred on the pivot.
	_mesh.ShowFrame(0.0)
	var box := _mesh.GetPosedBoundingBox()
	var size := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var fit := 2.0 / size if size > 0.0 else 1.0
	_mesh.SetScale(fit)
	_mesh.SetPosition(TMesh.ToGodot(-box.get_center() * fit))
	_distance = 4.0
	_playing = false
	_play_button.text = "Play"
	_frame = 0.0
	_slider.max_value = maxi(_mesh.FrameCount(), 0)
	_slider.set_value_no_signal(0)
	_show_frame()
	_info.text = "%s\nfile units: %s\ncull %s, alpha %s, alpha test %s, semi-transparent %s\nspecular %s / %s / tint %s, shading reduction %s\ndiffuse %s\nmaterial %s\nglow %s\nfur %s" % [
		_mesh.Descriptor.get("Source", ""), box.size, _mesh.Cullmode, _mesh.Alpha, _mesh.AlphaTestTreshold,
		_mesh.TextureSemiTransparency, _mesh.SpecularIntensity, _mesh.SpecularPower, _mesh.SpecularTint,
		_mesh.ShadingReduction, _mesh.DiffuseTexture, _mesh.MaterialTexture, _mesh.GlowTexture, _mesh.FurTexture]


func _apply_reduction() -> void:
	if _mesh:
		_mesh.ShadingReductionOverride = 0.5 if _reduction.button_pressed else 0.0
		_mesh.ApplyMaterial()


func _toggle_play() -> void:
	_playing = not _playing
	_play_button.text = "Pause" if _playing else "Play"


func _show_frame() -> void:
	if _mesh:
		_mesh.ShowFrame(_frame)
		_frame_label.text = "frame %d / %d" % [int(_frame), _mesh.FrameCount()]


func _process(delta: float) -> void:
	if _playing and _mesh and _mesh.FrameCount() > 0:
		_frame = fmod(_frame + delta * TMesh.FRAMES_PER_SECOND, _mesh.FrameCount())
		_slider.set_value_no_signal(_frame)
		_show_frame()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_distance = maxf(0.5, _distance * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_distance = minf(100.0, _distance * 1.1)
		_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.01
		_pitch = clampf(_pitch - mm.relative.y * 0.01, -1.5, 1.5)
		_update_camera()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_SPACE:
		_toggle_play()


func _update_camera() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.position = dir * _distance
	_camera.look_at(Vector3.ZERO)


## Video frames: each matching mesh turns half a circle over `frames` frames while its take plays at 30 fps;
## writes frame_00000.png, frame_00001.png, ... (encode with ffmpeg at 30 fps).
func _run_turntable(needles: PackedStringArray, out_dir: String, frames: int) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var n := 0
	for i in _list.item_count:
		var path: String = _list.get_item_metadata(i)
		var hit := false
		for needle in needles:
			hit = hit or path.contains(needle.to_lower())
		if not hit:
			continue
		_list.select(i)
		_list.ensure_current_is_visible()
		_show(path)
		for f in frames:
			_yaw = 0.6 + PI * f / frames
			_pitch = -0.35
			_update_camera()
			if _mesh.FrameCount() > 0:
				_frame = fmod(float(f), _mesh.FrameCount())
				_slider.set_value_no_signal(_frame)
				_show_frame()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("frame_%05d.png" % n))
			n += 1
	get_tree().quit()


func _run_capture(needles: PackedStringArray, out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	for path in _paths:
		var hit := false
		for needle in needles:
			hit = hit or path.contains(needle.to_lower())
		if not hit:
			continue
		_show(path)
		var name := path.trim_prefix(ALL_MESHES_ROOT + "/").trim_suffix(TMesh.DESCRIPTOR_SUFFIX).replace("/", "_")
		var views := [[0.6, -0.35], [0.6 + PI, -0.35]]
		for v in views.size():
			_yaw = views[v][0]
			_pitch = views[v][1]
			_update_camera()
			for i in 3:
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%d.png" % [name, v]))
		# Step through the whole take so animation problems show up in the log.
		for f in _mesh.FrameCount():
			_mesh.ShowFrame(f)
		await RenderingServer.frame_post_draw
	get_tree().quit()
