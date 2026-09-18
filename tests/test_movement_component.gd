extends "res://tests/test_case.gd"
## TPositionComponent, TMovementComponent, TPathfindingComponent (BaseConflict.EntityComponents.Shared.pas:651-1001,
## :2161-2224) on the Single map. Expected values are worked out from the Pascal methods named in each test; the
## tile numbers and centers come from tests/test_pathfinding.gd (tile 187,158 holds (0,-23), centers 0.8 apart).

const C = preload("res://src/runtime/dws/dws_const.gd")
const NOW = 1000000.0

var _map: TMap
var _free: Array = []
var _buses: Array = []
var _mc: TMovementComponent  # the last _unit's


## Records the movement events: Log holds [event name, parameters...] in call order.
class MoveProbe:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnSyncPath", C.eiSyncPath, C.epLast, C.etTrigger))
		e.append(XEvent("OnSyncPosition", C.eiSyncPosition, C.epLast, C.etTrigger))
		e.append(XEvent("OnMoveTargetReached", C.eiMoveTargetReached, C.epLast, C.etTrigger))

	func Names() -> Array:
		return Log.map(func(entry): return entry[0])

	func All(name: String) -> Array:
		return Log.filter(func(entry): return entry[0] == name)

	func OnSyncPath(Start, Target, Path) -> bool:
		Log.append(["SyncPath", Start, Target, Path.duplicate()])
		return true

	func OnSyncPosition(Pos) -> bool:
		Log.append(["SyncPosition", Pos])
		return true

	func OnMoveTargetReached() -> bool:
		Log.append(["MoveTargetReached"])
		return true


class FakeEntityManager:
	extends RefCounted
	var Entities := {}

	func TryGetNexusNextEnemy(_Position, _TeamID):
		return null

	func TryGetEntityByID(ID: int):
		return Entities.get(ID)

	func GetEntityByID(ID: int):
		return Entities.get(ID)


class FakeGame:
	extends RefCounted
	var IsShuttingDown := false
	var EntityManager := FakeEntityManager.new()
	var Map: TMap


func before_each() -> void:
	TTimeManager.FakeTime = NOW
	TTimeManager.ZDiff = 0.0


func after_each() -> void:
	for o in _free:
		o.Free()
	_free.clear()
	_mc = null
	for bus in _buses:
		bus.Game = null
		bus.Free()
	_buses.clear()
	if _map != null:
		_map.Free()
		_map = null
	TTimeManager.FakeTime = null
	TTimeManager.ZDiff = 0.0
	TEntity.LastScriptError = ""
	super()


func _bus(side: int = C.nsServer, with_map: bool = true) -> TEventbus:
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = side
	bus.Game = FakeGame.new()
	if with_map:
		if _map == null:
			_map = TMap.new().CreateFromFile(TMap.MapFile("Single"))
			_map.Lanes.single()
		bus.Game.Map = _map
	_buses.append(bus)
	return bus


## A unit at pos with speed (per ms), TMovementComponent (+ TPathfindingComponent when pathfinding) and a probe,
## after eiAfterCreate. Returns the probe (probe.Owner is the unit).
func _unit(bus: TEventbus, pos: Vector2, speed: float, pathfinding: bool, id: int = 7) -> MoveProbe:
	var e := TEntity.new().Create(bus, id)
	_free.push_front(e)
	e.Position = pos
	e.Blackboard.SetValue(C.eiTeamID, [], 1)
	e.Blackboard.SetValue(C.eiSpeed, [], speed)
	e.Blackboard.SetIndexedValue(C.eiUnitData, [], C.udUsePathfinding, pathfinding)
	_mc = TMovementComponent.new().Create(e)
	if pathfinding:
		TPathfindingComponent.new().Create(e)
	var probe := MoveProbe.new().Create(e) as MoveProbe
	e.Eventbus.Trigger(C.eiAfterCreate, [])
	return probe


func _tile(x: int, y: int) -> TPathfindingTile:
	return _map.Pathfinding.Grid(x, y)


func _idle(bus: TEventbus, times: int = 1) -> void:
	for i in times:
		bus.Trigger(C.eiIdle, [])


func _move_to(e: TEntity, target, range_: float = 0.0) -> void:
	e.Eventbus.Trigger(C.eiMoveTo, [RTarget.Create(target), range_])


