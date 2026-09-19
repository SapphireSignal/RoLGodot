class_name TLane
extends TObject
## Port of TLane (BaseConflict.Map.pas:138, implementation :671, RWaypoint :898): a lane the units walk along,
## made of waypoint lines. Each waypoint projects points onto its line along directions that fan out between
## the border directions (index 0 = start, 1 = center, 2 = end; Normal for the left side, Reverse for the right).
## GetNextWaypoint is the nearest waypoint (the caller, DirectionOnLane, applies the direction). Fixed bug of the
## original: DistanceToPoint returned the distance to the LAST waypoint (its loop overwrote the minimum it started;
## docs/original-bugs.md). The client-only DebugRender comes with the client.

const ldNormal = 0  # EnumLaneDirection (BaseConflict.Types.Shared.pas:61)
const ldReverse = 1


class RWaypoint:
	extends RefCounted
	var Waypoint: RLine2D
	var ProjectionCenter := Vector2.ZERO
	var DirectionNormal: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]  # Start, Center, End
	var DirectionReverse: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]

	func ProjectPoint(Point: Vector2) -> Vector2:
		var LeftBorder: Vector2
		var RightBorder: Vector2
		var Endpoint: Vector2
		if Waypoint.IsLeft(Point):
			if DirectionNormal[1].cross(ProjectionCenter.direction_to(Point)) < 0:
				LeftBorder = DirectionNormal[1]
				RightBorder = DirectionNormal[2]
				Endpoint = Waypoint.Endpoint
			else:
				LeftBorder = DirectionNormal[1]
				RightBorder = DirectionNormal[0]
				Endpoint = Waypoint.Origin
		else:
			if DirectionReverse[1].cross(ProjectionCenter.direction_to(Point)) > 0:
				LeftBorder = DirectionReverse[1]
				RightBorder = DirectionReverse[2]
				Endpoint = Waypoint.Endpoint
			else:
				LeftBorder = DirectionReverse[1]
				RightBorder = DirectionReverse[0]
				Endpoint = Waypoint.Origin
		if LeftBorder.dot(RightBorder) >= 0.999:
			# parallel => direct projection onto lane
			return Waypoint.NearestPointOnLine(Point)
		var ProjectedPoint := RRay2D.Create(ProjectionCenter, LeftBorder).IntersectionWithRay(RRay2D.Create(Endpoint, RightBorder))
		return RRay2D.Create(ProjectedPoint, ProjectedPoint.direction_to(Point)).IntersectionWithRay(Waypoint.ToRay())


var FWayPoints: Array[RWaypoint] = []


func AddWayPoint(Waypoint: RLine2D, ProjectionCenter: Vector2, DirectionNormal: Array, DirectionReverse: Array) -> void:
	var aWaypoint := RWaypoint.new()
	aWaypoint.Waypoint = Waypoint
	aWaypoint.ProjectionCenter = ProjectionCenter
	for i in 3:
		aWaypoint.DirectionNormal[i] = DirectionNormal[i].normalized()
	for i in 3:
		aWaypoint.DirectionReverse[i] = DirectionReverse[i].normalized()
	FWayPoints.append(aWaypoint)


func GetNextWaypoint(Position: Vector2, _LaneDirection: int) -> RWaypoint:
	assert(FWayPoints.size() > 0)
	var Result := FWayPoints[0]
	for i in range(1, FWayPoints.size()):
		var dist := FWayPoints[i].Waypoint.DistanceToPoint(Position)
		if Result.Waypoint.DistanceToPoint(Position) > dist:
			Result = FWayPoints[i]
	return Result


func DistanceToPoint(Point: Vector2) -> float:
	var Result := 3.40282347e+38  # MaxSingle
	for i in FWayPoints.size():
		Result = minf(Result, FWayPoints[i].Waypoint.DistanceToPoint(Point))
	return Result


## Returns the direction of the lane if I want to walk to the endpoint.
func GetLaneDirection(Endpoint: Vector2) -> int:
	if FWayPoints[0].Waypoint.Center.distance_to(Endpoint) < FWayPoints[-1].Waypoint.Center.distance_to(Endpoint):
		return ldReverse
	return ldNormal


func DirectionOnLane(Point: Vector2, LaneDirection: int) -> Vector2:
	var Waypoint := GetNextWaypoint(Point, LaneDirection)
	var Result := Point.direction_to(Waypoint.ProjectPoint(Point))
	if Waypoint.Waypoint.IsLeft(Point) != (LaneDirection == ldReverse):
		Result = -Result
	return Result


## Returns the distance between Pos and Target weighted, so walking along the lane is cheaper than orthogonal
## to it.
func GetWeightedDistance(Pos: Vector2, Target: Vector2) -> float:
	# compute lane and orthogonal component
	var sstraight := (Target - Pos).length()
	var b := DirectionOnLane(Pos, ldNormal).normalized()
	var sorth := ((Target - Pos) - b.dot(Target - Pos) * b).length()
	var slane := absf(sstraight * sstraight - sorth * sorth)
	if slane > 0:
		slane = sqrt(slane)
	# walking orthogonal costs more
	return slane + sorth * 1.5


## TryGetNextWaypoint(Position, LaneDirection, out TargetPosition): the target position or null.
func TryGetNextWaypoint(Position: Vector2, LaneDirection: int):
	var First := true
	var Waypoint: RWaypoint = null
	for i in FWayPoints.size():
		var dist := FWayPoints[i].Waypoint.DistanceToPoint(Position)
		# due to precision errors don't detect waypoints very near
		if not (FWayPoints[i].Waypoint.IsLeft(Position) != (LaneDirection == ldReverse)) and dist > 1.0 \
				and (First or Waypoint.Waypoint.DistanceToPoint(Position) > dist):
			Waypoint = FWayPoints[i]
			First = false
	if First:
		return null
	return Waypoint.ProjectPoint(Position)
