class_name TWelaTargetConstraintUnitPropertyComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintUnitPropertyComponent (BaseConflict.EntityComponents.Shared.Wela.pas:455,
## implementation :1404). Only entities with all MustHave properties, any of MustHaveAny, none of MustNotHave and
## not all of MustNotHaveAll.

var FMustNotList: Array = []
var FMustList: Array = []
var FMustNotAllList: Array = []
var FMustAnyList: Array = []


func IsPossible(Target: RTarget) -> bool:
	var TargetEntity = Target.GetTargetEntity(TargetGame())
	if TargetEntity == null:
		return false
	var UnitProperties: Array = TargetEntity.UnitProperties()
	return DSet.Difference(FMustList, UnitProperties).is_empty() \
		and (FMustAnyList.is_empty() or DSet.Intersects(FMustAnyList, UnitProperties)) \
		and not DSet.Intersects(FMustNotList, UnitProperties) \
		and (FMustNotAllList.is_empty() or not DSet.Difference(FMustNotAllList, UnitProperties).is_empty())


func MustHave(Properties: Array) -> TWelaTargetConstraintUnitPropertyComponent:
	FMustList = DSet.Make(Properties)
	return self


func MustHaveAny(Properties: Array) -> TWelaTargetConstraintUnitPropertyComponent:
	FMustAnyList = DSet.Make(Properties)
	return self


func MustNotHave(Properties: Array) -> TWelaTargetConstraintUnitPropertyComponent:
	FMustNotList = DSet.Make(Properties)
	return self


func MustNotHaveAll(Properties: Array) -> TWelaTargetConstraintUnitPropertyComponent:
	FMustNotAllList = DSet.Make(Properties)
	return self
