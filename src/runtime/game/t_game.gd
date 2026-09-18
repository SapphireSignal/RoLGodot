class_name TGame
extends TObject
## Port of TGame (BaseConflict.Game.pas:47, implementation :144): the game both sides share. It owns the game
## entity (ID 1, with the TGameTickComponent and the GameDirector), the map of the scenario, the entity manager and
## the start values the scenario scripts set (StartingGold...). Initialize applies the scenario scripts last to
## first, then the mutators, each as Apply(GameEntity, Game).
## Port notes: the original's globals Game and Map are the global bus's Game (and Game.Map); TGame.Create takes the
## global bus the subclass made (the original: the GlobalEventbus global). The script-exposed functions (League,
## IsPvP...) and the component-read ones (IsSandbox, HasStarted, IsShuttingDown...) are methods, as in the original;
## properties stay properties (InGameStatus, ServerTime, Map, EntityManager...).

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

var StartingGold := 0.0
var GoldCap := 0.0
var StartingWood := 0.0
var IncomeUpgradeCap := 0
var StartingTier := 0
var GadgetCountCap := 0
var CharmCountCap := 0
var StartingIncomeRate := 0.0
var IncomeRatePerIncomeUpgrade := 0.0
var StartingIncomeUpgradeCost := 0.0
var IncomeUpgradeCostPerIncomeUpgrade := 0.0
var GoldCapPerTier := 0.0

var FGameInfo: TGameInformation = null
var FShutdown := false
var FMap: TMap = null
var FServerTime := 0
var FGameEntity: TEntity = null
var FEntityManager: TEntityManagerComponent = null
var FGlobalEventbus: TEventbus = null

var CollisionManager: TCollisionManagerComponent = null
var GameDirector: TGameDirectorComponent = null

var GameInfo: TGameInformation:
	get:
		return FGameInfo
var GameEntity: TEntity:
	get:
		return FGameEntity
var Map: TMap:
	get:
		return FMap
var EntityManager: TEntityManagerComponent:
	get:
		return FEntityManager
var GlobalEventbus: TEventbus:
	get:
		return FGlobalEventbus
var ServerTime: int:
	get:
		return GetServerTime()
	set(value):
		FServerTime = value
var InGameStatus: int:
	get:
		return GetIngameStatus()


func Create(GameInfo_ = null, GlobalEventbus_ = null) -> TGame:
	InitValues()
	FGameInfo = GameInfo_
	FGlobalEventbus = GlobalEventbus_
	FGlobalEventbus.Game = self
	FGameEntity = TEntity.new().Create(FGlobalEventbus, 1)
	TGameTickComponent.new().Create(FGameEntity)
	if FGameInfo.Scenario.MapName != "":
		FMap = TMap.new().CreateFromFile(TMap.MapFile(FGameInfo.Scenario.MapName))
	else:
		FMap = TMap.new().CreateEmpty()
	GameDirector = TGameDirectorComponent.new().Create(FGameEntity)
	return self


func Destroy() -> void:
	FShutdown = true
	# first let all entites unsubscribe from global components
	if FEntityManager != null:
		FEntityManager.Free()
		FEntityManager = null
	# then kill rest
	FGameEntity.Free()
	FMap.Destroy()
	FGameInfo.Free()
	CollisionManager = null
	GameDirector = null
	FGlobalEventbus.Game = null
	super()


func GetIngameStatus() -> int:
	if FShutdown:
		return BC.gsShutdown
	var TimeToStart := RParam.AsInteger(FGlobalEventbus.Read(C.eiGameTickTimeToFirstTick, []))
	if TimeToStart >= BC.GAME_WARMING_DURATION:
		return BC.gsLoading
	if TimeToStart > 0:
		return BC.gsWarming
	return BC.gsPlaying


func GetServerTime() -> int:
	return FServerTime


func HasShowdown() -> bool:
	return IsPvP() and not IsSandbox()


func HasStarted() -> bool:
	return RParam.AsInteger(FGlobalEventbus.Read(C.eiGameTickTimeToFirstTick, [])) <= 0


func Idle() -> void:
	FMap.Idle()
	EntityManager.Idle()


## Initializes the scenario environment: the scenario scripts last to first, then the mutators' scripts.
func Initialize() -> void:
	for i in range(FGameInfo.Scenario.ScenarioScriptfile.size() - 1, -1, -1):
		FGameEntity.ApplyScript(FGameInfo.Scenario.ScenarioScriptfile[i], "Apply", [FGameEntity, self])
	for Mutator: TMutatorMetaInfo in FGameInfo.Mutators:
		for ScriptFile: String in Mutator.MutatorScriptfile:
			FGameEntity.ApplyScript(ScriptFile, "Apply", [FGameEntity, self])


func InitValues() -> void:
	StartingGold = 300
	GoldCap = 400
	StartingWood = 1600
	IncomeUpgradeCap = 10
	StartingTier = 1
	GadgetCountCap = 5
	CharmCountCap = 3
	StartingIncomeRate = 10
	IncomeRatePerIncomeUpgrade = 2
	StartingIncomeUpgradeCost = 1500
	IncomeUpgradeCostPerIncomeUpgrade = 250
	GoldCapPerTier = 100


func IsDuo() -> bool:
	return FGameInfo.IsDuo()


func IsOneLane() -> bool:
	return FGameInfo.Scenario.MapName == BC.MAP_SINGLE


func IsPerformanceTest() -> bool:
	return FGameInfo.ScenarioUID == BC.SCENARIO_PERFORMANCE_TEST


func IsPvE() -> bool:
	return FGameInfo.IsPvE()


func IsPvP() -> bool:
	return FGameInfo.IsPvP()


func IsSandbox() -> bool:
	return FGameInfo.IsSandbox()


func IsShuttingDown() -> bool:
	return InGameStatus == BC.gsShutdown


func IsTutorial() -> bool:
	return FGameInfo.IsTutorial()


func IsTwoLane() -> bool:
	return FGameInfo.Scenario.MapName == BC.MAP_DOUBLE


func IsWaiting() -> bool:
	return GetIngameStatus() == BC.gsLoading


func League() -> int:
	if BC.DISABLE_LEAGUE_SYSTEM:
		return BC.DEFAULT_LEAGUE
	return GameInfo.League
