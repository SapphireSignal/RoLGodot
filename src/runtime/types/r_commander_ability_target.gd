class_name RCommanderAbilityTarget
extends RefCounted
## Port of RCommanderAbilityTarget and ACommanderAbilityTargetHelper (BaseConflict.Types.Target.pas:115, :151,
## implementation :360-509): a target a commander picked for an ability. A record in the original: treat it as a
## value. An ACommanderAbilityTarget is an Array of these; its helpers are the static functions below.
## Create(x) folds the constructor overloads (TEntity, entity ID or Vector2).

const C = preload("res://src/runtime/dws/dws_const.gd")

## COMMANDER_ABILITIES_WITHOUT_TARGET (:107)
const COMMANDER_ABILITIES_WITHOUT_TARGET = [C.ctNone, C.ctTargetLess, C.ctSelftarget]

var FCoord := Vector2.ZERO
var FEntityID := 0
var FGridID := 0
var FGridCoordinate := Vector2i.ZERO
var FIsSet := false
var FType: int = C.ctNone

var TargetType: int:
	get:
		return FType
var IsSet: bool:
	get:
		return FIsSet
var Coordinate: Vector2:
	get:
		return FCoord
var EntityID: int:
	get:
		return FEntityID


## Create(Target: Vector2), Create(Target: TEntity), Create(TargetEntity: int).
static func Create(Target) -> RCommanderAbilityTarget:
	var Result := RCommanderAbilityTarget.new()
	Result.FIsSet = true
	if Target is Vector2:
		Result.FCoord = Target
		Result.FType = C.ctCoordinate
	elif Target is int:
		Result.FEntityID = Target
		Result.FType = C.ctEntity
	else:
		Result.FEntityID = Target.ID
		Result.FType = C.ctEntity
	return Result


static func CreateBuildTarget(TargetBuildZone: int, TargetCoordinate: Vector2i) -> RCommanderAbilityTarget:
	var Result := RCommanderAbilityTarget.new()
	Result.FIsSet = true
	Result.FType = C.ctBuildZone
	Result.FGridID = TargetBuildZone
	Result.FGridCoordinate = TargetCoordinate
	return Result


static func CreateEmpty() -> RCommanderAbilityTarget:
	return CreateUnset(C.ctNone)


static func CreateSelftarget() -> RCommanderAbilityTarget:
	var Result := RCommanderAbilityTarget.new()
	Result.FIsSet = true
	Result.FType = C.ctSelftarget
	return Result


static func CreateTargetLess() -> RCommanderAbilityTarget:
	var Result := RCommanderAbilityTarget.new()
	Result.FIsSet = true
	Result.FType = C.ctTargetLess
	return Result


## A target not set yet (user interaction needed); targetless kinds are always set.
static func CreateUnset(CAType: int) -> RCommanderAbilityTarget:
	var Result := RCommanderAbilityTarget.new()
	Result.FIsSet = COMMANDER_ABILITIES_WITHOUT_TARGET.has(CAType)
	Result.FType = CAType
	return Result


func Clone() -> RCommanderAbilityTarget:
	var Result := RCommanderAbilityTarget.new()
	Result.FCoord = FCoord
	Result.FEntityID = FEntityID
	Result.FGridID = FGridID
	Result.FGridCoordinate = FGridCoordinate
	Result.FIsSet = FIsSet
	Result.FType = FType
	return Result


func GetWorldPosition(Game, Owner = null) -> Vector2:
	assert(IsCoordinateTarget() or IsEntityTarget() or IsBuildTarget())
	return ToRTarget(Owner).GetTargetPosition(Game)


func IsBuildTarget() -> bool:
	return FType == C.ctBuildZone


func IsCoordinateTarget() -> bool:
	return FType == C.ctCoordinate


func IsEmpty() -> bool:
	return FType == C.ctNone


func IsEntityTarget() -> bool:
	return FType == C.ctEntity


func IsSelftarget() -> bool:
	return FType == C.ctSelftarget


func IsTargetLess() -> bool:
	return FType == C.ctTargetLess


func ToRTarget(Owner) -> RTarget:
	if not FIsSet:
		return RTarget.CreateEmpty()
	match FType:
		C.ctNone, C.ctTargetLess:
			return RTarget.CreateEmpty()
		C.ctSelftarget:
			if Owner == null:
				push_error("RCommanderAbilityTarget.ToRTarget: Need Owner to resolve selftarget!")
				return RTarget.CreateEmpty()
			return RTarget.Create(Owner)
		C.ctCoordinate:
			return RTarget.Create(FCoord)
		C.ctEntity:
			return RTarget.Create(FEntityID)
		C.ctBuildZone:
			return RTarget.CreateBuildTarget(FGridID, FGridCoordinate)
	assert(false)
	return RTarget.CreateEmpty()


func Unset() -> void:
	FIsSet = false


## ACommanderAbilityTargetHelper.ToRTargets: an ATarget with one RTarget per ability target.
static func ToRTargets(Targets: Array, Owner) -> Array:
	var Result: Array = []
	for Item: RCommanderAbilityTarget in Targets:
		Result.append(Item.ToRTarget(Owner))
	return Result


## ACommanderAbilityTargetHelper.ToRParam: a copy of the Array (the targets are values).
static func ArrayToRParam(Targets: Array) -> Array:
	return Targets.duplicate()


## RParam.AsACommanderAbilityTarget: empty = [].
static func ArrayFromRParam(p) -> Array:
	return RParam.AsArray(p)
