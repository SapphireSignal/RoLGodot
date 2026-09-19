class_name TAutoBrainOnResourceComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnResourceComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:715,
## implementation :3038), server only. At eiResourceTransaction [ResourceID, Amount] (trigger, epLower: before the
## resource manager books it; groupless only) of a TriggerOn resource, if the brain can think and eiIsReady of its
## group allows, fires eiFire at the owner in its group once per unit that still fits under the cap
## (min(cap - balance, Amount); singles truncated), but at most once without TimesForEach.

var FResource: Array = []
var FTimesForEach := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnTransact", C.eiResourceTransaction, C.epLower, C.etTrigger))


func OnTransact(ResourceID, Amount) -> bool:
	if not CanThink() or not TEventbus.GetCurrentEvent_CalledToGroup().is_empty():
		return true
	var ResourceType := RParam.AsInteger(ResourceID)
	var Ready := FResource.has(ResourceType)
	Ready = Ready and RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup))
	if Ready:
		var Group: Array = TEventbus.GetCurrentEvent_CalledToGroup().duplicate()
		var Times: int
		if BC.IsIntResource(ResourceType):
			Times = RParam.AsInteger(Owner.Cap(ResourceType, Group))
			Times = Times - RParam.AsInteger(Owner.Balance(ResourceType, Group))
			Times = mini(Times, RParam.AsInteger(Amount))
		else:
			var sTimes := RParam.AsSingle(Owner.Cap(ResourceType, Group))
			sTimes = RParam.ToSingle(sTimes - RParam.AsSingle(Owner.Balance(ResourceType, Group)))
			sTimes = minf(sTimes, RParam.AsSingle(Amount))
			Times = int(sTimes)
		if not FTimesForEach:
			Times = mini(Times, 1)
		for i in Times:
			Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Owner))], ComponentGroup)
	return true


func TimesForEach() -> TAutoBrainOnResourceComponent:
	FTimesForEach = true
	return self


func TriggerOn(Resource: Array) -> TAutoBrainOnResourceComponent:
	FResource = DSet.Make(Resource)
	return self
