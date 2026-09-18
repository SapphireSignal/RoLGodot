class_name TBrainFleeComponent
extends TBrainComponent
## Port of TBrainFleeComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:286, implementation
## :2667), server only. Runs back to the position (and front) it had at eiAfterCreate once it is Range or more away
## from it: its chain (epLow) then sends eiMoveTo [that spot, 0] and consumes the thought; while moving back it
## keeps consuming it. Back within 0.2 of the spot (eiMoveTargetReached) it turns to the old front.

var FTargetPosition := Vector2.ZERO
var FTargetDirection := Vector2.ZERO
var FRange := 0.0
var FMoving := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epMiddle, C.etTrigger))
	e.append(XEvent("OnMoveTargetReached", C.eiMoveTargetReached, C.epLast, C.etTrigger))
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epLow, C.etTrigger))


func IsAway() -> bool:
	return FTargetPosition.distance_to(Owner.Position) >= 0.2


func IsOutOFRange() -> bool:
	return FTargetPosition.distance_to(Owner.Position) >= FRange


func OnAfterCreate() -> bool:
	FTargetPosition = Owner.Position
	FTargetDirection = Owner.Front
	return true


func OnMoveTargetReached() -> bool:
	FMoving = false
	if not IsAway():
		Owner.Front = FTargetDirection
	return true


func OnThinkChain() -> bool:
	return ThinkChainEvent()


func Range(s: float) -> TBrainFleeComponent:
	FRange = RParam.ToSingle(s)
	return self


func ThinkChain() -> bool:
	var Result := not FMoving
	if not FMoving and CanMove() and IsOutOFRange():
		Eventbus().Trigger(C.eiMoveTo, [RTarget.Create(FTargetPosition), 0.0])
		# don't think about our move target until it's really needed
		FMoving = true
		Result = false
	return Result
