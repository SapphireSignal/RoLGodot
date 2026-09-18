class_name TPathfinding
extends TObject
## Port of TPathfinding (BaseConflict.Classes.Pathfinding.pas:110, implementation :168): A* over a square grid
## of TileSize tiles covering the map boundaries (PATHFINDING_TILE_SIZE 0.8 on 300 x 300: 374 x 374 tiles).
## Tiles outside the walk zone are permanently blocked. A computed path reserves the time slots of its tiles
## (when each tile is entered and until the next one is), so later paths of other units avoid them; each
## entity keeps its last path (ComputedPaths) until it cancels it or computes a new one.
## Port notes: tiles are created on first access instead of all up front (a tile depends only on its grid
## position, the boundaries and the walk zone, so this is invisible and saves building 140k objects per map).
## The original reads the Map global (the running game's map) for the lanes; here the pathfinding keeps its map.
## The lane direction of an entity needs the entity's Game (its global bus's Game). Out-of-range Grid access
## raises EPathfindingError in the original: here push_error and null.

const L = preload("res://src/runtime/dws/dws_lib.gd")
const C = preload("res://src/runtime/dws/dws_const.gd")

var FTileWidthCount := 0
var FTileHeightCount := 0
var FGrid: Array = []  # x * FTileHeightCount + y -> TPathfindingTile (null until first access)
var FTileSize := 0.0
var FMapBoundaries := Rect2()
var FWalkableZone: TMultipolygon
var FMaxUnitSize := 0
var FComputedPaths := {}  # TEntity -> TPath (owned)
var FMap = null  # TMap

var ComputedPaths: Dictionary:
	get:
		return FComputedPaths
var TileWidthCount: int:
	get:
		return FTileWidthCount
var TileHeightCount: int:
	get:
		return FTileHeightCount
var TileSize: float:
	get:
		return FTileSize
	set(Value):
		ClearGrid()
		FTileSize = RParam.ToSingle(Value)
		CreateGrid()
var MaxUnitSize: int:
	get:
		return FMaxUnitSize
	set(Value):
		FMaxUnitSize = Value


## Create(TileSize, MaxUnitSize, MapBoundaries, WalkableZone) + the owning map (the original's Map global).
func Create(TileSize_: float = 0, MaxUnitSize_: int = 0, MapBoundaries: Rect2 = Rect2(),
		WalkableZone: TMultipolygon = null, Map = null) -> TPathfinding:
	FTileSize = RParam.ToSingle(TileSize_)
	FMaxUnitSize = MaxUnitSize_
	FMapBoundaries = MapBoundaries
	FWalkableZone = WalkableZone
	FMap = Map
	CreateGrid()
	return self


func CreateGrid() -> void:
	# every tile is quadratic, so width = height
	FTileHeightCount = int(FMapBoundaries.size.y / FTileSize)
	FTileWidthCount = int(FMapBoundaries.size.x / FTileSize)
	FGrid.resize(FTileWidthCount * FTileHeightCount)
	FGrid.fill(null)


## CreateGrid + InitGridWithWorldData for one tile.
func CreateTile(X: int, Y: int) -> TPathfindingTile:
	var Left := FMapBoundaries.position.x
	var Top := FMapBoundaries.position.y
	var Tile := TPathfindingTile.new().Create(Vector2i(X, Y), Left + X * FTileSize, Top + Y * FTileSize,
		Left + (X + 1) * FTileSize, Top + (Y + 1) * FTileSize, self)
	if not FWalkableZone.IsPointInMultiPolygon(Tile.Center):
		# setting freespace to a negative value, will mark them as occupied
		Tile.FPermanentlyBlocked = true
	return Tile


func ClearGrid() -> void:
	for Tile in FGrid:
		if Tile != null:
			Tile.Free()
	FGrid.clear()


