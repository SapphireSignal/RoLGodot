class_name TBrainFollowLaneComponent
extends TBrainComponent
## Port of TBrainFollowLaneComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:206,
## implementation :1501), server only. The inner need to walk the lane to its end: when not moving (and allowed to
## move) its chain (epLast) sends eiMoveTo [the enemy nexus (TryGetNexusNextEnemy: the farthest, quirk kept), own
## collision radius] and consumes the thought; without an enemy nexus it stands still. Every eiThinkChain it is
## reached in returns False. Binds to the nearest lane at eiAfterCreate and on returning from exile, and answers
## eiGetLane (TLane or null) / eiGetLaneDirection at epFirst.
## Port note: without Game.Map (tests) the lane stays null.

var FMoving := false
var FLane = null  # TLane
var FLaneDirection: int = TLane.ldNormal


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnExiled", C.eiExiled, C.epLast, C.etWrite))
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epMiddle, C.etTrigger))
	e.append(XEvent("OnMoveTargetReached", C.eiMoveTargetReached, C.epLast, C.etTrigger))
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epLast, C.etTrigger))
	e.append(XEvent("OnGetLane", C.eiGetLane, C.epFirst, C.etRead))
	e.append(XEvent("OnGetLaneDirection", C.eiGetLaneDirection, C.epFirst, C.etRead))


func AcquireLane() -> void:
	var game = BrainGame()
	if game == null or game.Map == null:
		return
	var Properties: Array = game.Map.Lanes.GetLanePropertiesOfEntity(game, Owner)
	FLane = Properties[0]
	FLaneDirection = Properties[1]


func OnAfterCreate() -> bool:
	AcquireLane()
	return true


## If the unit returns to the battlefield its lane is looked up again.
func OnExiled(Exiled) -> bool:
	if not RParam.AsBoolean(Exiled):
		AcquireLane()
	return true


func OnGetLane():
	return FLane


func OnGetLaneDirection():
	return FLaneDirection


func OnMoveTargetReached() -> bool:
	FMoving = false
	return true


func OnThinkChain() -> bool:
	return ThinkChainEvent()


func ThinkChain() -> bool:
	if not FMoving and CanMove():
		var game = BrainGame()
		var opponentNexus = game.EntityManager.TryGetNexusNextEnemy(Owner) if game != null else null
		if opponentNexus == null:
			return false  # there is no enemy nexus, so stand still
		var Next := RTarget.Create(opponentNexus)
		var MoveRange: float = Owner.CollisionRadius
		Eventbus().Trigger(C.eiMoveTo, [Next, MoveRange])
		# don't think about our move target until it's really needed
		FMoving = true
	return false
