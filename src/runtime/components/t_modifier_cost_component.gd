class_name TModifierCostComponent
extends TModifierComponent
## Port of TModifierCostComponent (BaseConflict.EntityComponents.Shared.Wela.pas:207, implementation :1282).
## Adds eiWelaModifier of ValueGroup (optionally times a resource balance of its group) to every entry of
## eiResourceCost read from its own groups (IsLocalCall). Integer resources get the integer part of the offset.

var FScalesWithResource: int = C.reNone


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnResourceCost", C.eiResourceCost, C.epMiddle, C.etRead))


func OnResourceCost(Previous):
	if RParam.IsEmpty(Previous) or not IsLocalCall():
		return Previous
	var CostOffset = Eventbus().Read(C.eiWelaModifier, [], FValueGroup)
	var Factor = RParam.RPARAMEMPTY
	if FScalesWithResource != C.reNone:
		Factor = Owner.Balance(FScalesWithResource, ComponentGroup)
	var Costs: Array = RParam.AsArray(Previous)
	for Cost in Costs:
		if BC.IsFloatResource(Cost.ResourceType):
			var sFactor := RParam.AsSingle(CostOffset)
			if BC.IsFloatResource(FScalesWithResource):
				sFactor = RParam.ToSingle(sFactor * RParam.AsSingle(Factor))
			elif BC.IsIntResource(FScalesWithResource):
				sFactor = RParam.ToSingle(sFactor * RParam.AsInteger(Factor))
			Cost.Amount = RParam.ToSingle(RParam.AsSingle(Cost.Amount) + sFactor)
		else:
			var iFactor := RParam.AsInteger(CostOffset)
			if BC.IsFloatResource(FScalesWithResource):
				iFactor = int(iFactor * RParam.AsSingle(Factor))
			elif BC.IsIntResource(FScalesWithResource):
				iFactor = iFactor * RParam.AsInteger(Factor)
			Cost.Amount = RParam.AsInteger(Cost.Amount) + iFactor
	return RResourceCost.ToRParam(Costs)


func ScaleWithResource(ResType: int) -> TModifierCostComponent:
	FScalesWithResource = ResType
	return self
