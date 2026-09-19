class_name TPathfindingTile
extends TObject
## Port of TPathfindingTile (BaseConflict.Classes.Pathfinding.pas:45, implementation :464): one square of the
## pathfinding grid. Permanently blocked outside the walk zone, blocked while entities stand on it, and reserved
## per time slot (150 ms, 50 slots in a ring buffer) by the computed paths walking through it.
## Costs are singles (RParam.ToSingle where the original stores a single). Timestamps come from
## TTimeManager.GetTimeStamp (the original: GameTimeManager, the per-game clock; see TGameTimer).
## The map (the original's Map global) is the pathfinding's owner map.

const L = preload("res://src/runtime/dws/dws_lib.gd")

const TIMESLOTLENGTH = 150

var FGridPosition := Vector2i.ZERO
# RRectFloat WorldSpaceBoundaries as its four single edges (a Rect2 would round Right/Bottom through its size)
var FLeft := 0.0
var FTop := 0.0
var FRight := 0.0
var FBottom := 0.0
var FCenter := Vector2.ZERO
var FOwner: TPathfinding
var FNeighbours = null  # Array[TPathfindingTileNeighbour], built on first use
var FTargetHeuristicCost := 0.0
var FCostFromSource := 0.0
var FParent: TPathfindingTile = null
var FBlockingBeginnTime := 0
var FPermanentlyBlocked := false
var FBlockingEntities := {}  # TEntity -> true
var FBlockedTimeSlots: TRingBuffer

var GridPosition: Vector2i:
	get:
		return FGridPosition
## WorldSpaceBoundaries as a Rect2 (for display; the port computes with the exact edges).
var WorldSpaceBoundaries: Rect2:
	get:
		return Rect2(FLeft, FTop, FRight - FLeft, FBottom - FTop)
## WorldSpaceBoundaries.Center, the tile's position in every cost computation.
var Center: Vector2:
	get:
		return FCenter
var Neighbours: Array:
	get:
		return GetNeighboursList()


## Create(GridPosition, WorldSpaceBoundaries: RRectFloat, TIMESLOTLENGTH (unused), Owner) with the boundaries
## as their edges Left, Top, Right, Bottom (singles).
func Create(GridPosition_: Vector2i = Vector2i.ZERO, Left: float = 0, Top: float = 0, Right: float = 0,
		Bottom: float = 0, Owner: TPathfinding = null) -> TPathfindingTile:
	FGridPosition = GridPosition_
	FLeft = RParam.ToSingle(Left)
	FTop = RParam.ToSingle(Top)
	FRight = RParam.ToSingle(Right)
	FBottom = RParam.ToSingle(Bottom)
	FCenter = Vector2((FRight + FLeft) / 2, (FTop + FBottom) / 2)
	FPermanentlyBlocked = false
	FBlockedTimeSlots = TRingBuffer.new().Create(50, false)
	FOwner = Owner
	return self


func ComputeAndSetHeuristicCost(Source: TPathfindingTile, Target: TPathfindingTile, Direction: int, UseWaypoints: bool) -> void:
	var SourcePosition := Source.Center
	var TargetPosition := Target.Center
	# for waypoints heuristic use a more complex algorithm that compute the way cost along some waypoints
	if UseWaypoints:
		FTargetHeuristicCost = 0
		var Lane: TLane = FOwner.FMap.Lanes.GetNextLaneToPoint(SourcePosition)
		var LastSource := SourcePosition
		while true:
			var Next = Lane.TryGetNextWaypoint(LastSource, Direction)
			if Next == null:
				break
			TargetPosition = Next
			# ignore all waypoints before current position
			# else way back to first waypoint independently from current position (e.g. one field before nexus)
			# would be computed
			if (Direction == TLane.ldNormal and TargetPosition.x > Center.x) or \
					(Direction == TLane.ldReverse and TargetPosition.x < Center.x):
				if FTargetHeuristicCost == 0:
					FTargetHeuristicCost = RParam.ToSingle(FTargetHeuristicCost + (TargetPosition - Center).length())
				else:
					FTargetHeuristicCost = RParam.ToSingle(FTargetHeuristicCost + (TargetPosition - LastSource).length())
			LastSource = TargetPosition
		if FTargetHeuristicCost == 0:
			FTargetHeuristicCost = RParam.ToSingle(FTargetHeuristicCost + (Target.Center - Center).length())
		else:
			FTargetHeuristicCost = RParam.ToSingle(FTargetHeuristicCost + (Target.Center - LastSource).length())
	# no waypoints, use beeline as heuristic
	else:
		FTargetHeuristicCost = RParam.ToSingle((Target.Center - Center).length())


