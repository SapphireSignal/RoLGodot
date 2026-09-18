class_name TWelaReadyEventCompareComponent
extends TWelaReadyComponent
## Port of TWelaReadyEventCompareComponent (BaseConflict.EntityComponents.Shared.Wela.pas:747, implementation
## :3145). Ready while the value of ComparedEvent read in CheckingGroup (default: own group), as a single, passes
## the comparison with ReferenceValue.

var FComparator: int = C.coLowerEqual
var FComparedEvent := 0
var FReferenceValue := 0.0
var FCheckingGroup: Array = []


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FCheckingGroup = ComponentGroup
	return self


func IsReady() -> bool:
	var Amount = Eventbus().Read(FComparedEvent, [], FCheckingGroup)
	return BC.ResourceCompare(C.reFloat, Amount, FComparator, FReferenceValue)


func ComparedEvent(EventIdentifier: int) -> TWelaReadyEventCompareComponent:
	FComparedEvent = EventIdentifier
	return self


func SetComparator(Comparator: int) -> TWelaReadyEventCompareComponent:
	FComparator = Comparator
	return self


func ReferenceValue(ReferenceValue_: float) -> TWelaReadyEventCompareComponent:
	FReferenceValue = RParam.ToSingle(ReferenceValue_)
	return self


## The group where the resources are checked. Default is the component group.
func CheckingGroup(Group: Array) -> TWelaReadyEventCompareComponent:
	FCheckingGroup = DSet.Make(Group)
	return self
