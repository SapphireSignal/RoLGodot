extends Node3D
## Map viewer (phase 4 check): a scenario's battlefield seen through the game's camera (TClientCameraComponent.
## ApplyCamera: eye = target + zoom * 10 * CAMERAOFFSET.Normalize, vertical field of view coEngineCameraFoV, near 1,
## far 10000). A scenario is set up as in a real game: the server game (TGameThread) runs the scenario scripts, a
## TClientGame joins it over an in-process connection (TClientGame.JoinLocal), loads the client map (terrain, water,
## vegetation, the map's decorations such as bridges), runs the scenario's client part (the PvE nexus ground) and
## receives the server's entities (nexus, towers, lane nodes...) and then its events. The game then runs live: server
## frames every 32 ms, a client frame per drawn frame (spawners spawn, units walk and fight). The game limits the zoom
## to coGameplayCameraMinZoom..MaxZoom (2.6..3.8, starts at 3.8); the viewer lets it go further out for an overview.
## Controls: WASD / arrows scroll, right mouse drag pans, wheel zooms, Q / E rotate, R resets.
## Capture mode (checks without a person):
##   -- --capture-out=<absolute folder> [--maps=Single,Classic] [--hide=Terrain,Water,Vegetation,Entities] [--wait=ms]
##      [--play=<card label,...>] [--death-burst=N] [--post-effects=off|none] [--dump-glow=on] [--ghost-check=on]
##      [--fps-check=on [--fps-phases=still,dragging] [--profile=on]]
## writes views of each scenario on those maps (game camera at a few places, an overview; after the game ran --wait
## ms), then quits. Launcher smoke
## test:  -- --smoke-test=<file>  after a few drawn frames writes "ok ..." or "FAIL ..." to <file> and quits.
const GameCursor = preload("res://src/viewer/game_cursor.gd")

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
## [button, scenario UID, map]: the sandbox of the 1 lane map (Single: 1v1-4v4 PvP, ranked 1v1 / 2v2, tutorial, solo
## PvE), the 2 lane sandbox (Classic: the two lane PvP modes, ranked 3v3 / 4v4, duo PvE) and the PvE sandbox (Single,
## with the nexus ground of the PvE scenarios). BaseConflict.Constants.Scenario.pas.
const SCENARIOS := [["1 lane (Single)", BC.SCENARIO_SANDBOX_UID, "Single"],
	["2 lanes (Classic)", BC.SCENARIO_SANDBOX_CLASSIC_UID, "Classic"],
	["PvE (Single)", BC.SCENARIO_PVE_DEFAULT_PREFIX + BC.SCENARIO_SANDBOX_UID, "Single"]]
const LEAGUE := 1
## The player token of TGameManager.CreateTestserverGameInfo (its secret key).
const TOKEN := "1"
## Card buttons: [label, commander (0 blue, 1 red: the token's first two), unit pattern of the sandbox deck card].
const CARDS := [["Blue footmen", 0, "Units\\White\\FootmanDrop"], ["Blue spawner", 0, "Units\\White\\FootmanSpawner"],
	["Red footmen", 1, "Units\\White\\FootmanDrop"], ["Red spawner", 1, "Units\\White\\FootmanSpawner"]]
## BaseConflict.Constants.Client.pas CAMERAOFFSET (game space).
const CAMERAOFFSET := Vector3(-0.394721269607544, 0.812130928039551, -0.429695725440979)
const FIELD_OF_VIEW := 0.6853981635  # coEngineCameraFoV, radians, vertical
const MIN_ZOOM := 2.6
const MAX_ZOOM := 3.8
## Named views for captures and the view buttons: [name, target x, target z, zoom]. Classic's lanes run at z = 23 and
## -23 around the middle; Single's one lane at z = -23 (the scenario scripts' nexus and towers).
const VIEWS := [["start", 0.0, 0.0, MAX_ZOOM], ["west base", -90.0, -23.0, MAX_ZOOM], ["east base", 90.0, -23.0, MAX_ZOOM],
	["center close", 0.0, -10.0, MIN_ZOOM], ["overview", 0.0, 0.0, 30.0]]
const VIEWS_SINGLE := [["start", 0.0, -23.0, MAX_ZOOM], ["west base", -90.0, -23.0, MAX_ZOOM], ["east base", 90.0, -23.0, MAX_ZOOM],
	["center close", 0.0, -23.0, MIN_ZOOM], ["overview", 0.0, 0.0, 30.0]]

