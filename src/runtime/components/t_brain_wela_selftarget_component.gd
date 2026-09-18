class_name TBrainWelaSelftargetComponent
extends TBrainWelaComponent
## Port of TBrainWelaSelftargetComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:345,
## implementation :1238), server only. Welas aimed at their owner (e.g. regeneration): every chain (epMiddle), if
## eiIsReady and the owner passes eiWelaTargetPossible, fires at the owner (Blocking: stands first and consumes
## the thought).


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epMiddle, C.etTrigger))


func OnThinkChain() -> bool:
	return ThinkChainEvent()


func ThinkChain() -> bool:
	var Result := true
	if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)):
		if _TargetsPossible(ATarget.ToRParam(ATarget.Make(FOwner)), ComponentGroup):
			# firing blocks the chain, so we have to break here
			if FBlocking:
				Eventbus().Trigger(C.eiStand, [])
				Result = false
			Eventbus().Trigger(FFireEvent, [ATarget.ToRParam(ATarget.Make(FOwner))], ComponentGroup)
	return Result
