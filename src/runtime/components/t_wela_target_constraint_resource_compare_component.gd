class_name TWelaTargetConstraintResourceCompareComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintResourceCompareComponent (BaseConflict.EntityComponents.Shared.Wela.pas:315,
## implementation :1708). Only entity targets where the owner's resource (in its group) compared with the target's
## (times TargetFactor, default 1) passes. Balances, or caps (ComparesResourceCap); several resources are added.

var FCompareCap := false
var FComparator: int = C.coLowerEqual
var FComparedResource: int = C.reNone
var FAdditionalComparedResource: Array = []
var FTargetFactor := 1.0


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FTargetFactor = 1.0
	return self


func _Value(Entity, Resource: int, Group):
	if FCompareCap:
		return Entity.Cap(Resource, Group)
	return Entity.Balance(Resource, Group)


func IsPossible(Target: RTarget) -> bool:
	var TargetEntity = Target.TryGetTargetEntity(TargetGame())
	if TargetEntity == null:
		return false
	var OwnResource = _Value(Owner, FComparedResource, ComponentGroup)
	var TargetResource = _Value(TargetEntity, FComparedResource, null)
	for Res in FAdditionalComparedResource:
		OwnResource = BC.ResourceAdd(FComparedResource, OwnResource, _Value(Owner, Res, ComponentGroup))
		TargetResource = BC.ResourceAdd(FComparedResource, TargetResource, _Value(TargetEntity, Res, null))
	return BC.ResourceCompareParam(FComparedResource, OwnResource, FComparator, TargetResource, FTargetFactor)


## If called multiple, resources are added together.
func ComparedResource(Resource: int) -> TWelaTargetConstraintResourceCompareComponent:
	if FComparedResource == C.reNone:
		FComparedResource = Resource
	else:
		# the original asserts that all resources are either integer or single (debug builds only)
		FAdditionalComparedResource.append(Resource)
	return self


func ComparesResourceCap() -> TWelaTargetConstraintResourceCompareComponent:
	FCompareCap = true
	return self


func SetComparator(Comparator: int) -> TWelaTargetConstraintResourceCompareComponent:
	FComparator = Comparator
	return self


func TargetFactor(Factor: float) -> TWelaTargetConstraintResourceCompareComponent:
	FTargetFactor = RParam.ToSingle(Factor)
	return self