var _map: TClientMap
var _client: TClientGame
var _thread: TGameThread
var _entities: Node3D
var _entity_count := 0
var _drop_count := 0  # footmen drops so far: each goes to the next lane
var _scenario_index := 0
var _camera: Camera3D
var _post_effects: TPostEffectManager
var _target := Vector2.ZERO
var _zoom := MAX_ZOOM
var _rotation := 0.0
var _dragging := false
var _drag_position := Vector2.ZERO  # FDragPosition: the grabbed ground point, game space XZ
var _last_drag_screen := Vector2.ZERO  # the last dragged-to mouse position (--drag-check)
var _last_server_ms := 0.0  # this frame's game server step (--fps-check)
var _last_client_ms := 0.0  # this frame's client game step (--fps-check)
var _info: Label
var _toggles := {}
var _load_ms := 0.0
var _loading := false
var _loading_overlay: ColorRect


func _ready() -> void:
	GameCursor.Apply(get_tree())
	_build_scene()
	_build_ui()
	_no_keyboard_focus(self)
	var maps := _user_arg("maps")
	var capture := _user_arg("capture-out")
	if capture != "":
		_run_capture.call_deferred(maps.split(",") if maps != "" else PackedStringArray(), capture)
		return
	_request_scenario(0)
	var smoke := _user_arg("smoke-test")
	if smoke != "":
		_finish_smoke_test.call_deferred(smoke)


func _exit_tree() -> void:
	_unload()


## Buttons, check boxes and sliders take no keyboard focus: a focused button is pressed again by Space / Enter (a
## scenario reload) and arrow keys would move the focus instead of scrolling. Mouse clicks work as before.
static func _no_keyboard_focus(node: Node) -> void:
	if node is BaseButton or node is Slider:
		(node as Control).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_no_keyboard_focus(child)


func _user_arg(arg_name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % arg_name):
			return arg.substr(arg_name.length() + 3)
	return ""


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	# GFXD.MainScene.Backgroundcolor := $23373C (BaseConflictMainUnit.pas:346), a gamma-space value like everything
	env.environment.background_color = Color8(0x23, 0x37, 0x3C)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(env)
	_camera = Camera3D.new()
	_camera.fov = rad_to_deg(FIELD_OF_VIEW)
	_camera.near = 1.0
	_camera.far = 10000.0
	# the game's post effect stack (glow, unsharp masking, color correction): the camera draws into its world viewport;
	# --post-effects=off draws the plain scene, =none the pipeline without effects (comparison captures);
	# --effects-off=Toon,FXAA switches those effects' options off
	for uid in _user_arg("effects-off").split(",", false):
		if TPostEffectManager.OPTIONS.has(uid):
			TOptionManager.SetOption(TPostEffectManager.OPTIONS[uid], "False")
	if _user_arg("post-effects") == "off":
		add_child(_camera)
	else:
		_post_effects = TPostEffectManager.new().Create(self, _camera)
		if _user_arg("post-effects") == "none":
			_post_effects.FEffects = []
			_post_effects.Rebuild()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# the HUD's technical panel (FPS, ping) at the top left like the game; the viewer's own panel below it
	var technical := TTechnicalPanel.new()
	technical.PingSource = func() -> int: return _client.Ping() if _client != null and not _loading else 0
	layer.add_child(technical)
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8 + technical.size.y)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var back := Button.new()
	back.text = "Back to main"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://src/main/main.tscn"))
	box.add_child(back)
	var scenario_row := HBoxContainer.new()
	box.add_child(scenario_row)
	for i in SCENARIOS.size():
		var button := Button.new()
		button.text = SCENARIOS[i][0]
		var index := i
		button.pressed.connect(func() -> void: _request_scenario(index))
		scenario_row.add_child(button)
	for layer_name: String in ["Terrain", "Water", "Vegetation", "Entities"]:
		var toggle := CheckBox.new()
		toggle.text = layer_name
		toggle.button_pressed = true
		toggle.toggled.connect(func(_on: bool) -> void: _apply_toggles())
		box.add_child(toggle)
		_toggles[layer_name] = toggle
	var view_row := HBoxContainer.new()
	box.add_child(view_row)
	for i in VIEWS.size():
		var button := Button.new()
		button.text = VIEWS[i][0]
		var index := i
		button.pressed.connect(func() -> void: _set_view(_views()[index]))
		view_row.add_child(button)
	# cards played through the client's commanders (eiUseAbility goes to the server, as the card hand will send it)
	var card_row := HBoxContainer.new()
	box.add_child(card_row)
	for card: Array in CARDS:
		var button := Button.new()
		button.text = card[0]
		var team_index: int = card[1]
		var pattern: String = card[2]
		button.pressed.connect(func() -> void: _play_card(team_index, pattern))
		card_row.add_child(button)
	_info = Label.new()
	box.add_child(_info)
	# Loading a scenario blocks the main thread for seconds (server game + client game): a dimmed overlay says so and
	# swallows the clicks made meanwhile.
	_loading_overlay = ColorRect.new()
	_loading_overlay.color = Color(0, 0, 0, 0.6)
	_loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.visible = false
	var loading_label := Label.new()
	loading_label.name = "Text"
	loading_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_label.add_theme_font_size_override("font_size", 32)
	_loading_overlay.add_child(loading_label)
	layer.add_child(_loading_overlay)


