class_name TWelaHelperBeaconComponent
extends TEntityComponent
## Port of TWelaHelperBeaconComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:781,
## implementation :2928), server only. Marks its group for searches: eiWelaSearch read [SetUnitProperty] adds its
## component group to the result if the searched properties meet its TriggerAt properties.

var FUnitProperties: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWelaSearch", C.eiWelaSearch, C.epFirst, C.etRead))


func OnWelaSearch(Properties, Previous):
	if DSet.Intersects(RParam.AsSet(Properties), FUnitProperties):
		return DSet.Union(RParam.AsSet(Previous), ComponentGroup)
	return Previous


func TriggerAt(Properties = []) -> TWelaHelperBeaconComponent:
	FUnitProperties = DSet.Make(Properties)
	return self
