class_name TWelaTargetConstraintResourceComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintResourceComponent (BaseConflict.EntityComponents.Shared.Wela.pas:281,
## implementation :2759). Only entity targets that have the resource (a balance, and a cap unless the balance is
## compared) and whose fill (balance / cap; or the balance, the cap, the missing cap - balance) passes the
## comparison with Reference.

var FCompareBalanceToReference := false
var FCompareCapToReference := false
var FCompareMissingToReference := false
var FReference := 0.0
var FComparator: int = C.coLowerEqual
var FComparedResource: int = C.reNone


func IsPossible(Target: RTarget) -> bool:
	var TargetEntity = Target.TryGetTargetEntity(TargetGame())
	if TargetEntity == null:
		return false
	var ComparedResource := FComparedResource
	var Balance = TargetEntity.Eventbus.Read(C.eiResourceBalance, [FComparedResource])
	var Cap = TargetEntity.Eventbus.Read(C.eiResourceCap, [FComparedResource])
	# if resource not present, the constraint can't be valid
	if RParam.IsEmpty(Balance) or (RParam.IsEmpty(Cap) and not FCompareBalanceToReference):
		return false
	var Value
	if FCompareBalanceToReference:
		Value = Balance
	elif FCompareCapToReference:
		Value = Cap
	elif FCompareMissingToReference:
		Value = BC.ResourceSubtract(FComparedResource, Cap, Balance)
	else:
		Value = BC.ResourcePercentage(FComparedResource, Balance, Cap)
		ComparedResource = C.reFloat
	return BC.ResourceCompare(ComparedResource, Value, FComparator, FReference)


func CheckResource(ResourceID: int) -> TWelaTargetConstraintResourceComponent:
	FComparedResource = ResourceID
	return self


## Checks Balance / Cap <Comparator> Reference.
func Comparator(Comparator_: int) -> TWelaTargetConstraintResourceComponent:
	FComparator = Comparator_
	return self


## Sets the reference for the comparison.
func Reference(Reference_: float) -> TWelaTargetConstraintResourceComponent:
	FReference = RParam.ToSingle(Reference_)
	return self


## Compares the missing balance to the cap to the reference.
func CompareMissingToReference() -> TWelaTargetConstraintResourceComponent:
	FCompareMissingToReference = true
	return self


## Compares the balance to the reference.
func CompareBalanceToReference() -> TWelaTargetConstraintResourceComponent:
	FCompareBalanceToReference = true
	return self


## Compares the cap to the reference.
func CompareCapToReference() -> TWelaTargetConstraintResourceComponent:
	FCompareCapToReference = true
	return self


## Shorthand for coLowerEqual and 0.
func CheckEmpty() -> TWelaTargetConstraintResourceComponent:
	Reference(0)
	Comparator(C.coLowerEqual)
	return self


## Shorthand for coGreater and 0.
func CheckNotEmpty() -> TWelaTargetConstraintResourceComponent:
	Reference(0)
	Comparator(C.coGreater)
	return self


## Shorthand for coGreaterEqual and 1.
func CheckFull() -> TWelaTargetConstraintResourceComponent:
	Reference(1)
	Comparator(C.coGreaterEqual)
	return self


## Shorthand for coLower and 1.
func CheckNotFull() -> TWelaTargetConstraintResourceComponent:
	Reference(1)
	Comparator(C.coLower)
	return self


## Shorthand for CompareCapToReference, coGreater and 0.
func CheckHasResource() -> TWelaTargetConstraintResourceComponent:
	CompareCapToReference()
	Reference(0)
	Comparator(C.coGreater)
	return self
