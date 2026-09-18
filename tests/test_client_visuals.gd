extends "res://tests/test_case.gd"
## Client visuals (phase 4 -> 5 bridge): TAnimationController / TAnimation (Engine.Animation.pas), the TMesh bone
## driver (Engine.Mesh.pas), TVisualizerComponent + RMatrixAdjustments, TMeshComponent, TAnimationComponent,
## TLogicToWorldComponent (BaseConflict.EntityComponents.Client*.pas), TEntity.Serialize / Deserialize and the
## blackboard stream (BaseConflict.Entity.pas), TClientMap decorations (BaseConflict.Map.Client.pas) and TClientGame.
## Tests with meshes need tools/import_graphics.py's output (assets/graphics).

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
const FRAME = 32.0

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
	if TMesh.Exists("Units\\Neutral\\Nexus\\Nexus.xml") and FileAccess.file_exists("res://assets/graphics/maps/classic/classic.decorations.json"):
		return true
	print("  (assets/graphics missing: run python tools/import_graphics.py)")
	return false


func _bus(side: int = C.nsClient) -> TEventbus:
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = side
	_free.append(bus)
	return bus


func _near3(a: Vector3, b: Vector3, eps := 1e-4) -> bool:
	return (a - b).length() <= eps


func _mesh_components(entity: TEntity) -> Array:
	var result: Array = []
	entity.Eventbus.Trigger(C.eiEnumerateComponents, [func(component) -> bool:
		if component is TMeshComponent:
			result.append(component)
		return true])
	return result


## TAnimation (Engine.Animation.pas): a single play of 2000 ms started at 1000 fades in until 1500 and out from
## 2500 (FEndTime - FADEOUT_LENGTH); it is finished 500 ms after the fade-out start. A loop never fades out.
func test_animation_weights_and_time_keys() -> String:
	var single := TAnimationController.TAnimation.new("a", 1000, 2000, TAnimationController.alSingle, true)
	check_eq(single.ComputeWeight(1250), 0.5, "fading in")
	check_eq(single.ComputeWeight(2000), 1.0, "full weight")
	check_eq(single.ComputeWeight(2750), 0.5, "fading out")
	check_eq(single.ComputeTimeKey(2000), [0.5, false], "half way")
	check_eq(single.ComputeTimeKey(3000)[1], false, "not finished at 500 ms after the fade-out start")
	check_eq(single.ComputeTimeKey(3001)[1], true, "finished after")
	var loop := TAnimationController.TAnimation.new("b", 0, 1000, TAnimationController.alLoop, true)
	check_eq(loop.ComputeTimeKey(2500), [0.5, false], "a loop wraps (Frac) and never finishes")
	check_eq(TAnimationController.TAnimation.new("c", 0, 0, TAnimationController.alSingle, true).FLength, 1, "length at least 1")
	return take_failure()


## RMatrixAdjustments.Apply: swaps, then inversions of the base columns, then offset and rotation on the right.
func test_matrix_adjustments() -> String:
	var a := TVisualizerComponent.RMatrixAdjustments.new()
	a.BindSwapXZ = true
	a.BindInvertY = true
	var m := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(5, 6, 7))
	var r := a.Apply(m)
	check_eq(r.basis.x, Vector3(0, 0, 1), "column 0 <- column 2")
	check_eq(r.basis.z, Vector3(1, 0, 0), "column 2 <- column 0")
	check_eq(r.basis.y, Vector3(0, -1, 0), "column 1 inverted")
	a.Offset = Vector3(0, 2, 0)
	check_eq(a.Apply(m).origin, Vector3(5, 4, 7), "offset in the adjusted base (y inverted)")
	return take_failure()


## Classic.bcc: 54 decorations (bridges, bridge parts, stones, ambient sound emitters). Environment meshes are
## static: placed once at the decoration's position and front, size = eiSize * eiModelSize (1.0) * the legacy size
## factor 2 / 125 for BridgePart1 (Scripts\Environment\BridgePart1.ets).
func test_classic_decorations_are_placed() -> String:
	if not _has_assets():
		return ""
	var bus := _bus()
	var map := TClientMap.CreateFromFile("Classic", bus)
	check_eq(map.Decorations.size(), 54, "decorations in Classic.bcc")
	check_eq(map.DecorationEntities.size(), 54, "one entity each")
	bus.Trigger(C.eiIdle, [])
	var part_index := -1
	for i in map.Decorations.size():
		if String(map.Decorations[i].ScriptFilename).ends_with("BridgePart1.ets"):
			part_index = i
			break
	check(part_index >= 0, "a BridgePart1")
	var desc: Dictionary = map.Decorations[part_index]
	var meshes := _mesh_components(map.DecorationEntities[part_index])
	check_eq(meshes.size(), 1, "BridgePart1 has one mesh")
	var mesh: TMesh = meshes[0].FMesh
	check(meshes[0].FIsStatic, "environment meshes are static")
	check(_near3(mesh.Position, desc.Position), "at the decoration's position")
	check(_near3(mesh.Front, (desc.Front as Vector3).normalized()), "facing the decoration's front")
	check(_near3(mesh.ScaleVector, Vector3.ONE * float(desc.Size) * 2.0 / 125.0), "legacy size factor * size")
	# Stones1 has size 0 in the file: it is drawn at size zero, like the original
	var stones: TEntity = map.DecorationEntities[0]
	check_eq(_mesh_components(stones)[0].FMesh.ScaleVector, Vector3.ZERO, "Stones1 with size 0")
	map.free()
	return take_failure()


