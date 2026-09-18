class_name TServerGame
extends TGame
## Port of TServerGame (GameServer/BaseConflict.Game.Server.pas:93, implementation :766): the server's game. It
## makes the global bus (server side) and on the game entity the server entity manager (EntityManager and
## ServerEntityManager) and the server collision manager; it owns the statistics and the delayed event queue.
## Initialize applies the scenario, then creates one commander (Commander\CommanderTemplate) per slot with its
## team and cards, and a spectator commander; then the token mapping and surrender components, then eiAfterCreate on
## the game entity. Start fires eiGameCommencing (the warm-up). Idle: map, entity manager, the due delayed events,
## then eiIdle (unless finished). TeamLost ends the game (FFinished) with the other team as winner.
## Port notes: the original's globals ServerGame and GlobalEventbus are the game / its GlobalEventbus; Overwatch and
## OverwatchClearable (sandbox switches, globals copied by the game thread) and the GameServer form's Cheatmode live
## here. Bots (TPvPBotComponent) come with the AI (phase 8): a bot slot raises an error for now.
## BuildStatistics returns the RGameFinishedStatistics record as a Dictionary.

static var Cheatmode := false

var FFinished := false
var FWinnerTeamID := 0
var FSurrenderedTeamID := 0
var FCommanders: Array = []  # of TEntity
var FServerEntityManager: TServerEntityManagerComponent = null
var FGameStatistics: TGameStatisticManager = null
var FDelayedEvents: TIntPriorityQueue = null
var FScenarioDirector = null  # TScenarioDirectorComponent

var Overwatch := false
var OverwatchClearable := false

var Statistics: TGameStatisticManager:
	get:
		return FGameStatistics
var DelayedEvents: TIntPriorityQueue:
	get:
		return FDelayedEvents
	set(value):
		FDelayedEvents = value
var GameInformation: TServerGameInformation:
	get:
		return FGameInfo as TServerGameInformation
var ServerEntityManager: TServerEntityManagerComponent:
	get:
		return FServerEntityManager
var ScenarioDirector:
	get:
		return FScenarioDirector
	set(value):
		FScenarioDirector = value
## All commanders in this game.
var Commanders: Array:
	get:
		return FCommanders
var IsFinished: bool:
	get:
		return FFinished


func Create(GameInformation_ = null, _GlobalEventbus = null) -> TGame:
	FGameStatistics = TGameStatisticManager.new().Create()
	var Bus := TEventbus.new().Create(null)
	Bus.ApplicationType = C.nsServer
	FDelayedEvents = TIntPriorityQueue.new()
	super(GameInformation_, Bus)
	FCommanders = []
	FServerEntityManager = TServerEntityManagerComponent.new().Create(GameEntity)
	FEntityManager = FServerEntityManager
	CollisionManager = TServerCollisionManagerComponent.new().Create(GameEntity)
	return self


func Destroy() -> void:
	FCommanders = []
	FServerEntityManager = null
	FScenarioDirector = null
	var Bus := FGlobalEventbus
	super()
	Bus.Free()
	FDelayedEvents = null
	FGameStatistics.Free()


func BuildStatistics() -> Dictionary:
	var Result := FGameStatistics.BuildStatistics(FGlobalEventbus)
	Result["winner_team_id"] = FWinnerTeamID
	return Result


## All commanders of a team.
func GetCommandersPerTeam(TeamID: int) -> Array:
	return FCommanders.filter(func(Entity: TEntity) -> bool: return Entity.TeamID() == TeamID)


## The highest team ID of the commanders (the first commander of it).
func GetTeamCount() -> int:
	if FCommanders.is_empty():
		return 0
	var Result: int = FCommanders[0].TeamID()
	for i in range(1, FCommanders.size()):
		if FCommanders[i].TeamID() > Result:
			Result = FCommanders[i].TeamID()
	return Result


## The game time (GameTimeManager.GetTimestamp).
func GetServerTime() -> int:
	return TTimeManager.GetTimeStamp()


func Idle() -> void:
	super()
	TDelayedEventHandler.ProcessDueEvents(FDelayedEvents)
	if not FFinished:
		FGlobalEventbus.Trigger(C.eiIdle, [])


## Initializes the scenario, then the players.
func Initialize() -> void:
	# initialze scenario scripts and environment
	super()

	# Create Playermapping
	var Mapping := {}  # Token -> Array of commander IDs

	# Create Commanders for Slots
	for i in GameInformation.Slots.size():
		var Commander := TEntity.CreateFromScript("Commander\\CommanderTemplate", FGlobalEventbus)
		Commander.ID = EntityManager.GenerateUniqueID()

		_InitializeCommander(Commander, GameInformation.Slots[i], GameInformation.League)

		# map slots to player
		for Token: String in GameInformation.Mapping:
			if not Mapping.has(Token):
				Mapping[Token] = []
			if GameInformation.Mapping[Token].has(i):
				Commander.Eventbus.Write(C.eiPlayerOwner, [GameInformation.Player[Token].Name])
				Mapping[Token].append(Commander.ID)
				FGameStatistics.AddCommander(Commander.ID, GameInformation.Player[Token].PlayerID)
		Commander.Deploy()

		FCommanders.append(Commander)

	# add spectator commander
	var Spectator := TEntity.CreateFromScript("Commander\\CommanderTemplate", FGlobalEventbus)
	Spectator.ID = EntityManager.GenerateUniqueID()
	_InitializeCommander(Spectator, TCommanderInformation.new().CreateSpectator(), GameInformation.League)
	Mapping[""] = [Spectator.ID]
	Spectator.Deploy()
	FCommanders.append(Spectator)

	TTokenMappingComponent.new().Create(GameEntity, Mapping)
	TSurrenderComponent.new().Create(GameEntity, GameInformation.Player.size())
	FGameEntity.Eventbus.Trigger(C.eiAfterCreate, [])


func _InitializeCommander(Commander: TEntity, CommanderInformation: TCommanderInformation, _League: int) -> void:
	if Cheatmode:
		Commander.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reGold, 100000.0)
		Commander.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reGold, 100000.0)
		Commander.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reWood, 10000.0)
		Commander.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reTier, 3)

	Commander.Eventbus.Write(C.eiOwnerCommander, [Commander.ID])
	Commander.Eventbus.Write(C.eiTeamID, [CommanderInformation.TeamID])

	# add Cards
	for i in CommanderInformation.Cards.size():
		TCommanderAbilityComponent.new().CreateGroupedSlot(Commander, [], CommanderInformation.Cards[i], i)

	if CommanderInformation.IsBot:
		push_error("TServerGame: bot commanders (TPvPBotComponent) are not ported yet")


## Starts the game: the warm-up timer.
func Start() -> void:
	FGlobalEventbus.Trigger(C.eiGameCommencing, [])


func TeamLost(TeamID: int) -> void:
	# TODO (original): Add proper team handling, instead of hardcoded 2 teams
	if TeamID == 1:
		FWinnerTeamID = 2
	elif TeamID == 2:
		FWinnerTeamID = 1
	elif TeamID == C.PVE_TEAM_ID:
		FWinnerTeamID = 1
	else:
		FWinnerTeamID = 0
	FFinished = true


func TeamSurrendered(TeamID: int) -> void:
	FSurrenderedTeamID = TeamID
