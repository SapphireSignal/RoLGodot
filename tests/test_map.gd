extends "res://tests/test_case.gd"
## The map (BaseConflict.Map.pas): TMap from the converted .bcm, TBuildZone / TBuildZoneManager, TLane /
## TLaneManager, the zone polygons (Engine.Math.Collision2D.pas) and the map-bound target constraints
## (TWelaTargetConstraint{Grid,BuildTeam,Zone}). Expected values are worked out by hand from the original code.

const C = preload("res://src/runtime/dws/dws_const.gd")
const PVP_BLUE = "res://src/content/scripts/server/Scenarios/PvPBlue.dws.gd"

var _bus: TEventbus
var _owner: TEntity


## Stands in for Game.ServerEntityManager: logs SpawnUnit calls.
class FakeServerEntityManager:
	extends RefCounted
	var Log: Array = []

	func SpawnUnit(X, Y, Script, TeamID) -> void:
		Log.append([Vector2(X, Y), Script, TeamID])


## Answers TryGetNexusNextEnemy with one fixed nexus (or none).
class FakeEntityManager:
	extends RefCounted
	var Nexus = null

	func TryGetNexusNextEnemy(_Position, _TeamID):
		return Nexus


class FakeNexus:
	extends RefCounted
	var Position := Vector2.ZERO


class FakeGame:
	extends RefCounted
	var IsShuttingDown := false
	var EntityManager = FakeEntityManager.new()
	var ServerEntityManager := FakeServerEntityManager.new()
	var Map: TMap
	var TwoLane := false

	func IsTwoLane() -> bool:
		return TwoLane


func _game(map_name: String) -> FakeGame:
	var game := FakeGame.new()
	game.Map = TMap.new().CreateFromFile(TMap.MapFile(map_name))
	return game


## The Single map with PvPBlue's build zone 0 (team 1) and a team 2 zone.
func _single_with_zones() -> FakeGame:
	var game := _game("Single")
	load(PVP_BLUE).new().Apply(null, game)
	game.Map.BuildZones.AddBuildZone(TBuildZone.new().Create(2).SetTeam(2).SetPosition(106.7, -23.0).SetSize(8, 3) \
		.SetFront(-1.0, 0.0).SetSpawnTarget(90.0, -23.0, 1.0, 0.0).Block(0, 0).Block(7, 0).Block(0, 2).Block(7, 2))
	return game


## A wela owner of team 1 on a bus whose Game is `game`.
func _setup(game: FakeGame) -> void:
	_bus = TEventbus.new().Create(null)
	_bus.Game = game
	_owner = TEntity.new().Create(_bus, 1)
	_owner.Blackboard.SetValue(C.eiTeamID, [], 1)
	_owner.Deploy()


func _teardown() -> void:
	if _owner != null:
		_owner.Free()
		_bus.Game = null
		_bus.Free()
	_bus = null
	_owner = null


func after_each() -> void:
	_teardown()
	super()


func _valid(target: RTarget) -> bool:
	var validity = _owner.Eventbus.Read(C.eiWelaTargetPossible, [ATarget.ToRParam([target])], [1])
	return RTargetValidity.FromRParam(validity).IsValid()


func _near(a: Vector2, b: Vector2, eps := 1e-3) -> bool:
	return a.distance_to(b) < eps


func test_map_from_file() -> void:
	var map := TMap.new().CreateFromFile(TMap.MapFile("Single"))
	check_eq(map.TeamCount, 2, "team count")
	check_eq(map.PlayerCount, 4, "player count")
	check_eq(map.TeamSize(), 2, "team size")
	check_eq(map.MapBoundaries, Rect2(-150, -150, 300, 300), "boundaries")
	check_eq(map.Zones.keys().size(), 5, "zones")
	check(map.Zones.has(C.ZONE_WALK) and map.Zones.has(C.ZONE_DROP), "walk and drop zone")
	check_eq(map.Filepath, "res://src/content/maps/Single.json", "file path")
	check_eq(map.Lanes.Lanes.size(), 2, "two hard-coded lanes until a scenario calls single")
	map.Free()
	var empty := TMap.new().CreateEmpty()
	check_eq(empty.MapBoundaries, Rect2(-100, -100, 200, 200), "default boundaries")
	check_eq(empty.TeamSize(), 0, "no teams: team size 0")


