class_name TResourceManagerComponent
extends TEntityComponent
## Port of TResourceManagerComponent (BaseConflict.EntityComponents.Shared.pas:386, implementation :1804).
## Component for handling resource within an entity. TEntity.Create adds one (ALLGROUP) to every entity.
## Balances, caps and costs live in the blackboard indexed by EnumResource, under the group the event was called to.
## Int resources (RES_INT_RESOURCES) are handled as integers, the rest as singles.

const BC = preload("res://src/runtime/base_conflict_constants.gd")

## TDictionary<integer, RParam> of the initial balances, null before eiAfterCreate.
var FInitialValues = null


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnResetResource", C.eiResourceReset, C.epLast, C.etTrigger))
	e.append(XEvent("OnGetResource", C.eiResourceBalance, C.epFirst, C.etRead))
	e.append(XEvent("OnSetResource", C.eiResourceBalance, C.epLast, C.etWrite))
	e.append(XEvent("OnCanTransact", C.eiResourceTransaction, C.epFirst, C.etRead))
	e.append(XEvent("OnTransact", C.eiResourceTransaction, C.epLast, C.etTrigger))
	e.append(XEvent("OnCanTransactNegative", C.eiResourceSubtraction, C.epFirst, C.etRead))
	e.append(XEvent("OnTransactNegative", C.eiResourceSubtraction, C.epLast, C.etTrigger))
	e.append(XEvent("OnGetResourceCap", C.eiResourceCap, C.epFirst, C.etRead))
	e.append(XEvent("OnSetResourceCap", C.eiResourceCap, C.epLast, C.etWrite))
	e.append(XEvent("OnGetResourceCost", C.eiResourceCost, C.epFirst, C.etRead))
	e.append(XEvent("OnSetResourceCost", C.eiResourceCost, C.epLast, C.etWrite))
	e.append(XEvent("OnResourceCapTransaction", C.eiResourceCapTransaction, C.epLast, C.etTrigger))


func Destroy() -> void:
	FInitialValues = null
	super()


## Save initial values.
func OnAfterCreate() -> bool:
	FInitialValues = FOwner.Blackboard.GetIndexMap(C.eiResourceBalance, [])
	return true


## Return whether transaction can be made inbound.
func OnCanTransact(ResourceID, Amount, _Previous):
	var Group: Array = TEventbus.CurrentEvent_CalledToGroup
	var Balance = FOwner.Blackboard.GetIndexedValue(C.eiResourceBalance, Group, RParam.AsInteger(ResourceID))
	if BC.IsIntResource(RParam.AsInteger(ResourceID)):
		var iAmount := RParam.AsInteger(Amount)
		return iAmount >= 0 or RParam.AsInteger(Balance) + iAmount >= 0
	var sAmount := RParam.AsSingle(Amount)
	return sAmount >= 0 or RParam.ToSingle(RParam.AsSingle(Balance) + sAmount) >= 0


## Return whether negative transaction can be made inbound.
func OnCanTransactNegative(ResourceID, Amount, Previous):
	if BC.IsIntResource(RParam.AsInteger(ResourceID)):
		return OnCanTransact(ResourceID, -RParam.AsInteger(Amount), Previous)
	return OnCanTransact(ResourceID, -RParam.AsSingle(Amount), Previous)


## Returns the balance of the resource.
func OnGetResource(ResourceID, _Previous):
	return FOwner.Blackboard.GetIndexedValue(C.eiResourceBalance, TEventbus.CurrentEvent_CalledToGroup, RParam.AsInteger(ResourceID))


## Returns the upper bound of the resource.
func OnGetResourceCap(ResourceID, _Previous):
	return FOwner.Blackboard.GetIndexedValue(C.eiResourceCap, TEventbus.CurrentEvent_CalledToGroup, RParam.AsInteger(ResourceID))


## Returns the amount of the resources: an AResourceCost (Array of RResourceCost) or RPARAM_EMPTY.
## Port: the original lists the entries in TDictionary hash order; here they are sorted by resource.
func OnGetResourceCost(_Previous):
	var Map: Dictionary = FOwner.Blackboard.GetIndexMap(C.eiResourceCost, TEventbus.CurrentEvent_CalledToGroup)
	if Map.is_empty():
		return RParam.RPARAMEMPTY
	var keys := Map.keys()
	keys.sort()
	var Cost: Array = []
	for key in keys:
		Cost.append(RResourceCost.new(key, Map[key]))
	return RResourceCost.ToRParam(Cost)


