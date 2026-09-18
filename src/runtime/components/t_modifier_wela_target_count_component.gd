class_name TModifierWelaTargetCountComponent
extends TModifierComponent
## Port of TModifierWelaTargetCountComponent (BaseConflict.EntityComponents.Shared.Wela.pas:78, implementation
## :2871). Adds eiWelaModifier of ValueGroup (only if > 0, optionally scaled by a resource) to eiWelaTargetCount;
## an empty target count counts as 1.

var FScalesWithResource: int = C.reNone


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWelaTargetCount", C.eiWelaTargetCount, C.epMiddle, C.etRead))


func OnWelaTargetCount(Previous):
	var AddValue := RParam.AsInteger(Eventbus().Read(C.eiWelaModifier, [], FValueGroup))
	if AddValue > 0:
		if FScalesWithResource != C.reNone:
			if BC.IsFloatResource(FScalesWithResource):
				AddValue = int(AddValue * RParam.AsSingle(Owner.Balance(FScalesWithResource, ComponentGroup)))
			else:
				AddValue = AddValue * RParam.AsInteger(Owner.Balance(FScalesWithResource, ComponentGroup))
		return RParam.AsIntegerDefault(Previous, 1) + AddValue
	return Previous


func ScaleWithResource(Resource: int) -> TModifierWelaTargetCountComponent:
	FScalesWithResource = Resource
	return self
