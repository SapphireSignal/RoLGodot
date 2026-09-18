class_name TWelaReadyResourceCompareComponent
extends TWelaReadyComponent
## Port of TWelaReadyResourceCompareComponent (BaseConflict.EntityComponents.Shared.Wela.pas:630, implementation
## :2113). Ready while the fill (balance / cap) of a resource in CheckingGroup (default []) passes the comparison
## with ReferenceValue, or the balance itself with ReferenceIsAbsolute. More ComparedResource calls add further
## resources to the first one's balance and cap. ChecksCommander checks the owning commander (none: ready).

var FCompareCap := false  # declared but never used in the original
var FChecksCommander := false
var FReferenceIsAbsolute := false
var FComparator: int = C.coLowerEqual
var FComparedResource: int = C.reNone
var FAdditionalComparedResource: Array = []
var FReferenceValue := 0.0
var FCheckingGroup: Array = []


func IsReady() -> bool:
	var CheckedEntity = Owner
	if FChecksCommander:
		var game = GlobalEventbus().Game
		CheckedEntity = game.EntityManager.GetOwningCommander(Owner) if game != null else null
	if CheckedEntity == null:
		return true
	var Balance = CheckedEntity.Balance(FComparedResource, FCheckingGroup)
	for Res in FAdditionalComparedResource:
		Balance = BC.ResourceAdd(FComparedResource, Balance, CheckedEntity.Balance(Res, FCheckingGroup))
	if FReferenceIsAbsolute:
		return BC.ResourceCompare(FComparedResource, Balance, FComparator, FReferenceValue)
	var Cap = CheckedEntity.Cap(FComparedResource, FCheckingGroup)
	for Res in FAdditionalComparedResource:
		Cap = BC.ResourceAdd(FComparedResource, Cap, CheckedEntity.Cap(Res, FCheckingGroup))
	return BC.ResourceCompare(C.reFloat, BC.ResourcePercentage(FComparedResource, Balance, Cap), FComparator, FReferenceValue)


func ComparedResource(Resource: int) -> TWelaReadyResourceCompareComponent:
	if FComparedResource == C.reNone:
		FComparedResource = Resource
	else:
		# the original asserts that all resources are either integer or single (debug builds only)
		FAdditionalComparedResource.append(Resource)
	return self


func SetComparator(Comparator: int) -> TWelaReadyResourceCompareComponent:
	FComparator = Comparator
	return self


func ReferenceValue(ReferenceValue_: float) -> TWelaReadyResourceCompareComponent:
	FReferenceValue = RParam.ToSingle(ReferenceValue_)
	return self


func ReferenceIsAbsolute() -> TWelaReadyResourceCompareComponent:
	FReferenceIsAbsolute = true
	return self


## Shorthand for coLowerEqual and 0.
func CheckEmpty() -> TWelaReadyResourceCompareComponent:
	SetComparator(C.coLowerEqual)
	ReferenceValue(0)
	return self


## Shorthand for coGreater and 0.
func CheckNotEmpty() -> TWelaReadyResourceCompareComponent:
	SetComparator(C.coGreater)
	ReferenceValue(0)
	return self


## Shorthand for coGreaterEqual and 1.
func CheckFull() -> TWelaReadyResourceCompareComponent:
	SetComparator(C.coGreaterEqual)
	ReferenceValue(1)
	return self


## Shorthand for coLower and 1.
func CheckNotFull() -> TWelaReadyResourceCompareComponent:
	SetComparator(C.coLower)
	ReferenceValue(1)
	return self


## The group where the resources are checked. Default is the public group [].
func CheckingGroup(Group: Array) -> TWelaReadyResourceCompareComponent:
	FCheckingGroup = DSet.Make(Group)
	return self


func ChecksCommander() -> TWelaReadyResourceCompareComponent:
	FChecksCommander = true
	return self