## TPositionComponent.OnSyncPosition: the owner jumps there.
func test_sync_position() -> void:
	var e := TEntity.new().Create(_bus(C.nsServer, false), 7)
	_free.push_front(e)
	TPositionComponent.new().Create(e)
	e.Eventbus.Trigger(C.eiSyncPosition, [Vector2(3, 4)])
	check_eq(e.Position, Vector2(3, 4), "moved")


## IdleDirect with ZDiff 2 and speed 0.5: 1 per idle (exact). From (0,0) to (10,0) with range 2: at (7,0) the rest
## 3 - 2 <= 1, so the 8th idle puts it at target - SetLength(2) = (8,0) and stands.
func test_direct_walk() -> void:
	var bus := _bus(C.nsServer, false)
	var probe := _unit(bus, Vector2.ZERO, 0.5, false)
	var e: TEntity = probe.Owner
	TTimeManager.ZDiff = 2.0
	_move_to(e, Vector2(10, 0), 2.0)
	check_eq(e.Eventbus.Read(C.eiIsMoving, []), true, "moving")
	check_eq(probe.Log, [["SyncPosition", Vector2.ZERO]], "server: syncs the start")
	_idle(bus)
	check_eq(e.Position, Vector2(1, 0), "one step")
	check_eq(e.Front, Vector2(1, 0), "facing the way")
	_idle(bus, 6)
	check_eq(e.Position, Vector2(7, 0), "seven steps")
	check_eq(e.Eventbus.Read(C.eiMoveTargetReached, []), false, "3 - 2 > 0.1")
	_idle(bus)
	check_eq(e.Position, Vector2(8, 0), "stops at range")
	check_eq(e.Eventbus.Read(C.eiIsMoving, []), false, "stands")
	check_eq(e.Eventbus.Read(C.eiMoveTargetReached, []), true, "within range")
	check_eq(probe.Names(), ["SyncPosition", "SyncPosition", "MoveTargetReached"], "stand syncs and reports")
	_idle(bus)
	check_eq(e.Position, Vector2(8, 0), "standing still")


## OnMoveTo: an empty target does nothing; the same target while moving stops the event (returns False);
## eiStand only reports when it was moving; eiDie / eiExiled(true) stand.
func test_move_to_and_stops() -> void:
	var bus := _bus(C.nsServer, false)
	var probe := _unit(bus, Vector2.ZERO, 0.5, false)
	var e: TEntity = probe.Owner
	e.Eventbus.Trigger(C.eiMoveTo, [RTarget.CreateEmpty(), 1.0])
	check_eq(e.Eventbus.Read(C.eiIsMoving, []), false, "empty target: no move")
	_move_to(e, Vector2(10, 0))
	_move_to(e, Vector2(10.05, 0))
	check_eq(probe.All("SyncPosition").size(), 1, "equal within SPATIALEPSILON while moving: ignored")
	_move_to(e, Vector2(0, 10))
	check_eq(probe.All("SyncPosition").size(), 2, "a new target restarts")
	e.Eventbus.Trigger(C.eiDie, [0, 0])
	check_eq(e.Eventbus.Read(C.eiIsMoving, []), false, "dead: stands")
	check_eq(probe.All("MoveTargetReached").size(), 1, "stand reports once")
	e.Eventbus.Trigger(C.eiStand, [])
	check_eq(probe.All("MoveTargetReached").size(), 1, "not moving: nothing to report")
	_move_to(e, Vector2(10, 0))
	e.Eventbus.Write(C.eiExiled, [false])
	check_eq(e.Eventbus.Read(C.eiIsMoving, []), true, "not exiled: keeps moving")
	e.Eventbus.Write(C.eiExiled, [true])
	check_eq(e.Eventbus.Read(C.eiIsMoving, []), false, "exiled: stands")


## OnLose: the server only clears FMoving (no stand events); the client stands.
func test_lose() -> void:
	var server := _bus(C.nsServer, false)
	var sp := _unit(server, Vector2.ZERO, 0.5, false)
	_move_to(sp.Owner, Vector2(10, 0))
	server.Trigger(C.eiLose, [1])
	check_eq(sp.Owner.Eventbus.Read(C.eiIsMoving, []), false, "server: stopped")
	check_eq(sp.All("MoveTargetReached").size(), 0, "server: silently")
	var client := _bus(C.nsClient, false)
	var cp := _unit(client, Vector2.ZERO, 0.5, false)
	_move_to(cp.Owner, Vector2(10, 0))
	client.Trigger(C.eiLose, [1])
	check_eq(cp.All("MoveTargetReached").size(), 1, "client: stands")


