class_name TAutoBrainOnUnitPropertyComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnUnitPropertyComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:744,
## implementation :2995), server only. At eiUnitPropertyChanged [ChangedUnitProperties, Removed] (epMiddle), when
## properties were added that meet TriggerOn and none of MustNotHave, and eiIsReady of its group allows, fires eiFire
## at the owner in its group (no CanThink check).

var FTriggerAtUnitProperties: Array = []
var FMustNotHave: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnUnitPropertyChanged", C.eiUnitPropertyChanged, C.epMiddle, C.etTrigger))


func OnUnitPropertyChanged(ChangedUnitProperties, Removed) -> bool:
	if not RParam.AsBoolean(Removed):
		var UnitProperties := RParam.AsSet(ChangedUnitProperties)
		if DSet.Intersects(FTriggerAtUnitProperties, UnitProperties) and \
			not DSet.Intersects(FMustNotHave, UnitProperties):
			if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)):
				Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Owner))], ComponentGroup)
	return true


func TriggerOn(UnitProperties: Array) -> TAutoBrainOnUnitPropertyComponent:
	FTriggerAtUnitProperties = DSet.Make(UnitProperties)
	return self


func MustNotHave(UnitProperties: Array) -> TAutoBrainOnUnitPropertyComponent:
	FMustNotHave = DSet.Make(UnitProperties)
	return self