func TotalEstimatedCost() -> float:
	return RParam.ToSingle(FCostFromSource + FTargetHeuristicCost)


func ReserveTile(StartingTime: int, Duration: int) -> void:
	assert(StartingTime + Duration < TTimeManager.GetTimeStamp() + FBlockedTimeSlots.Size * TIMESLOTLENGTH)
	for t in L.Div(Duration, TIMESLOTLENGTH) + 1:
		FBlockedTimeSlots.SetItem(L.Div(StartingTime, TIMESLOTLENGTH) + t, true)


func ReleaseTile(StartingTime: int, Duration: int) -> void:
	assert(StartingTime + Duration < TTimeManager.GetTimeStamp() + FBlockedTimeSlots.Size * TIMESLOTLENGTH)
	for t in L.Div(Duration, TIMESLOTLENGTH) + 1:
		# protect slot be released when it was set by another index
		if FBlockedTimeSlots.IsIndexSet(L.Div(StartingTime, TIMESLOTLENGTH) + t):
			FBlockedTimeSlots.SetItem(L.Div(StartingTime, TIMESLOTLENGTH) + t, false)


## The 8 surrounding tiles inside the grid, row by row from the top left.
func GetNeighbours() -> Array:
	var Result: Array = []
	for Offset: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
		var NeighbourIndex := GridPosition + Offset
		if NeighbourIndex.x >= 0 and NeighbourIndex.x <= FOwner.TileWidthCount - 1 \
				and NeighbourIndex.y >= 0 and NeighbourIndex.y <= FOwner.TileHeightCount - 1:
			Result.append(FOwner.Grid(NeighbourIndex.x, NeighbourIndex.y))
	return Result


func GetNeighboursList() -> Array:
	if FNeighbours == null:
		FNeighbours = []
		for Neighbour: TPathfindingTile in GetNeighbours():
			FNeighbours.append(TPathfindingTileNeighbour.new().Create(self, Neighbour))
	return FNeighbours


func IsWalkable(_UnitSize: int) -> bool:
	return IsWalkableAtTime(TTimeManager.GetTimeStamp(), 0)


func IsWalkableAtTime(Time: int, StayDuration: int) -> bool:
	# no one should ever look if a tile is walkable in to far future
	assert(Time < TTimeManager.GetTimeStamp() + FBlockedTimeSlots.Size * TIMESLOTLENGTH)
	var blocked := IsBlocked()
	if not blocked:
		for t in L.Div(StayDuration, TIMESLOTLENGTH) + 1:
			blocked = blocked or FBlockedTimeSlots.GetItem(L.Div(Time, TIMESLOTLENGTH) + t)
			if blocked:
				break
	return not blocked


func IsPermanentlyBlocked() -> bool:
	return FPermanentlyBlocked


func IsBlocked() -> bool:
	return IsPermanentlyBlocked() or FBlockingEntities.size() > 0


## The neighbour with the lowest center distance + waypoint heuristic to Target (first of equals).
func GetOptimalNeighbour(Target: TPathfindingTile) -> TPathfindingTile:
	var BestCost := 3.40282347e+38  # Single.MaxValue
	var Best: TPathfindingTile = null
	for Neighbour: TPathfindingTile in GetNeighbours():
		var DistanceToNeighbourCenter := RParam.ToSingle((Neighbour.Center - Center).length())
		Neighbour.ComputeAndSetHeuristicCost(self, Target, TLane.ldNormal, true)
		var Cost := RParam.ToSingle(DistanceToNeighbourCenter + Neighbour.FTargetHeuristicCost)
		if Cost < BestCost:
			BestCost = Cost
			Best = Neighbour
	assert(BestCost != 3.40282347e+38)
	return Best


func BlockTile(Entity) -> void:
	FBlockingEntities[Entity] = true


func UnblockTile(Entity) -> void:
	FBlockingEntities.erase(Entity)


## Also breaks the reference cycles (neighbours, parent, owner) so the tiles are released.
func Destroy() -> void:
	FBlockingEntities.clear()
	FNeighbours = null
	FParent = null
	FOwner = null
	super()
