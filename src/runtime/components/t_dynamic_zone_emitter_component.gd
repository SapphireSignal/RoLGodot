class_name TDynamicZoneEmitterComponent
extends TEntityComponent
## Port of TDynamicZoneEmitterComponent (BaseConflict.EntityComponents.Shared.pas:581, implementation :2226).
## Emits a dynamic zone around this unit. Abstract: subclasses override IsInDynamicZone.
## eiInDynamicZone (global read, [Position, TeamID, Zone]) returns empty, true or false; once false, nothing turns
## it true again.

## EnumDynamicZoneResult
enum { drNone, drTrue, drFalse }

var FDynamicZone: Array = []  # SetDynamicZone
var FNegate := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnInDynamicZone", C.eiInDynamicZone, C.epMiddle, C.etRead, C.esGlobal))


## Virtual, abstract in the original.
func IsInDynamicZone(_Position: Vector2, _TeamID: int) -> int:
	push_error("TDynamicZoneEmitterComponent.IsInDynamicZone is abstract")
	return drNone


## Checks whether the position is covered by this emitter.
func OnInDynamicZone(Position, TeamID, Zone, Previous):
	var Result = Previous
	# check if zone type matches this emitters zone type
	if DSet.Intersects(FDynamicZone, RParam.AsSet(Zone)):
		# if result is false, nothing can turn this to true
		if RParam.IsEmpty(Previous) or RParam.AsBoolean(Previous):
			var Res := IsInDynamicZone(RParam.AsVector2(Position), RParam.AsInteger(TeamID))
			if FNegate and Res == drTrue:
				Res = drFalse
			match Res:
				drNone:
					Result = Previous
				drTrue:
					Result = true
				drFalse:
					Result = false
	return Result


func SetZone(Zone: Array) -> TDynamicZoneEmitterComponent:
	FDynamicZone = DSet.Make(Zone)  # ByteArrayToSetDynamicZone
	return self


func Exclude() -> TDynamicZoneEmitterComponent:
	FNegate = true
	return self
