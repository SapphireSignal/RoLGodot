class_name RTarget
extends RefCounted
## Port of RTarget (BaseConflict.Types.Target.pas:22, implementation :201): a wela's target, an entity, a spot on
## the ground or a build grid field. A record in the original: treat an RTarget as a value (Clone to change one).
## Port conventions: the original reads the per-process Game global inside GetTargetEntity / GetTargetPosition /
## GetBuildZone; here the caller passes its Game (components: GlobalEventbus().Game). The scripts never use
## targets. Create(x) folds the constructor overloads (TEntity, entity ID or Vector2).

const C = preload("res://src/runtime/dws/dws_const.gd")
const SPATIALEPSILON = 0.1  # BaseConflict.Constants.pas:31

var FTargetType: int = C.ttNone
var FTargetCoord := Vector2.ZERO
var FEntityID := 0
var FBuildGridID := 0
var FBuildZoneCoord := Vector2i.ZERO

var TargetType: int:
	get:
		return FTargetType
var BuildGridID: int:
	get:
		return FBuildGridID
var BuildGridCoordinate: Vector2i:
	get:
		return FBuildZoneCoord
var EntityID: int:
	get:
		return FEntityID


## Create(Target: TEntity) (null: empty), Create(TargetEntityID: int), Create(Target: Vector2).
static func Create(Target) -> RTarget:
	var Result := RTarget.new()
	if Target is Vector2:
		Result.FTargetType = C.ttCoordinate
		Result.FTargetCoord = Target
	elif Target is int:
		Result.FTargetType = C.ttEntity
		Result.FEntityID = Target
	elif Target != null:
		Result.FTargetType = C.ttEntity
		Result.FEntityID = Target.ID
	return Result


static func CreateBuildTarget(BuildGridID_: int, Coord: Vector2i) -> RTarget:
	var Result := RTarget.new()
	Result.FTargetType = C.ttBuild
	Result.FBuildGridID = BuildGridID_
	Result.FBuildZoneCoord = Coord
	return Result


static func CreateEmpty() -> RTarget:
	return RTarget.new()


func Clone() -> RTarget:
	var Result := RTarget.new()
	Result.FTargetType = FTargetType
	Result.FTargetCoord = FTargetCoord
	Result.FEntityID = FEntityID
	Result.FBuildGridID = FBuildGridID
	Result.FBuildZoneCoord = FBuildZoneCoord
	return Result


## class operator Equal: coordinates within SPATIALEPSILON on both axes count as equal.
func Equal(b: RTarget) -> bool:
	if TargetType != b.TargetType:
		return false
	match TargetType:
		C.ttCoordinate:
			return absf(FTargetCoord.x - b.FTargetCoord.x) < SPATIALEPSILON and absf(FTargetCoord.y - b.FTargetCoord.y) < SPATIALEPSILON
		C.ttEntity:
			return EntityID == b.EntityID
		C.ttBuild:
			return BuildGridID == b.BuildGridID and BuildGridCoordinate == b.BuildGridCoordinate
	return true


func IsEmpty() -> bool:
	return TargetType == C.ttNone


func IsBuildTarget() -> bool:
	return TargetType == C.ttBuild


func IsCoordinate() -> bool:
	return TargetType == C.ttCoordinate


func IsEntity() -> bool:
	return TargetType == C.ttEntity


func GetBuildZone(Game):
	return Game.Map.BuildZones.GetBuildZone(BuildGridID)


## The target entity if it exists, else null (also while the game shuts down).
func GetTargetEntity(Game):
	if IsEntity() and Game != null and not Game.IsShuttingDown:
		return Game.EntityManager.GetEntityByID(EntityID)
	return null


## An entity target's current position (remembered for when the entity is gone), a build field's centre.
func GetTargetPosition(Game) -> Vector2:
	if IsEntity():
		var TargetEntity = Game.EntityManager.TryGetEntityByID(EntityID) if Game != null else null
		if TargetEntity != null:
			FTargetCoord = TargetEntity.Position
	elif IsBuildTarget():
		FTargetCoord = Game.Map.BuildZones.GetBuildZone(BuildGridID).GetCenterOfField(BuildGridCoordinate)
	return FTargetCoord


func IsEntityValid(Game) -> bool:
	return GetTargetEntity(Game) != null


## TryGetTargetEntity(out Entity): the entity or null.
func TryGetTargetEntity(Game):
	return GetTargetEntity(Game)
