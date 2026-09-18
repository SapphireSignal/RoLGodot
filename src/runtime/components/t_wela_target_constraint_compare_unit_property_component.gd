class_name TWelaTargetConstraintCompareUnitPropertyComponent
extends TWelaTargetConstraintUnitPropertyComponent
## Port of TWelaTargetConstraintCompareUnitPropertyComponent (BaseConflict.EntityComponents.Shared.Wela.pas:469,
## implementation :3203). The unit property rules must hold for the owner and the target together: BothMustHave
## (both have all), BothMustHaveAny (a property both have), BothMustNotHave (neither has any), BothMustNotHaveAll
## (neither has all).


func IsPossible(Target: RTarget) -> bool:
	var TargetEntity = Target.GetTargetEntity(TargetGame())
	if TargetEntity == null:
		return false
	var UnitProperties: Array = TargetEntity.UnitProperties()
	var OwnUnitProperties: Array = Owner.UnitProperties()
	var Common: Array = []
	for p in OwnUnitProperties:
		if UnitProperties.has(p):
			Common.append(p)
	return (DSet.Difference(FMustList, UnitProperties).is_empty() and DSet.Difference(FMustList, OwnUnitProperties).is_empty()) \
		and (FMustAnyList.is_empty() or DSet.Intersects(FMustAnyList, Common)) \
		and (not DSet.Intersects(FMustNotList, UnitProperties) and not DSet.Intersects(FMustNotList, OwnUnitProperties)) \
		and (FMustNotAllList.is_empty() or (not DSet.Difference(FMustNotAllList, UnitProperties).is_empty()
				and not DSet.Difference(FMustNotAllList, OwnUnitProperties).is_empty()))


## All properties have to be present at owner and target.
func BothMustHave(Properties: Array) -> TWelaTargetConstraintCompareUnitPropertyComponent:
	MustHave(Properties)
	return self


## Any of these properties have to be present at owner and target.
func BothMustHaveAny(Properties: Array) -> TWelaTargetConstraintCompareUnitPropertyComponent:
	MustHaveAny(Properties)
	return self


## None of these properties must be present at owner and target.
func BothMustNotHave(Properties: Array) -> TWelaTargetConstraintCompareUnitPropertyComponent:
	MustNotHave(Properties)
	return self


## These properties together must not be present at owner and target.
func BothMustNotHaveAll(Properties: Array) -> TWelaTargetConstraintCompareUnitPropertyComponent:
	MustNotHaveAll(Properties)
	return self
