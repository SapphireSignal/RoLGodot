class_name TWelaTargetConstraintWelaPropertyComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintWelaPropertyComponent (BaseConflict.EntityComponents.Shared.Wela.pas:486,
## implementation :1573). Only entities whose eiDamageType in CheckGroup (default: the main weapon) has all
## MustHave and none of MustNotHave types. Non-entity (or gone) targets are possible.

var FCheckGroup: Array = []
var FMustHave: Array = []
var FMustNotHave: Array = []


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FCheckGroup = [C.GROUP_MAINWEAPON]
	return self


func IsPossible(Target: RTarget) -> bool:
	var TargetEntity = Target.GetTargetEntity(TargetGame())
	if TargetEntity == null:
		return true
	var DamageTypes := RParam.AsSet(TargetEntity.Eventbus.Read(C.eiDamageType, [], FCheckGroup))
	return not DSet.Intersects(FMustNotHave, DamageTypes) and DSet.Difference(FMustHave, DamageTypes).is_empty()


func MustHave(Types: Array) -> TWelaTargetConstraintWelaPropertyComponent:
	FMustHave = DSet.Make(Types)
	return self


func MustNotHave(Types: Array) -> TWelaTargetConstraintWelaPropertyComponent:
	FMustNotHave = DSet.Make(Types)
	return self


func CheckGroup(Group: Array) -> TWelaTargetConstraintWelaPropertyComponent:
	FCheckGroup = DSet.Make(Group)
	return self