## Loads a scenario behind the loading overlay: it is drawn first, and stays one frame after the load so clicks
## queued during the blocking load land on it. Clicks while loading are ignored.
func _request_scenario(index: int) -> void:
	if _loading:
		return
	_loading = true
	(_loading_overlay.get_node("Text") as Label).text = "Loading %s ..." % SCENARIOS[index][0]
	_loading_overlay.visible = true
	for i in 2:
		await RenderingServer.frame_post_draw
	_load_scenario(index)
	await get_tree().process_frame
	_loading_overlay.visible = false
	_loading = false


func _unload() -> void:
	if _thread != null:
		_thread.StopThread()
	if _client != null:
		_client.Free()  # frees its map and entities (their meshes)
		_client = null
		_map = null
	if _thread != null:
		_thread.Free()
		_thread = null
	if _entities != null:
		_entities.queue_free()
		_entities = null
	GFXD.SetMainScene(null)


## The scenario's server game, then the client game (map, decorations, the scenario's client part) and the server's
## entities as a joining client gets them.
func _load_scenario(index: int) -> void:
	_unload()
	_scenario_index = index
	var start := Time.get_ticks_msec()
	var uid: String = SCENARIOS[index][1]
	var server_info := TGameManager.CreateTestserverGameInfo()
	server_info.ScenarioUID = uid
	server_info.League = LEAGUE
	server_info.Scenario = HScenario.ResolveScenario(uid, LEAGUE)
	_thread = TGameThread.new().Create(server_info)
	_entities = Node3D.new()
	_entities.name = "Entities"
	add_child(_entities)
	GFXD.SetMainScene(_entities)
	var client_info := TGameInformation.new().Create()
	client_info.ScenarioUID = uid
	client_info.League = LEAGUE
	client_info.IsSandboxOverride = true
	client_info.Scenario = HScenario.ResolveScenario(uid, LEAGUE)
	_client = TClientGame.JoinLocal(_thread, client_info, TOKEN)
	_map = _client.ClientMap
	add_child(_map)
	# the server answers NET_CLIENT_ENTER_CORE with the world, the client's frame takes it and says it is ready
	_thread.DoComputeGame()
	_client_frame()
	# from now on the server runs on its own thread like the original's TGameThread: drawing never waits for it
	_thread.StartThread()
	_entity_count = _client.EntityManager.DeployedEntityCount
	_load_ms = Time.get_ticks_msec() - start
	_apply_toggles()
	_set_view(_views()[0])


func _apply_toggles() -> void:
	if _map:
		_map.SetDrawTerrain(_toggles.Terrain.button_pressed)
		_map.SetDrawWater(_toggles.Water.button_pressed)
		_map.SetDrawVegetation(_toggles.Vegetation.button_pressed)
	if _entities:
		_entities.visible = _toggles.Entities.button_pressed


## The named views of the loaded map.
func _views() -> Array:
	return VIEWS_SINGLE if _map != null and _map.MapName == "Single" else VIEWS


func _set_view(view: Array) -> void:
	_target = Vector2(view[1], view[2])
	_zoom = view[3]
	_rotation = 0.0
	_update_camera()


## ApplyCamera: CameraDirection = FZoom * CAMERAOFFSET.Normalize * 10, turned by the rotation; eye = target + it.
func _update_camera() -> void:
	var direction := _zoom * CAMERAOFFSET.normalized() * 10
	direction = RMatrix.RotationPitchYawRoll(Vector3(0, _rotation, 0)) * direction
	var target := Vector3(_target.x, 0, _target.y)
	_camera.position = TMesh.ToGodot(target + direction)
	_camera.look_at(TMesh.ToGodot(target), Vector3.UP)
	if _info and _map:
		_info.text = "%s: map %s, %d decorations, %d entities, loaded in %d ms\ntarget (%.1f, %.1f)  zoom %.2f (game: %.1f..%.1f)  rotation %.2f\nWASD/arrows scroll, right drag pan, wheel zoom, Q/E rotate, R reset" % [
			SCENARIOS[_scenario_index][0], _map.MapName, _map.DecorationEntities.size(), _entity_count, _load_ms,
			_target.x, _target.y, _zoom, MIN_ZOOM, MAX_ZOOM, _rotation]


