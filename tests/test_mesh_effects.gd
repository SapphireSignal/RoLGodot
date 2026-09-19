extends "res://tests/test_case.gd"
## Mesh effects (docs/assets.md "Mesh effects"): TShader's block composition (Engine.GfxApi.pas), TMeshEffect and its
## used subclasses, TMeshEffectComponent, the effect stack of TMeshComponent and the custom shaders of TMesh
## (BaseConflict.EntityComponents.Client.Visuals.pas, Engine.Mesh.pas). Tests with meshes need assets/graphics.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

var _free: Array = []
var _thread: TGameThread = null
var _client: TClientGame = null


func after_each() -> void:
	for obj in _free:
		obj.Free()
	_free.clear()
	if _client != null:
		_client.Free()
	_client = null
	if _thread != null:
		_thread.Free()
	_thread = null
	TTimeManager.FakeTime = null
	TOptionManager.ResetOptions()
	TMesh.ClearGeometryCache()
	super()


func _has_assets() -> bool:
	if TMesh.Exists("Units\\Neutral\\Nexus\\Nexus.xml") and ResourceLoader.exists("res://assets/graphics/effects/textures/matcapcrystal1.png"):
		return true
	print("  (assets/graphics missing: run python tools/import_graphics.py)")
	return false


func _mesh_components(entity: TEntity) -> Array:
	var result: Array = []
	entity.Eventbus.Trigger(C.eiEnumerateComponents, [func(component) -> bool:
		if component is TMeshComponent:
			result.append(component)
		return true])
	return result


func _shader_names(mesh: TMesh) -> Array:
	var names := []
	for s: TMesh.RMeshShader in mesh.CustomShader:
		names.append(String(s.ShaderName).replace("\\", "/").get_file())
	return names


func _texture_file(material: ShaderMaterial, uniform: String) -> String:
	var texture = material.get_shader_parameter(uniform)
	return (texture as Texture2D).resource_path.get_file() if texture is Texture2D else ""


## LoadShader walks the block files last to first: the first file's block is outermost, #inherited nests the next
## one, the base's section content sits innermost; a block without #inherited drops what it replaces.
func test_shader_block_composition() -> String:
	var base := "head\n#block b\nBASE\n#endblock\n#block c\nC_BASE\n#endblock\ntail\n"
	var first := "#block b\nFIRST\n#inherited\n#endblock\n"
	var second := "#block b\nSECOND\n#inherited\nSECOND_AFTER\n#endblock\n#block c\nC_NEW\n#endblock\n"
	var result := TShader.Compose(base, [first, second])
	var lines := Array(result.split("\n", false))
	check_eq(lines, ["head", "FIRST", "SECOND", "BASE", "SECOND_AFTER", "C_NEW", "tail"], "nesting order")
	check_eq(Array(TShader.Compose(base, []).split("\n", false)), ["head", "BASE", "C_BASE", "tail"], "no blocks: the base's content")
	check(not TShader.Compose(TShader.LoadBaseFile(TMesh.SHADER_INCLUDE), [TShader.LoadBlockFile("MatcapShader.fx")]).contains("#block"),
		"no block markers left in a composed mesh shader")
	return take_failure()


## HMath.Interpolate over the timer's interval: keys (0, 0.3), (500, 0.0) over 500 ms. At 0 ms no key lies before the
## time (the original reads uninitialized values there): the port takes the first key.
func test_timekeys_follow_the_timer() -> String:
	TTimeManager.FakeTime = 1000.0
	var tint := TMeshEffectTint.new().Create(500, 0xFF102030)
	tint.AddKey(0, 0.3).AddKey(500, 0.0)
	check_near(tint.CurrentValue(), 0.3, 1e-6, "start")
	TTimeManager.FakeTime = 1250.0
	check_near(tint.CurrentValue(), 0.15, 1e-6, "half way")
	check(not tint.Expired(), "running")
	TTimeManager.FakeTime = 1501.0
	check(tint.Expired(), "expired after the duration")
	check_near(TMeshEffectWithTimekeys.Interpolate([[0, 1.0], [2147483647, 1.0]], 0.5, 1000), 1.0, 1e-6, "perma key")
	check_eq(tint.FColor, Color(0x10 / 255.0, 0x20 / 255.0, 0x30 / 255.0, 1.0), "ARGB color")
	return take_failure()