func test_multipolygon_with_hole() -> void:
	# Classic's drop zone: an outer ring with a subtractive hole around the middle lane.
	var map := TMap.new().CreateFromFile(TMap.MapFile("Classic"))
	var drop: TMultipolygon = map.Zones[C.ZONE_DROP]
	check(drop.IsPointInMultiPolygon(Vector2(0, 20)), "between hole and border: inside")
	check(not drop.IsPointInMultiPolygon(Vector2(0, 0)), "in the hole: outside")
	check(not drop.IsPointInMultiPolygon(Vector2(0, 40)), "beyond the border: outside")
	# nearest border of (0,0): the hole's top edge (first of two at distance 13), pushed 1e-4 further out
	var clamped := map.ClampToZone(C.ZONE_DROP, Vector2.ZERO)
	check(_near(clamped, Vector2(0, 13.0001), 1e-5), "clamped out of the hole: %s" % clamped)
	check(drop.IsPointInMultiPolygon(clamped), "the clamped point is inside")
	check_eq(map.ClampToZone(C.ZONE_DROP, Vector2(0, 20)), Vector2(0, 20), "inside stays")
	check_eq(map.ClampToZone("NoSuchZone", Vector2(1, 2)), Vector2(1, 2), "unknown zone: unchanged")
	map.Free()


func test_build_zone_from_scenario_script() -> void:
	var game := _single_with_zones()
	check_eq(game.ServerEntityManager.Log.size(), 2, "one lane: nexus and lane tower spawned")
	var zone: TBuildZone = game.Map.BuildZones.GetBuildZone(0)
	check(zone != null and zone.TeamID == 1, "zone 0 belongs to team 1")
	check_eq(zone.Size, Vector2i(8, 3), "size")
	check_eq(zone.Front, Vector2(1, 0), "front")
	check_eq(zone.Left, Vector2(0, 1), "left = orthogonal of front")
	check_eq(zone.SpawnDirection, Vector2(-1, 0), "spawn direction")
	# field (x, y) center = Center + 2 * Front * (y - 1) + 2 * Left * (x - 3.5)
	check(_near(zone.GetCenterOfField(0, 0), Vector2(-108.7, -30)), "field 0,0")
	check(_near(zone.GetCenterOfField(Vector2i(7, 2)), Vector2(-104.7, -16)), "field 7,2")
	check_eq(zone.PositionToCoord(zone.GetCenterOfField(3, 1)), Vector2i(3, 1), "center of field 3,1 maps back")
	# on a field border Round is banker's rounding: 3.5 -> 4, 2.5 -> 2
	check_eq(zone.PositionToCoord(zone.Center), Vector2i(4, 1), "x 3.5 rounds to 4")
	check_eq(zone.PositionToCoord(zone.Center + Vector2(0, -2)), Vector2i(2, 1), "x 2.5 rounds to 2")
	check(zone.IsBanned(0, 0) and zone.IsBanned(Vector2i(7, 2)), "corners are blocked")
	check(not zone.InRange(Vector2i(0, 0)), "a banned field is out of range")
	check(zone.InRange(Vector2i(1, 0)) and not zone.InRange(Vector2i(8, 0)) and not zone.InRange(Vector2i(-1, 0)), "range")
	check(zone.IsFree(Vector2i(20, 20)) and not zone.IsBanned(Vector2i(20, 20)), "outside the grid reads free")
	var manager: TBuildZoneManager = game.Map.BuildZones
	check_eq(manager.GetBuildZoneByPosition(zone.GetCenterOfField(3, 1)), zone, "zone by position")
	check_eq(manager.GetBuildZoneByPosition(zone.GetCenterOfField(0, 0)), null, "banned corner: no zone")
	check_eq(manager.GetBuildZoneByPosition(game.Map.BuildZones.GetBuildZone(2).GetCenterOfField(3, 1)).TeamID, 2, "zone 2")
	zone.SetFieldID(Vector2i(3, 1), 42)
	check_eq(manager.GetWaveEntityIDByCoord(0, Vector2i(3, 1)), 42, "blocking entity by coord")
	check_eq(manager.GetWaveEntityIDByCoord(9, Vector2i(3, 1)), -1, "unknown zone: -1")
	manager.UpdateEntityIDInBuildZones(42, 50)
	check_eq(zone.GetFieldID(Vector2i(3, 1)), 50, "entity ID replaced")
	check(not zone.IsFree(Vector2i(3, 1)), "blocked field is not free")
	zone.SetSize(8, 3)
	check(zone.IsFree(Vector2i(3, 1)) and not zone.IsBanned(0, 0), "setting the size frees every field")
	game.Map.Free()


