class_name TServerEntityManagerComponent
extends TEntityManagerComponent
## Port of TServerEntityManagerComponent (GameServer/BaseConflict.EntityComponents.Server.pas:358, implementation
## :1817): the server's entity manager, on the game entity (Game.EntityManager and Game.ServerEntityManager).
## eiDelayedKillEntity kills at the next Idle (eiKillEntity; the entity is freed one Idle later); SpawnUnit builds,
## sets up, sends and deploys new entities.
## Port notes: the original reads the ServerGame / Game globals; here GlobalEventbus().Game. Game.Map.ClampToZone
## and Game.Statistics are used when the game has them; eiLose calls Game.TeamLost when the game has it (the server
## game comes in phase 3). The sandbox overwatch switches (the globals Overwatch / OverwatchClearable, set from the
## game) are read as Game.Overwatch / Game.OverwatchClearable when Game.IsSandbox. The Delphi overloads fold into one
## SpawnUnit: SpawnUnit(PositionX, PositionY, PatternFileName, TeamID) (the scripts) or SpawnUnit(Position: Vector2,
## Front, PatternFileName, League, Level, TeamID, OwnerCommanderID = -1, Creator = null, Callback, PreProcessing,
## PostProcessing, CreateMethod); callbacks are Callable(Entity), empty = nil. CreateMethod is unused, as in the
## original. Where the original raised or asserted, push_error and return null.

const BC = preload("res://src/runtime/base_conflict_constants.gd")
const INHERIT_FROM_GAME = -1

var FEntitiesToKill: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnDelayedKillEntity", C.eiDelayedKillEntity, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnLose", C.eiLose, C.epLast, C.etTrigger, C.esGlobal))


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FEntitiesToKill = []
	return self


func Destroy() -> void:
	super()
	FEntitiesToKill = []


## Add entity to kill-on-next-frame-list.
func OnDelayedKillEntity(EntityID) -> bool:
	FEntitiesToKill.append(RParam.AsInteger(EntityID))
	return true


## Kills the queued entities; kills queued while this runs wait for the next frame. Fixed bug of the original: its
## Clear after the loop dropped them, so those entities never died (docs/original-bugs.md).
func Idle() -> void:
	super()
	var ToKill := FEntitiesToKill
	FEntitiesToKill = []
	for EntityID in ToKill:
		GlobalEventbus().Trigger(C.eiKillEntity, [EntityID])


## Initiates the defeat of the team.
func OnLose(TeamID) -> bool:
	var Game = GlobalEventbus().Game
	if Game != null and Game.has_method("TeamLost"):
		Game.TeamLost(RParam.AsInteger(TeamID))
	return true


func _Game():
	return GlobalEventbus().Game


## SpawnSpawner(BuildGridID, BuildGridCoordinate, PatternFileName, TeamID, OwnerCommanderID, Creator, Callback,
## PreProcessing = empty, CreateMethod = ""): spawns the unit on the build field (a 1x1 unit, front of the zone),
## writes eiBuildgridOwner in its setup, blocks the field and saves it in eiBuildgridBlockedFields (an Array of
## [BuildZoneID, Vector2i]).
func SpawnSpawner(BuildGridID: int, BuildGridCoordinate: Vector2i, PatternFileName: String, TeamID: int, OwnerCommanderID: int, Creator, Callback := Callable(), PreProcessing := Callable(), CreateMethod := ""):
	var Game = _Game()
	var BuildZone: TBuildZone = Game.Map.BuildZones.TryGetBuildZone(BuildGridID)
	if BuildZone == null:
		push_error("TServerEntityManagerComponent.SpawnSpawner: Invalid buildgrid id!")
		return null
	var BuildTarget := RTarget.CreateBuildTarget(BuildGridID, BuildGridCoordinate)
	var NeededGridSize := Vector2i(1, 1)
	var Position := BuildTarget.GetRealBuildPosition(Game, NeededGridSize)
	var Front := BuildZone.Front
	var ZoneID := BuildZone.ID
	var Setup := func(SpawnedEntity: TEntity) -> void:
		if Callback.is_valid():
			Callback.call(SpawnedEntity)
		# save target buildgrid, must be in setup, as the spawner can spawn directly after create
		SpawnedEntity.Eventbus.Write(C.eiBuildgridOwner, [ZoneID])
	var Result = SpawnUnit(Position, Front, PatternFileName, INHERIT_FROM_GAME, INHERIT_FROM_GAME, TeamID,
		OwnerCommanderID, Creator, Setup, PreProcessing, Callable(), CreateMethod)
	if Result == null:
		return null
	# block gridfields
	var BlockedFieldGrids: Array = []
	for i in NeededGridSize.x * NeededGridSize.y:
		BlockedFieldGrids.append([0, Vector2i.ZERO])
	var j := 0
	for x in NeededGridSize.x:
		for y in NeededGridSize.y:
			# assume non overlapping buildgrids, look for buildgrid at target coordinate and block the field there
			Position = BuildZone.GetCenterOfField(BuildTarget.BuildGridCoordinate + Vector2i(x, y))
			BuildZone = Game.Map.BuildZones.GetBuildZoneByPosition(Position)
			if BuildZone == null:
				# the original asserted, then crashed on the next field
				push_error("TServerEntityManagerComponent.SpawnSpawner: Invalid buildcoordinate passed to Server!")
				break
			BlockedFieldGrids[j] = [BuildZone.ID, BuildZone.PositionToCoord(Position)]
			GlobalEventbus().Write(C.eiSetGridFieldBlocking, [BlockedFieldGrids[j][0], BlockedFieldGrids[j][1], Result.ID])
			j += 1
		if BuildZone == null:
			break
	# save blocked gridfields, for refunding
	Result.Eventbus.Write(C.eiBuildgridBlockedFields, [BlockedFieldGrids])
	return Result