## Grid[X, Y] / GridBy2D[xy].
func Grid(X: int, Y: int) -> TPathfindingTile:
	if X < 0 or X >= FTileWidthCount:
		push_error("TPathfinding.GetTile: Index X out of bound.")
		return null
	if Y < 0 or Y >= FTileHeightCount:
		push_error("TPathfinding.GetTile: Index Y out of bound.")
		return null
	var Index := X * FTileHeightCount + Y
	if FGrid[Index] == null:
		FGrid[Index] = CreateTile(X, Y)
	return FGrid[Index]


## The tile under a position, null outside the map boundaries (edges included).
func GetTileByPosition(Position: Vector2) -> TPathfindingTile:
	var Left := FMapBoundaries.position.x
	var Top := FMapBoundaries.position.y
	if Left <= Position.x and Position.x <= FMapBoundaries.end.x and Top <= Position.y and Position.y <= FMapBoundaries.end.y:
		# TileIndex is an RVector2: singles
		var TileIndexX := RParam.ToSingle((Position.x - Left) / FTileSize)
		var TileIndexY := RParam.ToSingle((Position.y - Top) / FTileSize)
		return Grid(int(TileIndexX), int(TileIndexY))
	return null


## Computes a path for the entity from its current tile (eiPathfindingTile) to the target position, reserves it
## and remembers it as the entity's path. Returns the tiles from source to target (or up to CancelPathLength),
## an empty array if the entity has no tile or no path exists.
func ComputePath(Entity: TEntity, TargetPosition: Vector2, CancelPathLength: int, UseWaypoints: bool,
		IgnoreOtherEntities: bool) -> Array:
	var Source = RParam.AsObject(Entity.Eventbus.Read(C.eiPathfindingTile, []))
	if Source == null:
		return []
	CancelLastComputedPath(Entity)
	var Target := GetTileByPosition(TargetPosition)
	assert(Target != null)
	var Game = Entity.GlobalEventbus.Game if Entity.GlobalEventbus != null else null
	var Direction: int = FMap.Lanes.GetLanePropertiesOfEntity(Game, Entity)[1]
	var Path := DoPathfinding(Source, Target, Direction, CancelPathLength,
		RParam.AsSingle(Entity.Eventbus.Read(C.eiSpeed, [])), UseWaypoints, IgnoreOtherEntities, true)
	if Path == null:
		return []
	assert(not FComputedPaths.has(Entity))
	FComputedPaths[Entity] = Path
	return Path.Waypoints.map(func(Waypoint): return Waypoint.Tile)


func ComputeDebugPath(Start: TPathfindingTile, Target: TPathfindingTile, MaxPathLength: int, Direction: int) -> Array:
	var Result: Array = []
	var Path := DoPathfinding(Start, Target, Direction, MaxPathLength, 1, false, false, false)
	if Path != null:
		Result = Path.Waypoints.map(func(Waypoint): return Waypoint.Tile)
		Path.Free()
	return Result


func ComputePathLength(Path: Array) -> float:
	var Result := 0.0
	if Path.size() > 1:
		for i in range(1, Path.size()):
			Result += (Path[i].Center - Path[i - 1].Center).length()
	return Result


## Drops the entity's last path, releasing its reserved time slots.
func CancelLastComputedPath(Entity) -> void:
	if FComputedPaths.has(Entity):
		FComputedPaths[Entity].Free()
		FComputedPaths.erase(Entity)


# return the path from source to endtile, by following the path (endtile.FParent) until parent is nil
static func GetPathToSource(EndTile: TPathfindingTile) -> Array:
	assert(EndTile != null)
	var Path: Array = []
	while true:
		Path.append(EndTile)
		EndTile = EndTile.FParent
		if EndTile == null:
			break
	Path.reverse()
	return Path


