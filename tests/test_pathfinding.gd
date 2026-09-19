extends "res://tests/test_case.gd"
## Pathfinding (BaseConflict.Classes.Pathfinding.pas) on the Single map, and the engine structures it uses:
## TPriorityQueue / TIntPriorityQueue, TRingBuffer (Engine.Helferlein.DataStructures.pas), SameValue /
## CompareValue (System.Math). Expected values are worked out by hand from the original code.

const C = preload("res://src/runtime/dws/dws_const.gd")
const L = preload("res://src/runtime/dws/dws_lib.gd")
const NOW = 1000000.0

var _map: TMap
var _bus: TEventbus
var _unit: TEntity


class FakeEntityManager:
	extends RefCounted

	func TryGetNexusNextEnemy(_Position, _TeamID = 0):
		return null


class FakeGame:
	extends RefCounted
	var EntityManager := FakeEntityManager.new()

	func IsShuttingDown() -> bool:
		return false

	var Map: TMap


func _setup() -> void:
	TTimeManager.SetFakeTime(NOW)
	_map = TMap.new().CreateFromFile(TMap.MapFile("Single"))


func after_each() -> void:
	if _unit != null:
		_unit.Free()
		_bus.Game = null
		_bus.Free()
	if _map != null:
		_map.Free()
	_unit = null
	_bus = null
	_map = null
	TTimeManager.SetFakeTime(null)
	super()


func _tile(x: int, y: int) -> TPathfindingTile:
	return _map.Pathfinding.Grid(x, y)


func _positions(tiles: Array) -> Array:
	return tiles.map(func(t): return t.GridPosition)


func test_same_value() -> void:
	check(L.SameValue(100, 100.009), "relative 1E-4 of 100: 0.01")
	check(not L.SameValue(100, 100.011), "beyond 0.01")
	check(L.SameValue(0, 0.0001) and not L.SameValue(0, 0.0002), "at least 1E-4 absolute")
	check_eq([L.CompareValue(1, 2), L.CompareValue(2, 1), L.CompareValue(1, 1.00005)], [-1, 1, 0], "compare")


func test_priority_queue() -> void:
	var q := TPriorityQueue.new()
	for item in [["a", 3.0], ["b", 1.0], ["c", 2.0], ["d", 1.0]]:
		q.Insert(item[0], item[1])
	check_eq(q.Count, 4, "count")
	check_eq(q.Peek(), "d", "equal priorities: last in, first out")
	var order: Array = []
	while not q.IsEmpty():
		order.append(q.ExtractMin())
	check_eq(order, ["d", "b", "c", "a"], "extract order")
	q.Insert("f", 1.0)
	q.Insert("e", 1.00005)
	check_eq(q.ExtractMin(), "e", "within 1E-4: counts as equal, so the newer comes first")
	q.Clear()
	q.Insert("x", 5.0)
	q.Insert("y", 2.0)
	q.DecreaseKey("x", 1.0)
	check(q.Contains("x") and q.Count == 2, "decrease key keeps the item")
	check_eq(q.ExtractMin(), "x", "x now first")
	var iq := TIntPriorityQueue.new()
	iq.Insert("f", 10000)
	iq.Insert("e", 10001)
	check_eq(iq.ExtractMin(), "f", "int priorities compare exactly")


func test_ring_buffer() -> void:
	var r := TRingBuffer.new().Create(3, false)
	check_eq(r.Size, 3, "size")
	check(r.IsIndexSet(0) and not r.IsIndexSet(3), "every cell starts as index 0")
	check_eq(r.GetItem(0), false, "zero value")
	r.SetItem(4, true)
	check_eq(r.GetItem(4), true, "set")
	check(not r.IsIndexSet(1) and r.GetItem(1) == false, "cell 1 now belongs to index 4: default for 1")
	r.EnableDefaultValue = false
	check_eq(r.GetItem(1), true, "without default: the cell's value")
	r.Append(false)
	check_eq(r.LastIndex, 5, "append after the last index")


func test_grid() -> void:
	_setup()
	var pf := _map.Pathfinding
	# 300 / single(0.8) = 374.99999 -> 374 tiles each way
	check_eq([pf.TileWidthCount, pf.TileHeightCount], [374, 374], "tile counts")
	# (0,-23): (150 / 0.8, 127 / 0.8) = (187.5, 158.75) as singles -> tile 187,158
	var tile := pf.GetTileByPosition(Vector2(0, -23))
	check_eq(tile.GridPosition, Vector2i(187, 158), "tile under a position")
	check_eq(tile, _tile(187, 158), "the same tile object")
	check(absf(tile.Center.x) < 1e-4 and absf(tile.Center.y + 23.2) < 1e-4, "center %s" % tile.Center)
	check_eq(pf.GetTileByPosition(Vector2(200, 0)), null, "outside the boundaries")
	check(not tile.IsPermanentlyBlocked(), "inside the walk zone")
	check(pf.GetTileByPosition(Vector2(0, 0)).IsPermanentlyBlocked(), "outside the walk zone: blocked")
	check_eq(_tile(0, 0).Neighbours.size(), 3, "corner tile: 3 neighbours")
	check_eq(tile.Neighbours.size(), 8, "8 neighbours")
	check(is_equal_approx(tile.Neighbours[1].Cost, 0.8) and is_equal_approx(tile.Neighbours[0].Cost, 0.8 * sqrt(2)), "costs")
	check_eq(tile.Neighbours[0].NeighbourTile.GridPosition, Vector2i(186, 157), "neighbour order starts top left")
	tile.BlockTile(self)
	check(tile.IsBlocked() and not tile.IsWalkable(1), "blocked by an entity")
	tile.UnblockTile(self)
	check(tile.IsWalkable(1), "unblocked")


