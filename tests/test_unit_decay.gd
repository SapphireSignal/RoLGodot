extends "res://tests/test_case.gd"
## The procedural death of units on the client: TMeshComponent.OnDie hands a dying unit's mesh (udHasDeathEffect) to
## TClientGame.DecayManager (TUnitDecayManagerComponent), which draws it with the death shader of its color for 500 ms
## and then frees it.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
const FRAME = 32.0
const TOKEN = "1"  # CreateTestserverGameInfo's secret key

var _thread: TGameThread = null
var _client: TClientGame = null


func after_each() -> void:
	if _client != null:
		_client.Free()
	_client = null
	if _thread != null:
		_thread.Free()
	_thread = null
	TTimeManager.SetFakeTime(null)
	super()


func _frame() -> void:
	TTimeManager.SetFakeTime(TTimeManager.GetFakeTime() + FRAME)
	_thread.DoComputeGame()
	TThreadContext.Current().GameTimeManager.TickTack()
	_client.GlobalEventbus.Trigger(C.eiIdle, [])
	_client.ReadyWhenLoaded()
	_client.Idle()


func _run_for(ms: float) -> void:
	var until: float = TTimeManager.GetFakeTime() + ms
	while TTimeManager.GetFakeTime() + FRAME <= until:
		_frame()


func _joined_sandbox() -> void:
	TTimeManager.SetFakeTime(1000.0)
	_thread = TGameThread.new().Create(TGameManager.CreateTestserverGameInfo())
	var info := TGameInformation.new().Create()
	info.ScenarioUID = BC.TESTSERVER_SCENARIO_UID
	info.League = BC.TESTSERVER_SENARIO_LEAGUE
	info.Scenario = HScenario.ResolveScenario(info.ScenarioUID, info.League)
	_client = TClientGame.JoinLocal(_thread, info, TOKEN)


func _mesh_component(entity: TEntity) -> TMeshComponent:
	var result: Array = []
	entity.Eventbus.Trigger(C.eiEnumerateComponents, [func(component) -> bool:
		if component is TMeshComponent and not component.FIsEffectMesh:
			result.append(component)
		return true])
	return result[0] if not result.is_empty() else null


func _gone(mesh) -> bool:
	return not is_instance_valid(mesh) or mesh.is_queued_for_deletion()


## A killed footman on the client: its mesh goes to the decay manager with the white death shader (explosion in the
## white glow color), plays its death animation, the mesh component goes; after 500 ms the mesh is freed.
func test_dying_unit_decays_on_the_client() -> String:
	_joined_sandbox()
	_run_for(BC.GAME_WARMING_DURATION + 3 * FRAME)
	check_eq(_client.DecayManager.DecayingCount(), 0, "nothing decays yet")
	var commander: TEntity = null
	for entity: TEntity in _client.EntityManager.GetDeployedEntityList():
		if entity.ID in _client.FTokenMapping:
			commander = entity
			break
	var group := -1
	for g in range(0, 64):
		if commander.Blackboard.GetValue(C.eiWelaUnitPattern, [g]) == "Units\\White\\FootmanDrop":
			group = g
	var targets := RCommanderAbilityTarget.ArrayToRParam([RCommanderAbilityTarget.Create(Vector2(-20, -23))])
	commander.Eventbus.Trigger(C.eiUseAbility, [targets], [group])
	_run_for(2000.0)
	var server_units: Array = _thread.InternalGame.EntityManager.FilterEntities([C.upUnit], [])
	check(server_units.size() > 0, "a squad on the server")
	if server_units.is_empty():
		return take_failure()
	var victim: TEntity = server_units[0]
	var copy: TEntity = _client.EntityManager.GetEntityByID(victim.ID)
	check(copy != null, "the client has it")
	var component := _mesh_component(copy) if copy != null else null
	check(component != null and component.FMesh != null, "with its mesh")
	if component == null or component.FMesh == null:
		return take_failure()
	check(RParam.AsBoolean(copy.UnitData(C.udHasDeathEffect)), "UnitTemplate gives it the death effect")
	var mesh: TMesh = component.FMesh
	var victim_id := victim.ID
	victim.Eventbus.Trigger(C.eiKill, [-1, -1])
	_frame()
	check_eq(_client.DecayManager.DecayingCount(), 1, "the mesh decays")
	check(is_instance_valid(mesh), "the mesh lives on")
	if not is_instance_valid(mesh):
		return take_failure()
	check_eq(mesh.CustomShader.size(), 1, "only the death shader")
	check_eq(mesh.CustomShader[0].ShaderName, "Graphics\\Effects\\Shader\\DeathShader.fx", "not black: DeathShader.fx")
	# no script makes a death animation: the pose freezes
	check(not mesh.AnimationController.HasAnimation(C.ANIMATION_DEATH), "the footman has no death animation")
	check_eq(mesh.AnimationController.Status, TAnimationController.asPaused, "its pose freezes")
	check_eq(mesh.MeshMaterial.get_shader_parameter("explosion_color"),
		TUnitDecayManagerComponent._rgb(0xFFFEFF98), "the white glow color")
	var progress: float = mesh.MeshMaterial.get_shader_parameter("explosion_progress")
	check(progress >= 0.0 and progress < 0.2, "progress starts: %s" % progress)
	var still: TEntity = _client.EntityManager.GetEntityByID(victim_id)
	check(still == null or _mesh_component(still) == null, "the mesh component went")
	_run_for(250.0)
	mesh.SetUpCustomShaders()
	progress = mesh.MeshMaterial.get_shader_parameter("explosion_progress")
	check(progress > 0.4 and progress < 0.7, "half way: %s" % progress)
	_run_for(300.0)
	check_eq(_client.DecayManager.DecayingCount(), 0, "decayed")
	check(_gone(mesh), "the mesh is freed")
	check_eq(TEntity.LastScriptError, "", "no script error")
	return take_failure()


## Black units darken with DeathShader_Black.fx instead.
func test_black_units_use_the_black_death_shader() -> String:
	TTimeManager.SetFakeTime(1000.0)
	var manager := TUnitDecayManagerComponent.new()
	var mesh := TMesh.CreateFromFile("Units\\Black\\VoidSkeleton_Default\\VoidSkeleton.xml")
	check(mesh != null, "a mesh")
	if mesh == null:
		return take_failure()
	manager.AddMesh(mesh, C.ecBlack)
	check_eq(mesh.CustomShader[0].ShaderName, "Graphics\\Effects\\Shader\\DeathShader_Black.fx", "black")
	mesh.SetUpCustomShaders()
	check_eq(mesh.MeshMaterial.get_shader_parameter("dsb_progress"), 0.0, "progress 0")
	TTimeManager.SetFakeTime(1250.0)
	mesh.SetUpCustomShaders()
	check_eq(mesh.MeshMaterial.get_shader_parameter("dsb_progress"), 0.5, "half way")
	TTimeManager.SetFakeTime(1600.0)
	manager.OnIdle()
	check_eq(manager.DecayingCount(), 0, "decayed")
	check(_gone(mesh), "freed")
	return take_failure()
