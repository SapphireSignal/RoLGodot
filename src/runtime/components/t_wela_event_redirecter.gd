class_name TWelaEventRedirecter
extends TGDEntityComponent
## Port of TWelaEventRedirecter (BaseConflict.EntityComponents.Shared.Wela.pas:832, implementation :2272).
## Some welas produce entities and need data from them: reads of eiResourceCost, eiWelaNeededGridSize, eiWelaDamage,
## eiWelaRange, eiWelaTargetCount, eiCooldown, eiColorIdentity (and eiCollisionRadius) that find nothing are answered
## from the data entity of the eiWelaUnitPattern in the group the read was called to (EntityDataCache, at the
## component's card league/level; ungrouped read there). If other data is saved in the blackboard this data is used
## instead of the redirected. CopyValue / CopyIndexedValue copy a value from that data entity once, at setup.


func _DeclareEvents(e: Array) -> void:
	super(e)
	for Event in [C.eiResourceCost, C.eiWelaNeededGridSize, C.eiWelaDamage, C.eiWelaRange, C.eiWelaTargetCount,
			C.eiCooldown, C.eiColorIdentity]:
		e.append(XEvent("OnRedirect", Event, C.epFirst, C.etRead))
	e.append(XEvent("OnCollisionRadius", C.eiCollisionRadius, C.epFirst, C.etRead))


func Cache() -> TEntityDataCache:
	return GlobalEventbus().EntityDataCache


func GetPattern(TargetGroup: Array) -> String:
	return RParam.AsString(Eventbus().Read(C.eiWelaUnitPattern, [], TargetGroup))


func Redirect(Event: int, Previous):
	var Result = Previous
	if RParam.IsEmpty(Previous):
		Result = Cache().Read(GetPattern(TEventbus.GetCurrentEvent_CalledToGroup()), CardLeague(), CardLevel(), Event)
	return Result


func OnRedirect(Previous):
	return Redirect(TEventbus.GetCurrentEvent_EventIdentifier(), Previous)


func OnCollisionRadius(Previous):
	if RParam.IsEmpty(Previous):
		var DataEntity := Cache().GetEntity(GetPattern(TEventbus.GetCurrentEvent_CalledToGroup()), CardLeague(), CardLevel())
		# port: the original crashes on a pattern without data entity; here the value stays empty
		return DataEntity.CollisionRadius if DataEntity != null else Previous
	return Previous


func CopyIndexedValue(Event: int, SourceGroup: Array, Resource: int, TargetGroup: Array) -> TWelaEventRedirecter:
	var Value = Cache().Read(GetPattern(ComponentGroup), CardLeague(), CardLevel(), Event, DSet.Make(SourceGroup), Resource)
	Owner.Blackboard.SetIndexedValue(Event, DSet.Make(TargetGroup), Resource, Value)
	return self


func CopyValue(Event: int, SourceGroup: Array, TargetGroup: Array) -> TWelaEventRedirecter:
	var Value = Cache().Read(GetPattern(ComponentGroup), CardLeague(), CardLevel(), Event, DSet.Make(SourceGroup))
	Owner.Blackboard.SetValue(Event, DSet.Make(TargetGroup), Value)
	return self
