class_name TBrainOverwatchComponent
extends TBrainComponent
## Port of TBrainOverwatchComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:258,
## implementation :2443), server only. Holds the position (and front) the unit has at eiAfterCreate: when not
## moving, able to move and more than 1.0 away, its chain (epLower) sends eiMoveTo [that spot, 0]. Every
## eiThinkChain it is reached in returns False. Back on the spot (eiMoveTargetReached) it turns to the old front.

var FTargetPosition := Vector2.ZERO
var FTargetDirection := Vector2.ZERO
var FMoving := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epMiddle, C.etTrigger))
	e.append(XEvent("OnMoveTargetReached", C.eiMoveTargetReached, C.epLast, C.etTrigger))
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epLower, C.etTrigger))


func IsAway() -> bool:
	return FTargetPosition.distance_to(Owner.Position) > 1.0


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


func ThinkChain() -> bool:
	if not FMoving and CanMove() and IsAway():
		Eventbus().Trigger(C.eiMoveTo, [RTarget.Create(FTargetPosition), 0.0])
		# don't think about our move target until it's really needed
		FMoving = true
	return false
