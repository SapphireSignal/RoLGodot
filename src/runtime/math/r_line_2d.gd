class_name RLine2D
extends RefCounted
## Port of RLine2D (Engine\Engine.Math.Collision2D.pas:225): a finite line segment, Origin + Direction (the length
## of Direction is the length of the segment). A record in the original: treat it as a value.

var Origin := Vector2.ZERO
var Direction := Vector2.ZERO

var Endpoint: Vector2:
	get:
		return Origin + Direction
	set(Value):
		Direction = Value - Origin
var Center: Vector2:
	get:
		return Origin + (Direction * 0.5)


static func Create(Origin_: Vector2, Direction_: Vector2) -> RLine2D:
	var Result := RLine2D.new()
	Result.Origin = Origin_
	Result.Direction = Direction_
	return Result


func Length() -> float:
	return Direction.length()


static func CreateFromPoints(Startpoint: Vector2, Endpoint_: Vector2) -> RLine2D:
	var Result := RLine2D.new()
	Result.Origin = Startpoint
	Result.Endpoint = Endpoint_
	return Result


## Returns whether the given point lies at the left of the line looked from above an in direction.
func IsLeft(Point: Vector2) -> bool:
	return Origin.direction_to(Point).dot(Vector2(-Direction.y, Direction.x)) >= 0


## Returns the shortest distance of a point to the line.
func DistanceToPoint(Point: Vector2) -> float:
	return NearestPointOnLine(Point).distance_to(Point)


## Returns the closest point on the line to a point.
func NearestPointOnLine(Point: Vector2) -> Vector2:
	var dl := 1.0 / Direction.length()
	return clampf((Point - Origin).dot(Direction * dl) * dl, 0.0, 1.0) * Direction + Origin


## Returns the infinite ray which contains the line.
func ToRay() -> RRay2D:
	return RRay2D.Create(Origin, Direction)