func test_lanes() -> void:
	var lanes := TLaneManager.new().Create()
	# Classic lane 1, first waypoint: the line x = -60 from y -11 to -35. (-70,-23) is right of it, so the
	# reverse directions fan it: ray from the center along (-36,23) meets the ray from (-60,-35) along (-1,0) at
	# (-60 + 432/23, -35); from there towards the point onto the line: y = -35 + 12 * 432/662.
	var projected: Vector2 = lanes.Lanes[0].FWayPoints[0].ProjectPoint(Vector2(-70, -23))
	check(_near(projected, Vector2(-60, -35 + 12.0 * 432 / 662)), "fanned projection: %s" % projected)
	lanes.single()
	check_eq(lanes.Lanes.size(), 1, "single lane")
	var lane: TLane = lanes.Lanes[0]
	check_eq(lane.GetLaneDirection(Vector2(-96, -23)), TLane.ldReverse, "towards the blue nexus: reverse")
	check_eq(lane.GetLaneDirection(Vector2(96, -23)), TLane.ldNormal, "towards the red nexus: normal")
	check(is_equal_approx(lane.DistanceToPoint(Vector2(0, -23)), 60), "distance (to the last waypoint)")
	check_eq(lane.TryGetNextWaypoint(Vector2(0, -23), TLane.ldNormal), Vector2(60, -23), "next waypoint east")
	check_eq(lane.TryGetNextWaypoint(Vector2(0, -23), TLane.ldReverse), Vector2(-60, -23), "next waypoint west")
	check_eq(lane.TryGetNextWaypoint(Vector2(70, -23), TLane.ldNormal), null, "past the last waypoint: none")
	check(_near(lane.DirectionOnLane(Vector2(0, -23), TLane.ldNormal), Vector2(1, 0)), "normal walks east")
	check(_near(lane.DirectionOnLane(Vector2(0, -23), TLane.ldReverse), Vector2(-1, 0)), "reverse walks west")
	var game := FakeGame.new()
	var nexus := FakeNexus.new()
	nexus.Position = Vector2(96, -23)
	game.EntityManager.Nexus = nexus
	check_eq(lanes.GetLanePropertiesOfEntity(game, Vector2(0, -23), 1), [lane, TLane.ldNormal], "to the enemy nexus")
	game.EntityManager.Nexus = null
	check_eq(lanes.GetLanePropertiesOfEntity(game, Vector2(-10, -23), 1)[1], TLane.ldReverse, "no nexus: nearer end")
	check(_near(lanes.GetOrientationOfNextLane(game, Vector2(-10, -23), 1), Vector2(-1, 0)), "orientation")


func test_grid_constraint() -> void:
	var game := _single_with_zones()
	_setup(game)
	TWelaTargetConstraintGridComponent.new().CreateGrouped(_owner, [1])
	_owner.Blackboard.SetValue(C.eiWelaNeededGridSize, [1], Vector2i(2, 1))
	check(_valid(RTarget.CreateBuildTarget(0, Vector2i(3, 1))), "fields 3,1 and 4,1 free")
	check(not _valid(RTarget.CreateBuildTarget(0, Vector2i(6, 0))), "7,0 is banned")
	check(not _valid(RTarget.CreateBuildTarget(0, Vector2i(7, 1))), "8,1 is outside the grid")
	check(not _valid(RTarget.CreateBuildTarget(9, Vector2i(3, 1))), "unknown zone")
	check(not _valid(RTarget.Create(Vector2(-106.7, -23))), "not a build target")
	game.Map.BuildZones.GetBuildZone(0).SetFieldID(Vector2i(4, 1), 42)
	check(not _valid(RTarget.CreateBuildTarget(0, Vector2i(3, 1))), "4,1 blocked by an entity")
	game.Map.Free()


func test_build_team_constraint() -> void:
	var game := _single_with_zones()
	_setup(game)
	TWelaTargetConstraintBuildTeamComponent.new().CreateGrouped(_owner, [1])
	check(_valid(RTarget.CreateBuildTarget(0, Vector2i(3, 1))), "own team's zone")
	check(not _valid(RTarget.CreateBuildTarget(2, Vector2i(3, 1))), "enemy zone")
	check(not _valid(RTarget.CreateBuildTarget(9, Vector2i(3, 1))), "unknown zone")
	check(not _valid(RTarget.Create(Vector2(-106.7, -23))), "not a build target")
	game.Map.Free()


func test_zone_constraint() -> void:
	var game := _game("Classic")
	_setup(game)
	var drop = TWelaTargetConstraintZoneComponent.new().CreateGrouped(_owner, [1], C.ZONE_DROP, false)
	check(_valid(RTarget.Create(Vector2(0, 20))), "inside the drop zone")
	check(not _valid(RTarget.Create(Vector2(0, 0))), "in the hole")
	# (0,20): the hole's top edge is 7 away, the outer border 13
	drop.SetPadding(5)
	check(_valid(RTarget.Create(Vector2(0, 20))), "7 from the border, padding 5")
	drop.SetPadding(8)
	check(not _valid(RTarget.Create(Vector2(0, 20))), "7 from the border, padding 8")
	game.Map.Free()
	_teardown()
	# Prefix: zone name + owner team ID ("Spell1"); a missing zone allows everything
	game = _game("Single")
	_setup(game)
	TWelaTargetConstraintZoneComponent.new().CreateGrouped(_owner, [1], "Spell", true)
	check(_valid(RTarget.Create(Vector2(0, -20))), "inside Spell1")
	check(not _valid(RTarget.Create(Vector2(0, 0))), "outside Spell1")
	_owner.Blackboard.SetValue(C.eiTeamID, [], 3)
	check(_valid(RTarget.Create(Vector2(0, 0))), "no Spell3 zone: allowed")
	game.Map.Free()
