class_name TThinkImpulseOnceComponent
extends TGDEntityComponent
## Port of TThinkImpulseOnceComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:86,
## implementation :2387), server only. Thinks once in its group, then frees itself: at the first global eiIdle
## (the second with WaitOneFrame; skipped while exiled), or at eiAfterCreate / eiDeploy (epLast) instead.

var FWaitOneFrame := false
var FTriggerOnAfterCreate := false
var FTriggerOnDeploy := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnDeploy", C.eiDeploy, C.epLast, C.etTrigger))
	e.append(XEvent("OnIdle", C.eiIdle, C.epMiddle, C.etTrigger, C.esGlobal))


func Trigger() -> void:
	Eventbus().Trigger(C.eiThink, [], ComponentGroup)
	Eventbus().Trigger(C.eiThinkChain, [], ComponentGroup)
	Free()


func OnAfterCreate() -> bool:
	if FTriggerOnAfterCreate:
		Trigger()
	return true


func OnDeploy() -> bool:
	if FTriggerOnDeploy:
		Trigger()
	return true


func OnIdle() -> bool:
	if not FTriggerOnAfterCreate and not FTriggerOnDeploy:
		if FWaitOneFrame:
			FWaitOneFrame = false
		elif not RParam.AsBoolean(Eventbus().Read(C.eiExiled, [])):
			Trigger()
	return true


func WaitOneFrame() -> TThinkImpulseOnceComponent:
	FWaitOneFrame = true
	return self


func TriggerOnAfterCreate() -> TThinkImpulseOnceComponent:
	FTriggerOnAfterCreate = true
	return self


func TriggerOnDeploy() -> TThinkImpulseOnceComponent:
	FTriggerOnDeploy = true
	return self