## The sandbox (map Single): the nexus crystals and the lane towers' crystal shards reflect MatcapCrystal<team>.png
## (Units\Neutral\Nexus.ets, LanetowerLevel1.ets); the towers spawn with the white spawn effect (grey fading color,
## ecWhite override) for 2500 ms, drawn without culling meanwhile, then it expires and the cull mode returns.
func test_sandbox_crystals_and_tower_spawn() -> String:
	if not _has_assets():
		return ""
	TTimeManager.FakeTime = 1000.0
	_thread = TGameThread.new().Create(TGameManager.CreateTestserverGameInfo())
	var info := TGameInformation.new().Create()
	info.ScenarioUID = BC.TESTSERVER_SCENARIO_UID
	info.League = BC.TESTSERVER_SENARIO_LEAGUE
	info.Scenario = HScenario.ResolveScenario(info.ScenarioUID, info.League)
	_client = TClientGame.JoinLocal(_thread, info, "1")
	_thread.DoComputeGame()  # the server answers NET_CLIENT_ENTER_CORE with the world
	_client.GlobalEventbus.Trigger(C.eiIdle, [])  # the client takes it
	var nexi: Array = []
	var towers: Array = []
	for copy: TEntity in _client.EntityManager.GetDeployedEntityList():
		if copy.ScriptFile.contains("Nexus"):
			nexi.append(copy)
		elif copy.ScriptFile.contains("Lanetower"):
			towers.append(copy)
	check_eq(TEntity.LastScriptError, "", "no script error")
	check(nexi.size() == 2 and towers.size() >= 2, "nexus and towers")
	_client.GlobalEventbus.Trigger(C.eiIdle, [])
	for nexus: TEntity in nexi:
		for mesh_component in _mesh_components(nexus):
			if not mesh_component.FModelFileName.ends_with("NexusCrystal.xml"):
				continue
			var mesh: TMesh = mesh_component.FMesh
			check(_shader_names(mesh).has("MatcapShader.fx"), "matcap on the nexus crystal")
			mesh.SetUpCustomShaders()
			check_eq(_texture_file(mesh.MeshMaterial, "variable_texture_2"), "matcapcrystal%d.png" % nexus.TeamID(),
				"team matcap of nexus %d" % nexus.TeamID())
	var tower: TEntity = towers[0]
	var shards = null
	for mesh_component in _mesh_components(tower):
		if mesh_component.FModelFileName.to_lower().ends_with("lanetowercrystalshards.xml"):
			shards = mesh_component
	check(shards != null, "tower crystal shards")
	if shards == null:
		return take_failure()
	var mesh: TMesh = shards.FMesh
	check_eq(_shader_names(mesh), ["SpawnShader_White.fx", "MatcapShader.fx"], "spawn (order 1) before matcap (9993)")
	check_eq(mesh.Cullmode, "cmNone", "no culling while spawning")
	mesh.SetUpCustomShaders()
	check_eq(_texture_file(mesh.MeshMaterial, "variable_texture_3"), "spawnmask.png", "white spawn mask")
	var fading: Vector3 = mesh.MeshMaterial.get_shader_parameter("fading_color")
	check(fading.is_equal_approx(Vector3(0x50 / 255.0, 0x59 / 255.0, 0x58 / 255.0)), "OverrideColor($FF505958)")
	TTimeManager.FakeTime = 1000.0 + 2501.0
	_client.GlobalEventbus.Trigger(C.eiIdle, [])
	check_eq(_shader_names(mesh), ["MatcapShader.fx"], "the spawn effect expired")
	check_eq(mesh.Cullmode, "cmCCW", "cull mode back")
	return take_failure()


