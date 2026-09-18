class_name TLaneManager
extends TObject
## Port of TLaneManager (BaseConflict.Map.pas:169, implementation :517): the map's lanes. The lanes are hard-coded
## ("Hacked values"): Create builds the two lanes of the classic map, `single` (called by the 1-lane scenario
## scripts) replaces them with the one lane of the single map.
## Port convention: the original reads the per-process Game global in GetLanePropertiesOfEntity; here the caller
## passes its Game (components: GlobalEventbus().Game), like RTarget. The pointer outs become a returned
## [TargetLane, Direction]. The client-only DebugRender comes with the client.

var FLanes: Array[TLane] = []

var Lanes: Array[TLane]:
	get:
		return FLanes


func Create() -> TLaneManager:
	var LANE_POINT1 := Vector2(-60, -11)
	var LANE_POINT2 := Vector2(-60, -35)
	var LANE_CENTER := Vector2(-60, -23)
	var NEXUS_POINT := Vector2(-96, 0)
	var LANE_END_DIRECTION1 := Vector2(-6, 11)
	var LANE_END_DIRECTION2 := Vector2(-1, 0)
	FLanes.clear()
	# Hacked values
	var Lane := TLane.new()
	Lane.AddWayPoint(
		RLine2D.CreateFromPoints(LANE_POINT1, LANE_POINT2),
		LANE_CENTER,
		[LANE_POINT1.direction_to(nXY(LANE_POINT1)), LANE_CENTER.direction_to(nXY(LANE_CENTER)), LANE_POINT2.direction_to(nXY(LANE_POINT2))],
		[LANE_END_DIRECTION1, LANE_CENTER.direction_to(NEXUS_POINT), LANE_END_DIRECTION2])
	Lane.AddWayPoint(
		RLine2D.CreateFromPoints(nXY(LANE_POINT1), nXY(LANE_POINT2)),
		nXY(LANE_CENTER),
		[nXY(LANE_END_DIRECTION1), nXY(LANE_CENTER.direction_to(NEXUS_POINT)), nXY(LANE_END_DIRECTION2)],
		[nXY(LANE_POINT1.direction_to(nXY(LANE_POINT1))), nXY(LANE_CENTER.direction_to(nXY(LANE_CENTER))), nXY(LANE_POINT2.direction_to(nXY(LANE_POINT2)))])
	FLanes.append(Lane)
	Lane = TLane.new()
	Lane.AddWayPoint(
		RLine2D.CreateFromPoints(XnY(LANE_POINT2), XnY(LANE_POINT1)),
		XnY(LANE_CENTER),
		[XnY(LANE_POINT2.direction_to(nXY(LANE_POINT2))), XnY(LANE_CENTER.direction_to(nXY(LANE_CENTER))), XnY(LANE_POINT1.direction_to(nXY(LANE_POINT1)))],
		[XnY(LANE_END_DIRECTION2), XnY(LANE_CENTER.direction_to(NEXUS_POINT)), XnY(LANE_END_DIRECTION1)])
	Lane.AddWayPoint(
		RLine2D.CreateFromPoints(-LANE_POINT2, -LANE_POINT1),
		-LANE_CENTER,
		[-LANE_END_DIRECTION2, -LANE_CENTER.direction_to(NEXUS_POINT), -LANE_END_DIRECTION1],
		[-LANE_POINT2.direction_to(nXY(LANE_POINT2)), -LANE_CENTER.direction_to(nXY(LANE_CENTER)), -LANE_POINT1.direction_to(nXY(LANE_POINT1))])
	FLanes.append(Lane)
	return self


static func nXY(v: Vector2) -> Vector2:
	return Vector2(-v.x, v.y)


static func XnY(v: Vector2) -> Vector2:
	return Vector2(v.x, -v.y)


func GetNextLaneToPoint(Position: Vector2) -> TLane:
	if FLanes.size() <= 0:
		return null
	var Result := FLanes[0]
	for i in FLanes.size():
		if FLanes[i].DistanceToPoint(Position) < Result.DistanceToPoint(Position):
			Result = FLanes[i]
	return Result


## GetLanePropertiesOfEntity(Game, Entity) or GetLanePropertiesOfEntity(Game, Position, TeamID):
## returns [TargetLane (or null), Direction].
func GetLanePropertiesOfEntity(Game, EntityOrPosition, TeamID: int = 0) -> Array:
	var Position: Vector2
	if EntityOrPosition is TEntity:
		Position = EntityOrPosition.Position
		TeamID = EntityOrPosition.TeamID()
	else:
		Position = EntityOrPosition
	var Direction := TLane.ldNormal
	# look for next lane and bind to it
	var TargetLane := GetNextLaneToPoint(Position)
	if TargetLane != null:
		var opponentNexus = Game.EntityManager.TryGetNexusNextEnemy(Position, TeamID)
		if opponentNexus != null:
			Direction = TargetLane.GetLaneDirection(opponentNexus.Position)
		else:
			# if I have no Nexus, I walk to the next end
			Direction = TargetLane.GetLaneDirection(Position)
	return [TargetLane, Direction]


func GetOrientationOfNextLane(Game, Position: Vector2, TeamID: int) -> Vector2:
	var Properties := GetLanePropertiesOfEntity(Game, Position, TeamID)
	if Properties[0] != null:
		return Properties[0].DirectionOnLane(Position, Properties[1])
	return Vector2(0, 1)  # RVector2.UNITY


func single() -> TLaneManager:
	var LANE_POINT1 := Vector2(-60, -11)
	var LANE_POINT2 := Vector2(-60, -35)
	var LANE_CENTER := Vector2(-60, -23)
	var NEXUS_POINT := Vector2(-96, -23)
	var LANE_END_DIRECTION1 := Vector2(-1, 0)
	var LANE_END_DIRECTION2 := Vector2(-1, 0)
	FLanes.clear()
	# Hacked values
	var Lane := TLane.new()
	Lane.AddWayPoint(
		RLine2D.CreateFromPoints(LANE_POINT1, LANE_POINT2),
		LANE_CENTER,
		[LANE_POINT1.direction_to(nXY(LANE_POINT1)), LANE_CENTER.direction_to(nXY(LANE_CENTER)), LANE_POINT2.direction_to(nXY(LANE_POINT2))],
		[LANE_END_DIRECTION1, LANE_CENTER.direction_to(NEXUS_POINT), LANE_END_DIRECTION2])
	Lane.AddWayPoint(
		RLine2D.CreateFromPoints(nXY(LANE_POINT1), nXY(LANE_POINT2)),
		nXY(LANE_CENTER),
		[nXY(LANE_END_DIRECTION1), nXY(LANE_CENTER.direction_to(NEXUS_POINT)), nXY(LANE_END_DIRECTION2)],
		[nXY(LANE_POINT1.direction_to(nXY(LANE_POINT1))), nXY(LANE_CENTER.direction_to(nXY(LANE_CENTER))), nXY(LANE_POINT2.direction_to(nXY(LANE_POINT2)))])
	FLanes.append(Lane)
	return self
