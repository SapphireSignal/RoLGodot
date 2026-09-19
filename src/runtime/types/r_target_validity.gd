class_name RTargetValidity
extends RefCounted
## Port of RTargetValidity (BaseConflict.Types.Target.pas:81, implementation :605): whether a list of targets is
## valid, each target and together. A record in the original: Clone before changing a value read from an RParam.
## By design (the original documents it): empty targets start invalid, and a target once invalid stays invalid.

const MAX_TARGETS = 256  # SizeOf(SetByte) * 8

## If cast from an empty RParam, IsInitialized is false (and IsValid true).
var IsInitialized := false
var TogetherValid := false
var TargetCount := 0
## Port: the indices missing from SingleValidityMask (the original starts with [0..255] and excludes).
var FInvalid := {}


## Creates a template with everything valid for these targets (empty targets invalid).
static func Create(Targets: Array) -> RTargetValidity:
	var Result := RTargetValidity.new()
	if Targets.size() > MAX_TARGETS:
		push_error("RTargetValidity.Create: Maximal %d targets are allowed for welas, atm!." % MAX_TARGETS)
	Result.TogetherValid = true
	Result.IsInitialized = true
	Result.TargetCount = Targets.size()
	for i in Result.TargetCount:
		if Targets[i].IsEmpty():
			Result.FInvalid[i] = true
	return Result


## RParam.AsRTargetValidity: a copy, or an uninitialized validity for an empty RParam.
static func FromRParam(p) -> RTargetValidity:
	if p is RTargetValidity:
		return p.Clone()
	return RTargetValidity.new()


func Clone() -> RTargetValidity:
	var Result := RTargetValidity.new()
	Result.IsInitialized = IsInitialized
	Result.TogetherValid = TogetherValid
	Result.TargetCount = TargetCount
	Result.FInvalid = FInvalid.duplicate()
	return Result


## Whether all targets and the combination of them are valid.
func IsValid() -> bool:
	if not IsInitialized:
		return true
	var Result := TogetherValid
	for i in TargetCount:
		Result = Result and not FInvalid.has(i)
	return Result


## Sets a single validity. A target that was invalid stays invalid even after a valid check.
func SetValidity(Index: int, Value: bool) -> void:
	if Index < MAX_TARGETS:
		if not FInvalid.has(Index) and not Value:
			FInvalid[Index] = true
	else:
		push_error("RTargetValidity.SetValidity: Target has been validated, but isnt't present in structure!")


## Sets the combinatorial validity. If some component made this invalid before, it will stay invalid.
func SetTogetherValid(Value: bool) -> void:
	TogetherValid = TogetherValid and Value
