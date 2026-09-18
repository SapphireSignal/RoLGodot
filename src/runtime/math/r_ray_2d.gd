class_name RRay2D
extends RefCounted
## Port of RRay2D (Engine\Engine.Math.Collision2D.pas:206): an infinite ray, Direction always normalized.
## A record in the original: treat it as a value.

var Origin := Vector2.ZERO
var FDirection := Vector2.ZERO

var Direction: Vector2:
	get:
		return FDirection
	set(Value):
		FDirection = Value.normalized()


static func Create(Origin_: Vector2, Direction_: Vector2) -> RRay2D:
	var Result := RRay2D.new()
	Result.Origin = Origin_
	Result.Direction = Direction_
	return Result


## Returns the intersection point; ZERO for parallel rays.
func IntersectionWithRay(otherRay: RRay2D) -> Vector2:
	var rs := Direction.cross(otherRay.Direction)
	if rs == 0:
		return Vector2.ZERO  # Parallel
	var u := (otherRay.Origin - Origin).cross(otherRay.Direction) / rs
	return Origin + (u * Direction)