## The server re-syncs the position every UNITSYNCINTERVAL (3000 ms) on idle, moving or not.
func test_sync_timer() -> void:
	var bus := _bus(C.nsServer, false)
	var probe := _unit(bus, Vector2(1, 2), 0.5, false)
	_idle(bus)
	check_eq(probe.Log, [], "not yet")
	TTimeManager.FakeTime = NOW + 3000
	_idle(bus, 2)
	check_eq(probe.Log, [["SyncPosition", Vector2(1, 2)]], "once, then restarted")


## TPathfindingComponent: blocks its tile on eiAfterCreate, answers eiPathfindingTile, unblocks the old tile when
## the position changes tile (without blocking the new one), blocks again on eiStand, unblocks when freed.
func test_pathfinding_component_blocks_tiles() -> void:
	var bus := _bus()
	var e := TEntity.new().Create(bus, 7)
	e.Position = Vector2(0, -23)
	var pc := TPathfindingComponent.new().Create(e)
	e.Eventbus.Trigger(C.eiAfterCreate, [])
	check_eq(e.Eventbus.Read(C.eiPathfindingTile, []), _tile(187, 158), "current tile")
	check(_tile(187, 158).IsBlocked(), "blocked on create")
	e.Position = Vector2(0.8, -23)
	check_eq(e.Eventbus.Read(C.eiPathfindingTile, []), _tile(188, 158), "follows the position")
	check(not _tile(187, 158).IsBlocked() and not _tile(188, 158).IsBlocked(), "moving blocks nothing")
	e.Eventbus.Trigger(C.eiStand, [])
	check(_tile(188, 158).IsBlocked(), "standing blocks")
	e.Position = Vector2(200, 0)
	check_eq(e.Eventbus.Read(C.eiPathfindingTile, []), _tile(188, 158), "off the map: keeps the last tile")
	pc.Free()
	check(not _tile(188, 158).IsBlocked(), "freed: unblocked")
	e.Free()


## Server with pathfinding: eiMoveTo computes the path (TPathfinding.ComputePath, test_pathfinding's straight
## east path 187..192) and sends it as eiSyncPath; the unit walks the tile centers (y -23.2), then towards the
## exact target on the last tile, and stands as soon as it is on the target's tile (192 spans x 3.6 .. 4.4).
func test_pathfinding_walk() -> void:
	var bus := _bus()
	var probe := _unit(bus, Vector2(0, -23), 0.5, true)
	var e: TEntity = probe.Owner
	TTimeManager.ZDiff = 1.0
	_move_to(e, Vector2(4, -23))
	var sync := probe.All("SyncPath")
	check_eq(sync.size(), 1, "one path")
	if sync.size() != 1:
		return
	check_eq(sync[0][1], Vector2(0, -23), "start")
	check_eq(sync[0][2], Vector2(4, -23), "target")
	check_eq(sync[0][3], [Vector2i(187, 158), Vector2i(188, 158), Vector2i(189, 158), Vector2i(190, 158),
		Vector2i(191, 158), Vector2i(192, 158)], "tile coordinates")
	check(_map.Pathfinding.ComputedPaths.has(e), "path reserved")
	_idle(bus)
	# 0.2 down to the first center, then 0.3 of the 0.8 east
	check(absf(e.Position.x - 0.3) < 1e-4 and absf(e.Position.y + 23.2) < 1e-4, "first step %s" % e.Position)
	check(_tile(187, 158).IsBlocked(), "still on the start tile: still blocked")
	_idle(bus)
	check(not _tile(187, 158).IsBlocked(), "x 0.8 is tile 188: the start tile is free")
	for i in 20:
		if not e.Eventbus.Read(C.eiIsMoving, []):
			break
		_idle(bus)
	check_eq(e.Eventbus.Read(C.eiIsMoving, []), false, "arrived")
	check_eq(e.Eventbus.Read(C.eiPathfindingTile, []), _tile(192, 158), "on the target tile")
	check(e.Position.x >= 3.6 and e.Position.x <= 4.0, "stopped on entering it: %s" % e.Position)
	check(_tile(192, 158).IsBlocked(), "standing blocks the tile")
	check(not _map.Pathfinding.ComputedPaths.has(e), "path released")
	check_eq(probe.All("SyncPath").size(), 1, "no new path needed")
	check_eq(probe.All("MoveTargetReached").size(), 1, "reported")