func DoPathfinding(Source: TPathfindingTile, Target: TPathfindingTile, Direction: int, MaxPathLength: int,
		EntityMovementSpeed: float, UseWaypoints: bool, IgnoreOtherEntities: bool, ReservePath: bool) -> TPath:
	assert(EntityMovementSpeed > 0)
	var TileDiagonalLength := RParam.ToSingle(sqrt(2 * FTileSize * FTileSize))
	var OpenList := TPriorityQueue.new()
	var ClosedList := {}
	var PathFound := false
	var StartingTime := TTimeManager.GetTimeStamp()
	var CurrentTile: TPathfindingTile
	# init start node
	Source.FCostFromSource = 0
	Source.FParent = null
	Source.FBlockingBeginnTime = StartingTime
	# and after init add them as first node for pahtfinding
	OpenList.Insert(Source, Source.TotalEstimatedCost())
	while true:
		CurrentTile = OpenList.ExtractMin()
		# found way to target, we are finsihed or if the computed path is long enough
		if CurrentTile == Target or CurrentTile.FCostFromSource >= MaxPathLength:
			PathFound = true
			break
		ClosedList[CurrentTile] = true
		for Neighbour: TPathfindingTileNeighbour in CurrentTile.Neighbours:
			var NeighbourTile := Neighbour.NeighbourTile
			# calculate the time is needed to cross the boundaries of the current tile and enter the neighbour tile in ms
			var EnterNeighbourTime := L.Round((CurrentTile.FCostFromSource + Neighbour.Cost / 2) / EntityMovementSpeed)
			# assume maximum length (walking diagonal)
			var NeighbourStayDuration := L.Round(TileDiagonalLength / EntityMovementSpeed)
			# fast break if any way to reach target is found
			if NeighbourTile == Target:
				NeighbourTile.FParent = CurrentTile
				NeighbourTile.FCostFromSource = RParam.ToSingle(CurrentTile.FCostFromSource + Neighbour.Cost)
				NeighbourTile.FBlockingBeginnTime = StartingTime + EnterNeighbourTime
				CurrentTile = NeighbourTile
				PathFound = true
				break
			if ((not IgnoreOtherEntities and NeighbourTile.IsWalkableAtTime(StartingTime + EnterNeighbourTime, NeighbourStayDuration))
					or (IgnoreOtherEntities and NeighbourTile.IsPermanentlyBlocked())) and not ClosedList.has(NeighbourTile):
				if not OpenList.Contains(NeighbourTile):
					NeighbourTile.FParent = CurrentTile
					NeighbourTile.FCostFromSource = RParam.ToSingle(CurrentTile.FCostFromSource + Neighbour.Cost)
					NeighbourTile.ComputeAndSetHeuristicCost(Source, Target, Direction, UseWaypoints)
					NeighbourTile.FBlockingBeginnTime = StartingTime + EnterNeighbourTime
					OpenList.Insert(NeighbourTile, NeighbourTile.TotalEstimatedCost())
				else:
					var newCost := RParam.ToSingle(CurrentTile.FCostFromSource + Neighbour.Cost)
					if NeighbourTile.FCostFromSource > newCost:
						NeighbourTile.FParent = CurrentTile
						NeighbourTile.FCostFromSource = newCost
						NeighbourTile.FBlockingBeginnTime = StartingTime + EnterNeighbourTime
						OpenList.DecreaseKey(NeighbourTile, NeighbourTile.TotalEstimatedCost())
		if OpenList.IsEmpty() or PathFound:
			break
	if not PathFound:
		return null
	# construct path from from source (0) to currenttile (high) by backtracking the moved path
	var Waypoints := GetPathToSource(CurrentTile)
	var Result := TPath.new()
	# block timeslots
	for i in Waypoints.size():
		var EnterTimestamp: int = Waypoints[i].FBlockingBeginnTime
		var Duration: int
		# if i is the last node in route, block until can move into middle
		if i == Waypoints.size() - 1:
			Duration = L.Round(TileDiagonalLength * 0.5 / EntityMovementSpeed)
		else:
			# blocking tile while when tile is entered and until the next tile is entered
			Duration = Waypoints[i + 1].FBlockingBeginnTime - Waypoints[i].FBlockingBeginnTime
		if ReservePath:
			Waypoints[i].ReserveTile(EnterTimestamp, Duration)
		Result.AddWaypoint(EnterTimestamp, Duration, Waypoints[i])
	return Result


func Destroy() -> void:
	for Path: TPath in FComputedPaths.values():
		Path.Free()
	FComputedPaths.clear()
	ClearGrid()
	FMap = null
	super()