## The stream copy of an entity: blackboard values arrive (position through the setter), the script builds the
## client side, the ID and UID are the server's.
func test_entity_serialize_deserialize() -> String:
	var server := _bus(C.nsServer)
	var client := _bus(C.nsClient)
	var entity := TEntity.new().Create(server, 77)
	_free.push_front(entity)
	entity.ScriptFile = "Environment\\Stones1"
	entity.UID = "uid-1"
	entity.Position = Vector2(3, 4)
	entity.Eventbus.Write(C.eiTeamID, [2])
	entity.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reHealth, 50.0)
	var stream := TEntityStream.new()
	entity.Serialize(stream)
	check_eq(stream.Read(), 77, "the ID comes first")
	var copy := TEntity.Deserialize(77, stream, client)
	check(copy != null, "built on the client")
	if copy == null:
		return take_failure()
	_free.push_front(copy)
	check_eq(copy.ID, 77, "server ID")
	check_eq(copy.UID, "uid-1", "server UID")
	check_eq(copy.Position, Vector2(3, 4), "position")
	check_eq(copy.TeamID(), 2, "team")
	check_eq(RParam.AsSingle(copy.Blackboard.GetIndexedValue(C.eiResourceCap, [], C.reHealth)), 50.0, "raw blackboard value")
	check_eq(_mesh_components(copy).size(), 1, "the client script's mesh")
	return take_failure()


## The sandbox (scenario "sandbox", map Single): the server's entities reach a TClientGame by their streams. The
## blue nexus stands at (-96, -23) (Scenarios\PvPBlue.dws), its crystal mesh shows the team's diffuse
## (Units\Neutral\Nexus.ets: NexusDiffuse.tga for team 1, NexusDiffuse2.tga for team 2) and plays its stand
## animation as the default (CreateNewAnimation(ANIMATION_STAND, 0, 200)).
func test_sandbox_entities_reach_the_client() -> String:
	if not _has_assets():
		return ""
	TTimeManager.FakeTime = 1000.0
	_thread = TGameThread.new().Create(TGameManager.CreateTestserverGameInfo())
	var info := TGameInformation.new().Create()
	info.ScenarioUID = BC.TESTSERVER_SCENARIO_UID
	info.League = BC.TESTSERVER_SENARIO_LEAGUE
	info.Scenario = HScenario.ResolveScenario(info.ScenarioUID, info.League)
	_client = TClientGame.new().Create(info)
	check_eq(_client.ClientMap.MapName, "Single", "sandbox map")
	var nexi: Array = []
	for copy: TEntity in _client.ReceiveWorld(_thread.InternalGame):
		if copy.ScriptFile.contains("Nexus"):
			nexi.append(copy)
	check_eq(TEntity.LastScriptError, "", "no script error")
	check_eq(nexi.size(), 2, "two nexus")
	_client.GlobalEventbus.Trigger(C.eiIdle, [])
	for nexus: TEntity in nexi:
		var crystal = null
		for mesh in _mesh_components(nexus):
			if mesh.FModelFileName.ends_with("NexusCrystal.xml"):
				crystal = mesh
		check(crystal != null, "nexus crystal mesh")
		if crystal == null:
			continue
		var expected := "nexusdiffuse.tga" if nexus.TeamID() == 1 else "nexusdiffuse2.tga"
		check_eq(String(crystal.FMesh.DiffuseTexture).to_lower(), expected, "team diffuse of team %d" % nexus.TeamID())
		check_eq(crystal.FMesh.AnimationController.DefaultAnimation, C.ANIMATION_STAND, "stand by default")
		# frames 0..200 of the take: its keyframes are 1000 / 30 ms apart, in whole ms
		check_eq(crystal.FMesh.AnimationController.GetAnimationLength(C.ANIMATION_STAND), roundi(200 * 1000.0 / 30.0), "200 frames")
		if nexus.TeamID() == 1:
			check_eq(nexus.DisplayPosition, Vector3(-96, 0, -23), "blue nexus display position")
			check(_near3(crystal.FMesh.Position, Vector3(-96, 0, -23)), "crystal at the nexus")
	return take_failure()


## The bone driver: the stand clip poses the bones at its frames; the controller only updates once per frame.
func test_mesh_animation_drives_bones() -> String:
	if not _has_assets():
		return ""
	TTimeManager.FakeTime = 0.0
	var bus := _bus()
	var entity := TEntity.new().Create(bus)
	_free.push_front(entity)
	var component := TMeshComponent.new().CreateGrouped(entity, [0], "Units\\Neutral\\Nexus\\NexusCrystal.xml") as TMeshComponent
	component.CreateNewAnimation(C.ANIMATION_STAND, 0, 200)
	var mesh := component.FMesh
	check(mesh.AnimationDriverBone.AnimationData.has(C.ANIMATION_STAND), "the stand clip is cut from the take")
	check_eq(mesh.AnimationController.DefaultAnimation, C.ANIMATION_STAND, "stand becomes the default")
	GFXD.NextFrame()
	mesh.Animate()
	var at_start := mesh._skin_matrix(0)
	# the crystal floats over the base (nexus.msh ends at y 14.175) while it spins
	check(mesh.GetPosedBoundingBox().position.y > 14.175, "floating")
	TTimeManager.FakeTime = 1234.0
	mesh.Animate()
	check(mesh._skin_matrix(0).is_equal_approx(at_start), "one update per frame (GFXD.FrameCount)")
	GFXD.NextFrame()
	mesh.Animate()
	check(not mesh._skin_matrix(0).is_equal_approx(at_start), "the next frame shows 1234 ms later")
	check(mesh.GetPosedBoundingBox().position.y > 14.175, "still floating")
	return take_failure()