## Creates a new entity of the given scriptfile (relative to the script path, e.g. 'Units\Archer'): team, position,
## front, owning commander, creator and card league / level (INHERIT_FROM_GAME: the game's league, MAX_LEVEL) are
## set before the script's CreateEntity runs further (in its initializer, then PreProcessing). Then it gets its ID,
## Callback runs, eiAfterCreate, eiSendEntities (to the clients), Deploy, PostProcessing.
## Script form: SpawnUnit(PositionX, PositionY, PatternFileName, TeamID) spawns facing (0, 1) for no commander.
func SpawnUnit(Position, Front, PatternFileName = "", League = INHERIT_FROM_GAME, Level = INHERIT_FROM_GAME, TeamID = 0, OwnerCommanderID = -1, Creator = null, Callback := Callable(), PreProcessing := Callable(), PostProcessing := Callable(), _CreateMethod := ""):
	if not Position is Vector2:
		# SpawnUnit(PositionX, PositionY, PatternFileName, TeamID)
		return SpawnUnit(Vector2(Position, Front), Vector2(0, 1), PatternFileName, INHERIT_FROM_GAME, INHERIT_FROM_GAME,
			League, -1, null)
	var Game = _Game()
	if PatternFileName == "":
		push_error("TServerEntityManagerComponent.SpawnUnit: Empty script pattern for creating entity created by unit \"%s\""
			% (Creator.ScriptFile if Creator != null else ""))
		return null

	if League == INHERIT_FROM_GAME:
		League = Game.League()
	if Level == INHERIT_FROM_GAME:
		Level = BC.MAX_LEVEL

	if Game != null and not PatternFileName.contains(BC.FILE_IDENTIFIER_SPAWNER):
		Position = Game.Map.ClampToZone(C.ZONE_WALK, Position)

	var Statistics = Game.get("Statistics") if Game != null else null
	if Statistics != null:
		Statistics.UnitSpawned(OwnerCommanderID, PatternFileName)

	var FinalPosition: Vector2 = Position
	var Setup := func(Entity: TEntity) -> void:
		Entity.Eventbus.Write(C.eiTeamID, [TeamID])
		Entity.Position = FinalPosition
		Entity.Front = Front
		if OwnerCommanderID >= 0:
			Entity.Eventbus.Write(C.eiOwnerCommander, [OwnerCommanderID])
		if Creator != null:
			Entity.Eventbus.Write(C.eiCreator, [Creator.ID])
			Entity.Eventbus.Write(C.eiCreatorScriptFileName, [Creator.ScriptFileName()])
		Entity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLeague, League)
		Entity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLevel, Level)
		if PreProcessing.is_valid():
			PreProcessing.call(Entity)
	var Entity := TEntity.CreateFromScript(PatternFileName, GlobalEventbus(), Setup)
	if Entity == null:
		return null
	Entity.ID = Game.EntityManager.GenerateUniqueID()

	if Callback.is_valid():
		Callback.call(Entity)

	if Game.IsSandbox() and Game.get("Overwatch"):
		if Game.get("OverwatchClearable"):
			TBrainOverwatchSandboxComponent.new().Create(Entity)
		else:
			TBrainOverwatchComponent.new().Create(Entity)

	Entity.Eventbus.Trigger(C.eiAfterCreate, [])
	# send new entity to client
	GlobalEventbus().Trigger(C.eiSendEntities, [[Entity]])
	# deploy after send, as the unit has to be on the client for triggered effects
	Entity.Deploy()

	if PostProcessing.is_valid():
		PostProcessing.call(Entity)
	return Entity


