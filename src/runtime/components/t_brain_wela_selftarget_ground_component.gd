class_name TBrainWelaSelftargetGroundComponent
extends TBrainWelaComponent
## Port of TBrainWelaSelftargetGroundComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:383,
## implementation :1006), server only. Welas aimed at the ground at the owner's feet (e.g. a nova): every chain
## (epMiddle), if eiIsReady, fires at the owner's position, no target check (Blocking: stands first and consumes
## the thought).


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epMiddle, C.etTrigger))


func OnThinkChain() -> bool:
	return ThinkChainEvent()


func ThinkChain() -> bool:
	var Result := true
	if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)):
		# firing blocks the chain, so we have to break here
		if FBlocking:
			Eventbus().Trigger(C.eiStand, [])
			Result = false
		var OwnPosition: Vector2 = Owner.Position
		Eventbus().Trigger(FFireEvent, [ATarget.ToRParam(ATarget.Make(OwnPosition))], ComponentGroup)
	return Result
