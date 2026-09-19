class_name TPath
extends TObject
## Port of TPath (BaseConflict.Classes.Pathfinding.pas:99, implementation :653): a computed path. Freeing it
## releases the time slots its waypoints reserved, from the end back to the first waypoint that lies wholly in
## the past. Fixed bug of the original: a path that reserved nothing (ComputeDebugPath) released slots on freeing,
## other units' reservations; here only a reserved path releases (docs/original-bugs.md).

var FWaypoints: Array[TPathWaypoint] = []
## whether the pathfinding reserved the waypoints' time slots
var Reserved := false

var Waypoints: Array[TPathWaypoint]:
	get:
		return FWaypoints


func AddWaypoint(EnterTimestamp: int, StayDuration: int, Tile: TPathfindingTile) -> void:
	FWaypoints.append(TPathWaypoint.new().Create(EnterTimestamp, StayDuration, Tile))


func ReleasePath() -> void:
	if not Reserved:
		return
	var currentTime := TTimeManager.GetTimeStamp()
	for i in range(FWaypoints.size() - 1, -1, -1):
		# if any waypoint was completly walked in the past, no need to release this waypoint and all waypoints before
		if (FWaypoints[i].EnterTimestamp + FWaypoints[i].StayDuration) < currentTime:
			break
		FWaypoints[i].Tile.ReleaseTile(FWaypoints[i].EnterTimestamp, FWaypoints[i].StayDuration)


func Destroy() -> void:
	ReleasePath()
	FWaypoints.clear()
	super()
