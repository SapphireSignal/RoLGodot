class_name TAutoBrainWelaTargetProducedUnitComponent
extends TAutoBrainComponent
## Port of TAutoBrainWelaTargetProducedUnitComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:520,
## implementation :1748), server only. At every eiWelaUnitProduced [EntityID] (epLast; FireOnlyAtUnitsInOwnGroup:
## only when called to a group sharing one with its own) fires eiFire at the produced unit in FireInGroup if the
## brain can think and eiIsReady / eiWelaTargetPossible there allow.

var FOnlyOwnGroup := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWelaUnitProduced", C.eiWelaUnitProduced, C.epLast, C.etTrigger))


func FireOnlyAtUnitsInOwnGroup() -> TAutoBrainWelaTargetProducedUnitComponent:
	FOnlyOwnGroup = true
	return self


func OnWelaUnitProduced(EntityID) -> bool:
	if not CanThink() or (FOnlyOwnGroup and
		not DSet.Intersects(ComponentGroup, TEventbus.GetCurrentEvent_CalledToGroup())):
		return true
	var Target := ATarget.ToRParam(ATarget.Make(RParam.AsInteger(EntityID)))
	if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], FFireGroup)) and \
		_TargetsPossible(Target, FFireGroup):
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(RParam.AsInteger(EntityID)))], FFireGroup)
	return true