## TClientCameraComponent.MouseWorldPosition: the ground plane (y = 0) under a screen point, game space XZ.
func _mouse_world_position(screen: Vector2) -> Vector2:
	var origin := TMesh.ToGodot(_camera.project_ray_origin(_camera_point(screen)))
	var direction := TMesh.ToGodot(_camera.project_ray_normal(_camera_point(screen)))
	if absf(direction.y) < 1e-6:
		return _target
	var hit := origin + direction * (-origin.y / direction.y)
	return Vector2(hit.x, hit.z)


## A mouse position (the root viewport's coordinates: the project stretches the UI to its base size) in the camera's
## viewport (the post effects' world viewport has the window's pixel size).
func _camera_point(screen: Vector2) -> Vector2:
	return screen * _camera.get_viewport().get_visible_rect().size / get_viewport().get_visible_rect().size


## TClientCameraComponent's panning (OnMouseMoveEvent while FMoving): the camera at its height plane on the line
## through the grabbed ground point FDragPosition along the click ray, so that point stays under the cursor; the new
## target is where the camera looks down on the ground.
func _drag_to(screen: Vector2) -> void:
	_last_drag_screen = screen
	var direction := TMesh.ToGodot(_camera.project_ray_normal(_camera_point(screen)))
	var offset := RMatrix.RotationPitchYawRoll(Vector3(0, _rotation, 0)) * (_zoom * CAMERAOFFSET.normalized() * 10)
	if absf(direction.y) < 1e-6:
		return
	var grabbed := Vector3(_drag_position.x, 0, _drag_position.y)
	var eye := grabbed + direction * ((offset.y - grabbed.y) / direction.y)
	var target := eye - offset
	_target = Vector2(target.x, target.z)
	_update_camera()


## The screen axes on the ground (game space): TClientCameraComponent scrolls along CAMERAOFFSET.XZ and its
## orthogonal; up moves away from the camera.
func _scroll(right: float, up: float) -> void:
	var forward := -Vector2(CAMERAOFFSET.x, CAMERAOFFSET.z).normalized().rotated(-_rotation)
	var side := Vector2(-forward.y, forward.x)
	_target += (forward * up - side * right) * _zoom * 0.5
	_update_camera()


## The client's frame (BaseConflictMainUnit): the frame time, eiIdle on the global bus (the network component takes
## what the server sent), the core game state (client ready once the world is in), then Game.Idle; the meshes
## animate while drawn.
func _client_frame() -> void:
	GFXD.NextFrame()
	TThreadContext.Current().GameTimeManager.TickTack()
	_client.GlobalEventbus.Trigger(C.eiIdle, [])
	_client.ReadyWhenLoaded()
	_client.Idle()


## Plays a sandbox deck card of a commander through the client (eiUseAbility on the client's copy of the commander
## is sent to the server, which decides): a drop on the lane in front of the commander's nexus, a spawner on the first
## free field of its team's build zones. The client does not check the play first (eiCanUseAbility has no client
## answer yet: the HUD's check comes with phase 5).
func _play_card(team_index: int, pattern: String) -> void:
	if _client == null or not _client.IsReady() or _client.FTokenMapping.size() <= team_index:
		return
	var commander: TEntity = _client.EntityManager.GetEntityByID(_client.FTokenMapping[team_index])
	if commander == null:
		return
	var group := -1
	for g in 64:
		if commander.Blackboard.GetValue(C.eiWelaUnitPattern, [g]) == pattern:
			group = g
			break
	if group < 0:
		return
	var candidates: Array = []
	if pattern.ends_with("Spawner"):
		for zone: TBuildZone in _client.Map.BuildZones.BuildZones.values():
			if zone.TeamID != commander.TeamID():
				continue
			for y in zone.Size.y:
				for x in zone.Size.x:
					if zone.IsFree(Vector2i(x, y)):
						candidates.append(RCommanderAbilityTarget.CreateBuildTarget(zone.ID, Vector2i(x, y)))
	else:
		# a drop 30 in front of the own nexus on a lane (every press the next lane), inside the map's drop zone: the
		# game's client only sends targets there (the sandbox server checks no targets, TBrainWelaCommanderComponent
		# .CanUseAbility)
		var nexus = _client.EntityManager.NexusByTeamID(commander.TeamID())
		if nexus == null:
			return
		var position: Vector2 = nexus.Position
		var lanes: Array = _client.Map.Lanes.Lanes
		var lane: TLane = lanes[_drop_count % lanes.size()]
		_drop_count += 1
		var point := Vector2(position.x - signf(position.x) * 30.0, lane.FWayPoints[0].ProjectionCenter.y)
		var drop_zone: TMultipolygon = _client.Map.Zones.get(C.ZONE_DROP)
		if drop_zone != null and not drop_zone.IsPointInMultiPolygon(point):
			point = drop_zone.NextPointOnBorder(point)
		candidates.append(RCommanderAbilityTarget.Create(point))
	if not candidates.is_empty():
		var targets := RCommanderAbilityTarget.ArrayToRParam([candidates[0]])
		commander.Eventbus.Trigger(C.eiUseAbility, [targets], [group])


