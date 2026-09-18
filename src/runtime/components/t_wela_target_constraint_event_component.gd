class_name TWelaTargetConstraintEventComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintEventComponent (BaseConflict.EntityComponents.Shared.Wela.pas:501, implementation
## :1487). Only entities where the boolean event (e.g. eiDamageable) reads true.

var FEvent := 0


func CreateGrouped(Owner = null, Group = [], Event: int = 0) -> TEntityComponent:
	super(Owner, Group)
	FEvent = Event
	return self


func IsPossible(Target: RTarget) -> bool:
	var TargetEntity = Target.GetTargetEntity(TargetGame())
	if TargetEntity == null:
		return false
	return RParam.AsBoolean(TargetEntity.Eventbus.Read(FEvent, []))