func test_straight_path() -> void:
	_setup()
	var path := _map.Pathfinding.ComputeDebugPath(_tile(187, 158), _tile(192, 158), 1000, TLane.ldNormal)
	check_eq(_positions(path), [Vector2i(187, 158), Vector2i(188, 158), Vector2i(189, 158), Vector2i(190, 158),
		Vector2i(191, 158), Vector2i(192, 158)], "straight east")
	check(is_equal_approx(_map.Pathfinding.ComputePathLength(path), 4.0), "length 5 * 0.8")


func test_detour_takes_the_last_inserted_of_equal_tiles() -> void:
	# 189,158 blocked: the detours north and south are equally long. Equal priorities come out last in, first out,
	# and the south tiles are inserted after the north ones (neighbour order), so the path goes south; it reaches
	# the target from 191,159 (fast break on the diagonal neighbour).
	_setup()
	_tile(189, 158).BlockTile(self)
	var path := _map.Pathfinding.ComputeDebugPath(_tile(187, 158), _tile(192, 158), 1000, TLane.ldNormal)
	check_eq(_positions(path), [Vector2i(187, 158), Vector2i(188, 158), Vector2i(189, 159), Vector2i(190, 159),
		Vector2i(191, 159), Vector2i(192, 158)], "detour south")


func test_max_path_length() -> void:
	_setup()
	# stops at the first extracted tile whose cost from the source reaches 2 (the third tile east, cost 2.4)
	var path := _map.Pathfinding.ComputeDebugPath(_tile(187, 158), _tile(200, 158), 2, TLane.ldNormal)
	check_eq(_positions(path), [Vector2i(187, 158), Vector2i(188, 158), Vector2i(189, 158), Vector2i(190, 158)], "cut")


func test_waypoint_heuristic() -> void:
	_setup()
	_map.Lanes.single()
	var source := _tile(187, 158)
	var target := _map.Pathfinding.GetTileByPosition(Vector2(96, -23))
	# west of the lane's waypoint line x = 60: via the waypoint (projected at the source's y), then to the target
	var west := _map.Pathfinding.GetTileByPosition(Vector2(40, -23))
	west.ComputeAndSetHeuristicCost(source, target, TLane.ldNormal, true)
	var wp := Vector2(60, source.Center.y)
	var expected := (wp - west.Center).length() + (target.Center - wp).length()
	check(absf(west.FTargetHeuristicCost - expected) < 1e-3, "via the waypoint: %s vs %s" % [west.FTargetHeuristicCost, expected])
	# east of it: the waypoint lies behind, so the beeline
	var east := _map.Pathfinding.GetTileByPosition(Vector2(80, -23))
	east.ComputeAndSetHeuristicCost(source, target, TLane.ldNormal, true)
	check(absf(east.FTargetHeuristicCost - (target.Center - east.Center).length()) < 1e-3, "waypoint behind: beeline")


func _walker(pos: Vector2, speed: float) -> void:
	_bus = TEventbus.new().Create(null)
	_bus.Game = FakeGame.new()
	_bus.Game.Map = _map
	_unit = TEntity.new().Create(_bus, 7)
	_unit.Position = pos
	_unit.Blackboard.SetValue(C.eiTeamID, [], 1)
	_unit.Blackboard.SetValue(C.eiSpeed, [], speed)
	_unit.Blackboard.SetValue(C.eiPathfindingTile, [], _map.Pathfinding.GetTileByPosition(pos))


func test_compute_path_reserves_time_slots() -> void:
	_setup()
	_walker(Vector2(0, -23), 0.01)
	var pf := _map.Pathfinding
	var path := pf.ComputePath(_unit, Vector2(4, -23), 100, false, false)
	check_eq(path.size(), 6, "six tiles east")
	check(pf.ComputedPaths.has(_unit), "remembered as the unit's path")
	# 188,158 is entered at Round((0 + 0.4) / 0.01) = 40 ms and left at 120 ms: slot (NOW + 40) div 150 only
	var tile := _tile(188, 158)
	check(not tile.IsWalkableAtTime(int(NOW) + 40, 0), "reserved while the unit passes")
	check(tile.IsWalkableAtTime(int(NOW) + 200, 0), "free in the next slot")
	pf.CancelLastComputedPath(_unit)
	check(not pf.ComputedPaths.has(_unit), "cancelled")
	check(tile.IsWalkableAtTime(int(NOW) + 40, 0), "cancelling releases the slots")
	_unit.Blackboard.SetValue(C.eiPathfindingTile, [], null)
	check_eq(pf.ComputePath(_unit, Vector2(4, -23), 100, false, false), [], "no current tile: no path")


func test_ignore_other_entities() -> void:
	# With IgnoreOtherEntities every tile that is not permanently blocked is walkable (the original's condition was
	# inverted: it only expanded blocked tiles, so only an adjacent target was found).
	_setup()
	_walker(Vector2(0, -23), 0.01)
	check_eq(_map.Pathfinding.ComputePath(_unit, Vector2(4, -23), 100, false, true).size(), 6, "5 tiles away: found")
	check_eq(_map.Pathfinding.ComputePath(_unit, Vector2(0.8, -23), 100, false, true).size(), 2, "adjacent: found")