func OnResetResource(ResourceID) -> bool:
	if FInitialValues != null and FInitialValues.has(RParam.AsInteger(ResourceID)):
		Eventbus().Write(C.eiResourceBalance, [ResourceID, FInitialValues[RParam.AsInteger(ResourceID)]])
	return true


## Adjusts the upper bound of the resource.
func OnResourceCapTransaction(ResourceID, Amount, Empty) -> bool:
	var Group: Array = TEventbus.CurrentEvent_CalledToGroup
	var Cap = FOwner.Blackboard.GetIndexedValue(C.eiResourceCap, Group, RParam.AsInteger(ResourceID))
	if BC.IsIntResource(RParam.AsInteger(ResourceID)):
		var iCurrentCap := RParam.AsInteger(Cap)
		if iCurrentCap >= 0:
			Eventbus().Write(C.eiResourceCap, [ResourceID, iCurrentCap + RParam.AsInteger(Amount)], Group)
			# fill new space with resource if amount is increase an should fill
			if RParam.AsInteger(Amount) > 0 and not RParam.AsBoolean(Empty):
				Eventbus().Trigger(C.eiResourceTransaction, [ResourceID, RParam.AsInteger(Amount)], Group)
	else:
		var sCurrentCap := RParam.AsSingle(Cap)
		if sCurrentCap >= 0:
			Eventbus().Write(C.eiResourceCap, [ResourceID, RParam.ToSingle(sCurrentCap + RParam.AsSingle(Amount))], Group)
			# fill new space with resource if amount is increase an should fill
			if RParam.AsSingle(Amount) > 0 and not RParam.AsBoolean(Empty):
				Eventbus().Trigger(C.eiResourceTransaction, [ResourceID, RParam.AsSingle(Amount)], Group)
	return true


## Sets the balance of the resource.
func OnSetResource(ResourceID, Amount) -> bool:
	FOwner.Blackboard.SetIndexedValue(C.eiResourceBalance, TEventbus.CurrentEvent_CalledToGroup, RParam.AsInteger(ResourceID), Amount)
	return true


## Sets the upper bound of the resource.
func OnSetResourceCap(ResourceID, Amount) -> bool:
	FOwner.Blackboard.SetIndexedValue(C.eiResourceCap, TEventbus.CurrentEvent_CalledToGroup, RParam.AsInteger(ResourceID), Amount)
	# refresh resource if cap has been reduced, this will cap it again, else it will do nothing
	OnTransact(ResourceID, RParam.RPARAMEMPTY)
	return true


## Saves the new cost.
func OnSetResourceCost(ResourceID, Amount) -> bool:
	FOwner.Blackboard.SetIndexedValue(C.eiResourceCost, TEventbus.CurrentEvent_CalledToGroup, RParam.AsInteger(ResourceID), Amount)
	return true


## Executes the transaction.
func OnTransact(ResourceID, Amount) -> bool:
	var Group: Array = TEventbus.CurrentEvent_CalledToGroup
	var Resource := RParam.AsInteger(ResourceID)
	var Balance = FOwner.Blackboard.GetIndexedValue(C.eiResourceBalance, Group, Resource)
	var Cap = FOwner.Blackboard.GetIndexedValue(C.eiResourceCap, Group, Resource)
	var UseCap: bool = Cap != null and not BC.IgnoresCap(Resource)
	if BC.IsIntResource(Resource):
		var iBalance := maxi(0, RParam.AsInteger(Balance) + RParam.AsInteger(Amount))
		if UseCap and RParam.AsInteger(Amount) >= 0:
			iBalance = mini(iBalance, RParam.AsInteger(Cap))
		Eventbus().Write(C.eiResourceBalance, [ResourceID, iBalance], Group)
	else:
		var sBalance := maxf(0.0, RParam.ToSingle(RParam.AsSingle(Balance) + RParam.AsSingle(Amount)))
		if UseCap and RParam.AsSingle(Amount) >= 0:
			sBalance = minf(sBalance, RParam.AsSingle(Cap))
		Eventbus().Write(C.eiResourceBalance, [ResourceID, sBalance], Group)
	return true


## Executes the negative transaction.
func OnTransactNegative(ResourceID, Amount) -> bool:
	if BC.IsIntResource(RParam.AsInteger(ResourceID)):
		return OnTransact(ResourceID, -RParam.AsInteger(Amount))
	return OnTransact(ResourceID, -RParam.AsSingle(Amount))

