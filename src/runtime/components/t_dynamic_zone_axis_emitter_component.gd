class_name TDynamicZoneAxisEmitterComponent
extends TDynamicZoneEmitterComponent
## Port of TDynamicZoneAxisEmitterComponent (BaseConflict.EntityComponents.Shared.pas:606, implementation :2272).
## Emits a dynamic zone depending on the dot-product with a normal. >= 0 True

var FNormal := Vector2(0, 1)
var FPosition := Vector2(0, -3)


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FNormal = Vector2(0, 1)
	FPosition = Vector2(0, -3)
	return self


func IsInDynamicZone(Position: Vector2, _TeamID: int) -> int:
	# DirectionTo = (Target - self).Normalize; the zero vector stays zero (dot 0: inside)
	if FPosition.direction_to(Position).dot(FNormal) >= 0:
		return drTrue
	return drNone


func SetNormal(X: float, Y: float) -> TDynamicZoneAxisEmitterComponent:
	FNormal = Vector2(X, Y).normalized()
	return self


## As in the original, the position is normalized too.
func SetPosition(X: float, Y: float) -> TDynamicZoneAxisEmitterComponent:
	FPosition = Vector2(X, Y).normalized()
	return self