func _process(delta: float) -> void:
	if _client != null and not _loading:
		# the game server runs on its own thread (TGameThread.StartThread); here only the client's frame
		var t1 := Time.get_ticks_usec()
		_client_frame()
		_last_server_ms = _thread.LastFrameMs
		_last_client_ms = (Time.get_ticks_usec() - t1) / 1000.0
		if _client.EntityManager.DeployedEntityCount != _entity_count:
			_entity_count = _client.EntityManager.DeployedEntityCount
			_update_camera()
	var right := Input.get_axis("ui_left", "ui_right")
	var up := Input.get_axis("ui_down", "ui_up")
	if Input.is_key_pressed(KEY_A):
		right -= 1
	if Input.is_key_pressed(KEY_D):
		right += 1
	if Input.is_key_pressed(KEY_W):
		up += 1
	if Input.is_key_pressed(KEY_S):
		up -= 1
	if right != 0 or up != 0:
		_scroll(right * delta * 60, up * delta * 60)
	if Input.is_key_pressed(KEY_Q):
		_rotation -= delta
		_update_camera()
	if Input.is_key_pressed(KEY_E):
		_rotation += delta
		_update_camera()


## A drag ends wherever the button is released, also over the panel (which eats the event before
## _unhandled_input), and when the window loses focus: otherwise the view kept panning with every mouse move. Only the
## start checks the GUI (OnKeybindingEvent: not GUI.IsMouseOverGUI); a running drag follows the mouse over the panel.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT \
			and not event.pressed:
		_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_drag_to((event as InputEventMouseMotion).position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_dragging = true
				_drag_position = _mouse_world_position(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = maxf(1.0, _zoom - 0.2)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = minf(40.0, _zoom + 0.2)
			_update_camera()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_R:
		_set_view(_views()[0])


## The costliest event handlers of a TEventbus.GetProf() table, per frame: self time (without the handlers they call).
func _print_profile(side: String, table: Dictionary, frames: int) -> void:
	var rows := []
	var total := 0
	for key in table:
		rows.append([key] + table[key])
		total += table[key][1]
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
	print("profile %s: handlers %.3f ms/frame (self times, %d frames)" % [side, total / 1000.0 / frames, frames])
	for row in rows.slice(0, 15):
		print("profile %s:   %-60s %8.3f ms/frame self %8.3f incl, %6.1f calls/frame" % [side, row[0],
			row[2] / 1000.0 / frames, row[3] / 1000.0 / frames, float(row[1]) / frames])


## Meshes drawn in the entities layer (decorations and the server's entities).
func _drawn_meshes() -> int:
	var count := 0
	if _entities:
		for child in _entities.get_children():
			if child is TMesh:
				count += 1
	return count


func _finish_smoke_test(result_path: String) -> void:
	while _loading:
		await get_tree().process_frame
	for i in 5:
		await RenderingServer.frame_post_draw
	var terrain_ok := _map != null and _map.Terrain != null and _map.Terrain.get_child_count() > 0
	var water_ok := _map != null and _map.Water.SurfaceCount() > 0
	var vegetation_ok := _map != null and _map.Vegetation.get_child_count() > 0
	var entities_ok := _map != null and _map.DecorationEntities.size() > 0 and _entity_count > 0 and _drawn_meshes() > 0
	var grid_tiles := _client.BuildgridManager.TileCount() if _client != null and _client.BuildgridManager != null else 0
	# what is on screen, in the overview: the sea must show (blue-dominant pixels), nothing blown out to white (the
	# water over the map's edge once was)
	for view: Array in _views():
		if view[0] == "overview":
			_set_view(view)
	for i in 4:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var image_ok := image != null
	var water_pixels := 0.0
	var white_pixels := 0.0
	if image_ok:
		var samples := 0
		for y in range(0, image.get_height(), 8):
			for x in range(0, image.get_width(), 8):
				var c := image.get_pixel(x, y)
				samples += 1
				if c.b > c.r + 0.15 and c.g > c.r:
					water_pixels += 1
				if c.r > 0.97 and c.g > 0.97 and c.b > 0.97:
					white_pixels += 1
		water_pixels /= samples
		white_pixels /= samples
	water_ok = water_ok and water_pixels > 0.1
	var screen_ok := white_pixels < 0.005
	var ok := terrain_ok and water_ok and vegetation_ok and entities_ok and image_ok and grid_tiles > 0 and screen_ok
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	file.store_string("%s map viewer: %s terrain %s, water %s (%.0f%% of the overview), white %.1f%%, vegetation %s, %d decorations, %d entities, %d meshes, %d build grid tiles\n" % [
		"ok" if ok else "FAIL", _map.MapName if _map else "no map", terrain_ok, water_ok, water_pixels * 100,
		white_pixels * 100, vegetation_ok, _map.DecorationEntities.size() if _map else 0, _entity_count, _drawn_meshes(),
		grid_tiles])
	file.close()
	get_tree().quit()


## --ghost-check: drags the view for 12 frames (30 px per frame), grabs the frame, then grabs two still frames from the
## same camera. Prints the share of pixels that differ between the dragged and the still frame, next to the still pair
## (the animation's noise: water, wind, units).
func _ghost_check(view: Array, out_dir: String, map_name: String) -> void:
	_set_view(view)
	for f in 10:
		await RenderingServer.frame_post_draw
	var size := Vector2(get_viewport().get_visible_rect().size)
	var cursor := size * Vector2(0.3, 0.5)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = cursor
	Input.parse_input_event(press)
	await get_tree().process_frame
	for f in 12:
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(30, 0)
		cursor += motion.relative
		motion.position = cursor
		Input.parse_input_event(motion)
		await RenderingServer.frame_post_draw
	var dragged := get_viewport().get_texture().get_image()
	var release := press.duplicate()
	release.pressed = false
	release.position = cursor
	Input.parse_input_event(release)
	for f in 6:
		await RenderingServer.frame_post_draw
	var still := get_viewport().get_texture().get_image()
	for f in 6:
		await RenderingServer.frame_post_draw
	var still2 := get_viewport().get_texture().get_image()
	dragged.save_png(out_dir.path_join("ghost_%s_dragged.png" % map_name))
	still.save_png(out_dir.path_join("ghost_%s_still.png" % map_name))
	print("ghost-check: %s dragged vs still %.2f%% of pixels differ, still vs still %.2f%%" % [map_name,
		_differing_share(dragged, still), _differing_share(still, still2)])


## Share of pixels (every second one in x and y) whose color differs by more than 16 / 255 in a channel, in percent.
static func _differing_share(a: Image, b: Image) -> float:
	var counted := 0
	var differ := 0
	for y in range(0, mini(a.get_height(), b.get_height()), 2):
		for x in range(0, mini(a.get_width(), b.get_width()), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			counted += 1
			if absf(ca.r - cb.r) > 16.0 / 255.0 or absf(ca.g - cb.g) > 16.0 / 255.0 or absf(ca.b - cb.b) > 16.0 / 255.0:
				differ += 1
	return 100.0 * differ / maxi(counted, 1)


func _run_capture(maps: PackedStringArray, out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	# --hide=Water,Vegetation: capture with those layers off (to isolate a render problem)
	for layer_name in _user_arg("hide").split(",", false):
		if _toggles.has(layer_name):
			(_toggles[layer_name] as CheckBox).set_pressed_no_signal(false)
	var extra_views: Array = []
	var extra := _user_arg("view")  # --view=x,z,zoom[,rotation] adds a custom view
	if extra != "":
		var p := extra.split(",")
		extra_views = [["custom", float(p[0]), float(p[1]), float(p[2]), float(p[3]) if p.size() > 3 else 0.0]]
	for i in SCENARIOS.size():
		if not maps.is_empty() and not maps.has(SCENARIOS[i][2]):
			continue
		_load_scenario(i)
		var views: Array = _views() + extra_views  # the loaded map's views
		# --play=<card label,...>: once the game has started (after the warm-up), play those cards
		var play := _user_arg("play")
		if play != "":
			while not _thread.InternalGame.HasStarted():
				await get_tree().process_frame
			for label in play.split(","):
				for card: Array in CARDS:
					if card[0] == label:
						_play_card(card[1], card[2])
		# --drag-check=on: a right drag through the input system; the grabbed ground point must stay under the cursor
		if _user_arg("drag-check") == "on":
			_set_view(views[0])
			for f in 4:
				await RenderingServer.frame_post_draw
			var size := Vector2(get_viewport().get_visible_rect().size)
			var start := size * Vector2(0.5, 0.5)
			var grabbed := _mouse_world_position(start)
			print("drag-check: window %s, root rect %s, camera viewport %s, target %s" % [get_window().size, size,
				_camera.get_viewport().get_visible_rect().size, _target])
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_RIGHT
			press.pressed = true
			press.position = start
			Input.parse_input_event(press)
			await get_tree().process_frame
			var worst := 0.0
			for point: Vector2 in [size * Vector2(0.3, 0.3), size * Vector2(0.8, 0.2), size * Vector2(0.15, 0.85)]:
				var motion := InputEventMouseMotion.new()
				motion.position = point
				motion.relative = point - start
				Input.parse_input_event(motion)
				await get_tree().process_frame
				# the event arrives scaled to the root viewport: measure where the handler saw the cursor
				grabbed = _drag_position
				worst = maxf(worst, _mouse_world_position(_last_drag_screen).distance_to(grabbed))
			print("drag-check: last cursor %s, target now %s" % [_last_drag_screen, _target])
			var release := press.duplicate()
			release.pressed = false
			Input.parse_input_event(release)
			await get_tree().process_frame
			print("drag-check: %s grabbed (%.2f, %.2f), worst drift %.4f, dragging after release %s" % [
				SCENARIOS[i][2], grabbed.x, grabbed.y, worst, _dragging])
			# the ground the eye sees: terrain heights along the lane (the drag holds the y = 0 plane, as the original)
			if _map != null and _map.Terrain != null:
				var heights := []
				for x in range(-100, 101, 20):
					for z in [-23.0, 0.0]:
						heights.append("%.2f" % (_map.Terrain.GetTerrainHeight(Vector2(x, z)) as Vector3).y)
				print("drag-check: terrain heights along z = -23 / 0, x -100..100: ", ", ".join(heights))
		# --ghost-check=on: a fast right drag through the input system; the frame drawn while dragging must match a still
		# frame from the same camera (outlines and glow drawn from the camera of an earlier frame show up as ghosts)
		if _user_arg("ghost-check") == "on":
			await _ghost_check(views[1], out_dir, SCENARIOS[i][2])
		# --wait=<ms>: let the game run that long before the checks and captures (units spawn and walk)
		var wait_until := Time.get_ticks_msec() + int(_user_arg("wait"))
		while Time.get_ticks_msec() < wait_until:
			await get_tree().process_frame
		# --fps-check=on: frame times over 3 s while the view pans continuously (a drag), then 3 s standing still (after
		# --play / --wait, so a full field can be measured)
		if _user_arg("fps-check") == "on":
			_set_view(views[0])
			for f in 30:
				await get_tree().process_frame
			# --fps-phases=still,dragging measures in that order (default: dragging, then still)
			var phases := _user_arg("fps-phases").split(",", false) if _user_arg("fps-phases") != "" else PackedStringArray(["dragging", "still"])
			for phase in phases:
				var frames := 0
				var slow := 0
				var client_sum := 0.0
				var server_sum := 0.0
				var times := []
				_thread.WorstFrameMs = 0.0
				# --profile=on (still phase): every event handler of both sides and the meshes' frame work, timed
				var profiling: bool = phase == "still" and _user_arg("profile") == "on"
				if profiling:
					TEventbus.SetProf({})
					TMesh.ProfUs = [0, 0, 0]
					_thread.StopThread()
					_thread.FContext.Prof = {}
					_thread.StartThread()
				# the drag goes through the input system like the owner's mouse: right button down in the middle of the
				# screen, then a fast mouse move every frame (40 pixels, swinging across the screen), button up at the end
				var screen := Vector2(get_viewport().get_visible_rect().size)
				var mouse := screen * 0.5
				if phase == "dragging":
					var down := InputEventMouseButton.new()
					down.button_index = MOUSE_BUTTON_RIGHT
					down.pressed = true
					down.position = mouse
					Input.parse_input_event(down)
				var start_ms := Time.get_ticks_usec()
				var last := start_ms
				while Time.get_ticks_usec() - start_ms < 3000000:
					if phase == "dragging":
						var step := Vector2(40, 12) * (1 if (frames / 15) % 2 == 0 else -1)
						var motion := InputEventMouseMotion.new()
						motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
						mouse += step
						motion.position = mouse
						motion.relative = step
						Input.parse_input_event(motion)
					await get_tree().process_frame
					var now := Time.get_ticks_usec()
					var ms := (now - last) / 1000.0
					last = now
					frames += 1
					times.append(ms)
					client_sum += _last_client_ms
					server_sum += _last_server_ms
					if ms > 12.0:
						slow += 1
				if phase == "dragging":
					var up := InputEventMouseButton.new()
					up.button_index = MOUSE_BUTTON_RIGHT
					up.pressed = false
					up.position = mouse
					Input.parse_input_event(up)
					print("fps-check: the drag moved the view to %s (dragging %s)" % [_target, _dragging])
				times.sort()
				var seconds := (Time.get_ticks_usec() - start_ms) / 1000000.0
				if profiling:
					_thread.StopThread()
					_print_profile("client", TEventbus.GetProf(), frames)
					_print_profile("server", _thread.FContext.Prof, maxi(1, int(seconds * 1000 / TGameThread.TARGET_FRAMETIME)))
					_thread.FContext.Prof = null
					_thread.StartThread()
					TEventbus.SetProf(null)
					print("profile client: meshes Animate %.3f ms/frame, SetUpCustomShaders %.3f ms/frame (%d mesh frames/frame)" % [
						TMesh.ProfUs[0] / 1000.0 / frames, TMesh.ProfUs[1] / 1000.0 / frames, TMesh.ProfUs[2] / frames])
					TMesh.ProfUs = null
				print("fps-check: the technical panel shows %d FPS" % GFXD.FPS())
				print("fps-check: %s %s, %d entities: %.1f fps, median %.1f ms, p99 %.1f ms, worst %.1f ms, %d frames > 12 ms; client step %.2f ms/frame; server thread %.2f ms/frame (worst %.1f, budget %d)" % [
					SCENARIOS[i][2], phase, _client.EntityManager.DeployedEntityCount, frames / seconds,
					times[times.size() / 2], times[int(times.size() * 0.99)], times[-1], slow, client_sum / frames,
					server_sum / frames, _thread.WorstFrameMs, TGameThread.TARGET_FRAMETIME])
		# --death-burst=N: after the wait, at the first unit death on the client, N frames ~60 ms apart centered on the
		# dying mesh (the decay manager's death shader, 500 ms)
		var burst := int(_user_arg("death-burst"))
		if burst > 0:
			var give_up := Time.get_ticks_msec() + 60000
			while _client.DecayManager.DecayingCount() == 0 and Time.get_ticks_msec() < give_up:
				await get_tree().process_frame
			if _client.DecayManager.DecayingCount() > 0:
				var dying: TMesh = _client.DecayManager.FDecayingUnits[0].DecayingMesh
				_set_view(["death", dying.Position.x, dying.Position.z, 1.2])
				for f in burst:
					var next := Time.get_ticks_msec() + 60
					await RenderingServer.frame_post_draw
					var file := "%d_%s_death_%02d.png" % [i, String(SCENARIOS[i][2]).to_lower(), f]
					get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
					while Time.get_ticks_msec() < next:
						await get_tree().process_frame
		for view: Array in views:
			_set_view(view)
			if view.size() > 4:
				_rotation = view[4]
				_update_camera()
			for f in 4:
				await RenderingServer.frame_post_draw
			var file := "%d_%s_%s.png" % [i, String(SCENARIOS[i][2]).to_lower(), String(view[0]).replace(" ", "_")]
			get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
			# --dump-glow=on: the glow stage's buffer too
			if _user_arg("dump-glow") == "on" and _post_effects != null and _post_effects.GlowViewport != null:
				_post_effects.GlowViewport.get_texture().get_image().save_png(out_dir.path_join("glow_" + file))
			# --dump-toon=on: the Toon border buffer
			if _user_arg("dump-toon") == "on" and _post_effects != null and _post_effects.ToonBorder != null:
				_post_effects.ToonBorder.get_image().save_png(out_dir.path_join("toon_" + file))
	get_tree().quit()
