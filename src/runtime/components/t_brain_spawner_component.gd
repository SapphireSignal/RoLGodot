class_name TBrainSpawnerComponent
extends TBrainComponent
## Port of TBrainSpawnerComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.Special.pas:50,
## implementation :161), server only. Handles a spawner: on the global eiWaveSpawn [GridID, Coordinate] for its
## build grid (eiBuildgridOwner) and field (the first of eiBuildgridBlockedFields, else (-1, -1)) it fires eiFire in
## its group at the build zone's spawn target (ApplyGridOffset: offset like the field sits in the grid,
## ApplyRandomOffset: a random ±1 per axis; both turned into the spawn target's base). Unless FireNotInitially it
## asks for a wave of its own (global eiWaveSpawn) at eiGameStart, or at eiDeploy once the game has started.
## Port: without its build zone it fires at its owner (the original asserted first; release build: silent).

const L = preload("res://src/runtime/dws/dws_lib.gd")

var FFireNotInitially := false
var FApplyGridOffset := false
var FApplyRandomOffset := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGameStart", C.eiGameStart, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnWaveSpawn", C.eiWaveSpawn, C.epMiddle, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnDeploy", C.eiDeploy, C.epLast, C.etTrigger))


func BuildGridID() -> int:
	return RParam.AsIntegerDefault(Eventbus().Read(C.eiBuildgridOwner, []), -1)


func OccupiedField() -> Vector2i:
	var OccupiedFields := RParam.AsArray(Eventbus().Read(C.eiBuildgridBlockedFields, []))
	if OccupiedFields.size() > 0:
		return OccupiedFields[0][1]
	return Vector2i(-1, -1)


func OnDeploy() -> bool:
	var Game = BrainGame()
	if not FFireNotInitially and IsWelaReady() and Game != null and Game.HasStarted():
		GlobalEventbus().Trigger(C.eiWaveSpawn, [BuildGridID(), OccupiedField()])
	return true


func OnGameStart() -> bool:
	if not FFireNotInitially and IsWelaReady():
		# if created before first wave spawn, spawn now at game start
		GlobalEventbus().Trigger(C.eiWaveSpawn, [BuildGridID(), OccupiedField()])
	return true


func OnWaveSpawn(GridID, Coordinate) -> bool:
	if not CanThink() or RParam.AsInteger(GridID) != BuildGridID():
		return true
	if IsWelaReady():
		if RParam.AsIntVector2(Coordinate) == OccupiedField():
			Spawn()
	return true


func Spawn() -> void:
	FFireNotInitially = false
	var Target: Array
	var BuildZone: TBuildZone = BrainGame().Map.BuildZones.TryGetBuildZone(BuildGridID())
	if BuildZone != null:
		var BuildzoneOffset := Vector2(0, 0)
		# apply random offset for spawn
		if FApplyRandomOffset:
			BuildzoneOffset = BuildzoneOffset + Vector2(L.Round(randf()) * 2 - 1, L.Round(randf()) * 2 - 1)
		if FApplyGridOffset:
			var Base := Matrix2x2Inverse(Transform2D(-BuildZone.Front, -BuildZone.Left, Vector2.ZERO))
			BuildzoneOffset = BuildzoneOffset + Base * (BuildZone.GetCenterOfField(OccupiedField()) - BuildZone.Center)
		# buildgrid to spawnbuildgrid
		BuildzoneOffset = BuildZone.SpawnTargetBase * BuildzoneOffset
		var TargetPos := BuildZone.SpawnTarget + BuildzoneOffset
		Target = ATarget.Make(RTarget.Create(TargetPos))
	else:
		Target = ATarget.Make(Owner)
	Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Target)], ComponentGroup)


## RMatrix2x2.Inverse (Engine/Engine.Math.pas:4479) as coded: it swaps the off-diagonal cells the wrong way round,
## so it returns the transpose of the inverse (for the spawner's rotation base: the base itself). A singular matrix
## comes back unchanged. Columns: x = (_11, _12), y = (_21, _22).
static func Matrix2x2Inverse(M: Transform2D) -> Transform2D:
	var Determinant := M.x.x * M.y.y - M.x.y * M.y.x
	if Determinant == 0:
		return M
	return Transform2D(Vector2(M.y.y / Determinant, -M.y.x / Determinant),
		Vector2(-M.x.y / Determinant, M.x.x / Determinant), Vector2.ZERO)


func ApplyRandomOffset() -> TBrainSpawnerComponent:
	FApplyRandomOffset = true
	return self


func ApplyGridOffset() -> TBrainSpawnerComponent:
	FApplyGridOffset = true
	return self


func FireNotInitially() -> TBrainSpawnerComponent:
	FFireNotInitially = true
	return self