## Drop.dws gives every drop TMeshEffectSpawn by its color: blue draws 20 own passes (pass_progress 0..1) that hide the
## mesh's own drawing, for 1500 ms. A second spawn effect (white) waits on the stack: not mounted, as one is there.
func test_blue_spawn_draws_own_passes() -> String:
	if not _has_assets():
		return ""
	TTimeManager.FakeTime = 0.0
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = C.nsClient
	_free.append(bus)
	var entity := TEntity.new().Create(bus)
	_free.push_front(entity)
	entity.Eventbus.Write(C.eiColorIdentity, [C.ecBlue])
	var component := TMeshComponent.new().CreateGrouped(entity, [0], "Units\\Neutral\\Nexus\\NexusCrystal.xml") as TMeshComponent
	var mesh := component.FMesh
	var first := TMeshEffectSpawn.new().Create()
	first.AssignToEntity(entity)
	var second := TMeshEffectSpawn.new().Create()
	second.OverrideColorIdentity(C.ecWhite)
	second.AssignToEntity(entity)
	check_eq(_shader_names(mesh), ["SpawnShader_Blue.fx"], "own passes mount at once; they are not in the main list")
	check_eq(mesh.OwnPassMaterials.size(), 20, "BLUE_PASSES")
	var chain := 0
	var m: Material = mesh.MeshInstance.material_override
	while m != null:
		chain += 1
		m = m.next_pass
	check_eq(chain, 20, "the mesh's own drawing is hidden")
	check(mesh.MeshInstance.material_override != mesh.MeshMaterial, "not the main material")
	mesh.SetUpCustomShaders()
	check_near(mesh.OwnPassMaterials[19][2].get_shader_parameter("pass_progress"), 1.0, 1e-6, "last pass progress")
	check_eq(mesh.ResolveShaderArray(), [], "no main custom shaders")
	TTimeManager.FakeTime = 1501.0
	component.Idle()
	check_eq(mesh.OwnPassMaterials.size(), 0, "blue expired")
	check(mesh.MeshInstance.material_override == mesh.MeshMaterial, "own drawing back")
	# as written, only an effect without own passes hands over to a waiting one of its class
	check_eq(_shader_names(mesh), [], "the waiting white spawn stays unmounted")
	check_eq(component.FEffectStack.size(), 1, "until it expires")
	TTimeManager.FakeTime = 2501.0
	component.Idle()
	check_eq(component.FEffectStack.size(), 0, "then it is gone")
	return take_failure()


## TMeshEffectComponent gives managed clones to the meshes of its group and takes them back when freed. Metal on a
## white unit reflects Metal_White.png; the stack mounts one effect per class.
func test_effect_component_and_metal() -> String:
	if not _has_assets():
		return ""
	TTimeManager.FakeTime = 0.0
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = C.nsClient
	_free.append(bus)
	var entity := TEntity.new().Create(bus)
	_free.push_front(entity)
	entity.Eventbus.Write(C.eiColorIdentity, [C.ecWhite])
	var in_group := TMeshComponent.new().CreateGrouped(entity, [1], "Units\\Neutral\\Nexus\\NexusCrystal.xml") as TMeshComponent
	var other := TMeshComponent.new().CreateGrouped(entity, [2], "Units\\Neutral\\Nexus\\NexusCrystal.xml") as TMeshComponent
	var effects := TMeshEffectComponent.new().CreateGrouped(entity, [1]) as TMeshEffectComponent
	effects.SetEffect(TMeshEffectMetal.new().Create())
	check_eq(_shader_names(in_group.FMesh), ["MetalShader.fx"], "metal on the group's mesh")
	check_eq(_shader_names(other.FMesh), [], "not on another group's")
	check(in_group.FEffectStack[0].Managed, "managed")
	in_group.FMesh.SetUpCustomShaders()
	check_eq(_texture_file(in_group.FMesh.MeshMaterial, "variable_texture_2"), "metal_white.png", "white metal")
	TMeshEffectMetal.new().Create().AssignToEntity(entity)
	check_eq(_shader_names(in_group.FMesh), ["MetalShader.fx"], "a second metal waits on the stack")
	check_eq(in_group.FEffectStack.size(), 2, "both on the stack")
	effects.Free()
	check_eq(in_group.FEffectStack.size(), 1, "the component's effect is gone")
	check_eq(_shader_names(in_group.FMesh), ["MetalShader.fx"], "the waiting one is mounted")
	return take_failure()