## Server: when the next tile of the path gets blocked (and is not the current one), the next idle computes a
## new path from the current tile instead of moving.
func test_pathfinding_repaths_around_a_blocked_tile() -> void:
	var bus := _bus()
	var probe := _unit(bus, Vector2(0, -23), 0.5, true)
	var e: TEntity = probe.Owner
	TTimeManager.ZDiff = 1.0
	_move_to(e, Vector2(4, -23))
	_idle(bus)
	var before := e.Position
	_tile(188, 158).BlockTile(self)
	_idle(bus)
	check_eq(e.Position, before, "no step on the re-path idle")
	var sync := probe.All("SyncPath")
	check_eq(sync.size(), 2, "a new path")
	if sync.size() == 2:
		check(not sync[1][3].has(Vector2i(188, 158)), "around the blocked tile: %s" % [sync[1][3]])
		check_eq(sync[1][3][0], Vector2i(187, 158), "from the current tile")
	for i in 30:
		if not e.Eventbus.Read(C.eiIsMoving, []):
			break
		_idle(bus)
	check_eq(e.Eventbus.Read(C.eiPathfindingTile, []), _tile(192, 158), "still arrives")
	_tile(188, 158).UnblockTile(self)


## Client OnSyncPath: OptimizePath keeps the first and last node and drops every node whose optimal neighbour
## (waypoint heuristic; the Single lane's waypoint line x = 60 lies east, so east is optimal) is the next node.
## A straight path shrinks to its ends; the speed is scaled by length(optimized) / length(path) = 4.0 / 4.0.
func test_client_optimizes_the_path() -> void:
	var bus := _bus(C.nsClient)
	var probe := _unit(bus, Vector2(0, -23.2), 0.5, true)
	var e: TEntity = probe.Owner
	var mc := _mc
	var path := [Vector2i(187, 158), Vector2i(188, 158), Vector2i(189, 158), Vector2i(190, 158),
		Vector2i(191, 158), Vector2i(192, 158)]
	e.Eventbus.Trigger(C.eiSyncPath, [Vector2(0, -23.2), Vector2(4, -23.2), path])
	check_eq(mc.FPath, [Vector2i(192, 158), Vector2i(187, 158)], "ends only, reversed")
	check(mc.FOverwriteMovementSpeed and absf(mc.FOverwrittenSpeed - 0.5) < 1e-5, "same length: same speed %s" % mc.FOverwrittenSpeed)
	e.Eventbus.Trigger(C.eiSyncPath, [Vector2(0, -23.2), Vector2(0.8, -23.2), [Vector2i(187, 158), Vector2i(188, 158)]])
	check_eq(mc.FPath, [Vector2i(188, 158), Vector2i(187, 158)], "two nodes: unchanged")
	check(not mc.FOverwriteMovementSpeed, "own speed")


## Real script: the server Footman (speed 4/1000 per ms, udUsePathfinding) walks 4 east on the Single map.
func test_footman_walks() -> void:
	var bus := _bus()
	var e := TEntity.CreateFromScript("Units\\White\\Footman", bus)
	check(e != null, "created: " + TEntity.LastScriptError)
	if e == null:
		return
	_free.push_front(e)
	e.Position = Vector2(0, -23)
	e.Eventbus.Trigger(C.eiAfterCreate, [])
	check_eq(e.Eventbus.Read(C.eiPathfindingTile, []), _tile(187, 158), "on its tile")
	TTimeManager.ZDiff = 100.0
	_move_to(e, Vector2(4, -23))
	check_eq(e.Eventbus.Read(C.eiIsMoving, []), true, "walking")
	var idles := 0
	while e.Eventbus.Read(C.eiIsMoving, []) and idles < 30:
		_idle(bus)
		idles += 1
	check_eq(e.Eventbus.Read(C.eiPathfindingTile, []), _tile(192, 158), "arrived on the target tile")
	# 0.4 per idle: 0.2 to the first center, 2.8 along the centers to x 2.8, then into 192 (x >= 3.6)
	check_eq(idles, 10, "0.4 per idle, 3.6+ to go")
