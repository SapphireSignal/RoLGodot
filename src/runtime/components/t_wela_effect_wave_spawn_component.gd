class_name TWelaEffectWaveSpawnComponent
extends TWelaEffectComponent
## Port of TWelaEffectWaveSpawnComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.Special.pas:58,
## implementation :95), server only. Triggers the wave spawns in a random order, making sure each build grid field
## spawns once per cycle. At eiAfterCreate (epLast) every build zone of the game gets a TSpawnrotation (tutorial
## games: the fixed tutorial order). On fire, for every zone: the global eiWaveSpawn [ZoneID, next field of the
## rotation] (SpawnAllTogether: all 20 fields, corners left out, x then y).
## It also filters every global eiWaveSpawn (epFirst, before the spawners): a zone with a rotation lets it through
## (true) only for a field still in the current cycle or the one spawned last (then used: taken out of the cycle,
## an empty cycle refills first); every other wave spawn is stopped (false), also those of zones without rotation
## and all of them with SpawnAllTogether. SpawnAllTogether and SpawnInOrder are unused by the scripts.
## Port: FSpawnRotations is a DelphiDictionary (the zones in the original's hash order) keyed by the zone ID with
## the identity hash, Delphi 10.1's integer hash as far as known (unverified: the snapshot has no RTL; Delphi 13
## hashes integers with FNV-1a). For the scenario zone IDs 0-3 this is ascending order. Delphi's Random (the
## random field of the cycle) is Godot's RNG.

const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FSpawnAllTogether := false
var FSpawnInOrder := false
var FSpawnRotations: DelphiDictionary


## TSpawnrotation (:37): one build zone's cycle of fields.
class TSpawnrotation:
	extends RefCounted
	const FIXED_TUTORIAL_ROTATION = [6, 19, 13, 11, 10, 9, 17, 14, 0, 16, 15, 7, 8, 2, 3, 1, 18, 12, 4, 5]

	var FSpawnCount := 0
	var FSpawnInOrder := false
	var FUseFixedRotation := false
	var FCurrentRotation: Array = []  # of Vector2i
	var FLastSpawnedCoordinate := Vector2i(-1, -1)

	func Create(SpawnInOrder: bool, UseFixedTutorialRotation: bool) -> TSpawnrotation:
		FSpawnInOrder = SpawnInOrder
		FCurrentRotation = []
		FLastSpawnedCoordinate = Vector2i(-1, -1)
		if UseFixedTutorialRotation:
			FUseFixedRotation = true
			FSpawnInOrder = true
		Fill()
		return self

	## A new cycle: every field but the four corners, x then y (tutorial: in the fixed order).
	func Fill() -> void:
		FCurrentRotation.clear()
		for x in BC.BUILDGRID_SIZE.x:
			for y in BC.BUILDGRID_SIZE.y:
				if not (x == 0 and y == 0) and not (x == 0 and y == BC.BUILDGRID_SIZE.y - 1) \
						and not (x == BC.BUILDGRID_SIZE.x - 1 and y == 0) \
						and not (x == BC.BUILDGRID_SIZE.x - 1 and y == BC.BUILDGRID_SIZE.y - 1):
					FCurrentRotation.append(Vector2i(x, y))
		if FUseFixedRotation:
			var temp: Array = []
			for i in FIXED_TUTORIAL_ROTATION.size():
				temp.append(FCurrentRotation[FIXED_TUTORIAL_ROTATION[i]])
			FCurrentRotation = temp

	func CheckEmptyAndFill() -> void:
		if FCurrentRotation.is_empty():
			Fill()

	func IsActive(Coordinate: Vector2i) -> bool:
		return Coordinate == FLastSpawnedCoordinate or FCurrentRotation.has(Coordinate)

	func NextInRotation() -> Vector2i:
		CheckEmptyAndFill()
		if FSpawnInOrder:
			return FCurrentRotation[0]
		return FCurrentRotation[randi_range(0, FCurrentRotation.size() - 1)]

	func UseField(Coordinate: Vector2i) -> void:
		FSpawnCount += 1
		FLastSpawnedCoordinate = Coordinate
		var i := FCurrentRotation.find(Coordinate)
		if i >= 0:
			FCurrentRotation.remove_at(i)


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FSpawnRotations = DelphiDictionary.new().Create(func(Key: int) -> int: return Key,
		func(Left: int, Right: int) -> bool: return Left == Right)
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnWaveSpawn", C.eiWaveSpawn, C.epFirst, C.etTrigger, C.esGlobal))


func Destroy() -> void:
	FSpawnRotations = null
	super()


func OnAfterCreate() -> bool:
	var Game = GlobalEventbus().Game
	if Game != null:
		for ZoneID in Game.Map.BuildZones.BuildZones.keys():
			FSpawnRotations.Add(ZoneID, TSpawnrotation.new().Create(FSpawnInOrder, Game.GameInformation.IsTutorial))
	return true


func Fire(_Targets: Array) -> void:
	for ZoneID in FSpawnRotations.Keys():
		if FSpawnAllTogether:
			for x in BC.BUILDGRID_SIZE.x:
				for y in BC.BUILDGRID_SIZE.y:
					if not (x == 0 and y == 0) and not (x == 0 and y == BC.BUILDGRID_SIZE.y - 1) \
							and not (x == BC.BUILDGRID_SIZE.x - 1 and y == 0) \
							and not (x == BC.BUILDGRID_SIZE.x - 1 and y == BC.BUILDGRID_SIZE.y - 1):
						GlobalEventbus().Trigger(C.eiWaveSpawn, [ZoneID, Vector2i(x, y)])
		else:
			var Target: Vector2i = FSpawnRotations.GetItem(ZoneID).NextInRotation()
			GlobalEventbus().Trigger(C.eiWaveSpawn, [ZoneID, Target])


func OnWaveSpawn(GridID, Coordinate) -> bool:
	var Result := false
	var ID := RParam.AsInteger(GridID)
	if not FSpawnAllTogether and FSpawnRotations.ContainsKey(ID):
		var Spawnrotation: TSpawnrotation = FSpawnRotations.GetItem(ID)
		Spawnrotation.CheckEmptyAndFill()
		if Spawnrotation.IsActive(RParam.AsIntVector2(Coordinate)):
			Result = true
			Spawnrotation.UseField(RParam.AsIntVector2(Coordinate))
	return Result


func SpawnAllTogether() -> TWelaEffectWaveSpawnComponent:
	FSpawnAllTogether = true
	return self


func SpawnInOrder() -> TWelaEffectWaveSpawnComponent:
	FSpawnInOrder = true
	return self
