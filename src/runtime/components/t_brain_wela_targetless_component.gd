class_name TBrainWelaTargetlessComponent
extends TBrainWelaComponent
## Port of TBrainWelaTargetlessComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:397,
## implementation :1289), server only. Welas without a target (e.g. the factory ability): every chain (epMiddle),
## if eiIsReady, fires at one empty target (Blocking: stands first and consumes the thought).


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
		Eventbus().Trigger(FFireEvent, [ATarget.ToRParam(ATarget.CreateEmpty())], ComponentGroup)
	return Result