## SpawnUnitWithFront(PositionX, PositionY, FrontX, FrontY, PatternFileName, TeamID)
func SpawnUnitWithFront(PositionX: float, PositionY: float, FrontX: float, FrontY: float, PatternFileName: String, TeamID: int):
	return SpawnUnit(Vector2(PositionX, PositionY), Vector2(FrontX, FrontY), PatternFileName, INHERIT_FROM_GAME,
		INHERIT_FROM_GAME, TeamID, -1, null)


## Spawns facing (-1, 0) and frees GROUP_BUILDING_LIFETIME before eiAfterCreate.
func SpawnUnitWithoutLimitedLifetime(PositionX: float, PositionY: float, PatternFileName: String, TeamID: int):
	return SpawnUnitWithoutLimitedLifetimeWithFront(PositionX, PositionY, -1, 0, PatternFileName, TeamID)


func SpawnUnitWithoutLimitedLifetimeWithFront(PositionX: float, PositionY: float, FrontX: float, FrontY: float, PatternFileName: String, TeamID: int):
	return SpawnUnit(Vector2(PositionX, PositionY), Vector2(FrontX, FrontY), PatternFileName, INHERIT_FROM_GAME,
		INHERIT_FROM_GAME, TeamID, -1, null,
		func(Entity: TEntity) -> void: Entity.FreeGroups([C.GROUP_BUILDING_LIFETIME]))


## SpawnUnitWithOverwatch(Position, Front, PatternFileName, TeamID) or
## SpawnUnitWithOverwatch(PositionX, PositionY, FrontX, FrontY, PatternFileName, TeamID): adds an overwatch brain.
func SpawnUnitWithOverwatch(Position, Front, PatternFileName, TeamID, A5 = null, A6 = null):
	if not Position is Vector2:
		# (PositionX, PositionY, FrontX, FrontY, PatternFileName, TeamID)
		return SpawnUnitWithOverwatch(Vector2(Position, Front), Vector2(PatternFileName, TeamID), A5, A6)
	return SpawnUnit(Position, Front, PatternFileName, INHERIT_FROM_GAME, INHERIT_FROM_GAME, TeamID, -1, null,
		func(Entity: TEntity) -> void: TBrainOverwatchComponent.new().Create(Entity))


## SpawnUnitWithOverwatchAndFlee(Position, Front, PatternFileName, TeamID, FleeDistance) or
## SpawnUnitWithOverwatchAndFlee(PositionX, PositionY, FrontX, FrontY, PatternFileName, TeamID, FleeDistance).
func SpawnUnitWithOverwatchAndFlee(Position, Front, PatternFileName, TeamID, FleeDistance, A5 = null, A6 = null):
	if not Position is Vector2:
		# (PositionX, PositionY, FrontX, FrontY, PatternFileName, TeamID, FleeDistance)
		return SpawnUnitWithOverwatchAndFlee(Vector2(Position, Front), Vector2(PatternFileName, TeamID), FleeDistance, A5, A6)
	var Setup := func(Entity: TEntity) -> void:
		TBrainOverwatchComponent.new().Create(Entity)
		TBrainFleeComponent.new().Create(Entity).Range(FleeDistance)
	return SpawnUnit(Position, Front, PatternFileName, INHERIT_FROM_GAME, INHERIT_FROM_GAME, TeamID, -1, null, Setup)


## Creates the entity without any setup but Callback (Callable(Entity)), then eiAfterCreate, send, Deploy.
func SpawnUnitRaw(PatternFileName: String, Callback: Callable):
	var Entity := TEntity.CreateFromScript(PatternFileName, GlobalEventbus())
	if Entity == null:
		return null
	Entity.ID = _Game().EntityManager.GenerateUniqueID()
	Callback.call(Entity)
	Entity.Eventbus.Trigger(C.eiAfterCreate, [])
	# send new entity to client
	GlobalEventbus().Trigger(C.eiSendEntities, [[Entity]])
	# deploy after send, as the unit has to be on the client for triggered effects
	Entity.Deploy()
	return Entity
