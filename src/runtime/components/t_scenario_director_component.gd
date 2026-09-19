class_name TScenarioDirectorComponent
extends TEntityComponent
## Port of TScenarioDirectorComponent (GameServer/BaseConflict.EntityComponents.Server.pas:797, implementation
## :2498-3445), server only: the PvE scenarios' director (Game.ScenarioDirector). The scenario scripts set it up
## (team, KI players, unit faction, boss waves) and queue timed actions; at every global eiGameTick it runs the
## actions that are due (eiGameTickCounter >= their tick) and lets every KI player think (income, drops, spawners).
## Units come from the card database (ChooseUnitFaction), typed by SCENARIO_UNIT_INFO_MAPPING
## (GameServer/BaseConflict.Constants.Scenario.Server.pas), costs normalized to the gold league (4), level 1.
## Port notes: the original's lists shuffle with Delphi's Random (TUltimateList.Shuffle: for i := Count - 1 downto 0
## Exchange(i, Random(i))); here the same walk with Godot's RNG (randi_range). Where the original raised
## (unknown unit identifier or boss wave, unit without scenario info or squad row), push_error and skip the item.
## PrintDebug only printed a header (the rest was commented out): not ported. TSurvivalScenarioDirectorComponent is
## unused (docs/unused-features.md).

const BC = preload("res://src/runtime/base_conflict_constants.gd")

## EnumUnitType (BaseConflict.Constants.Scenario.Server.pas:14)
enum { utRanged, utMelee, utTank, utDD, utUtil, utSiege, utBigBoss, utSmallBoss, utCannonFodder, utFlying, utGround,
	utUnit, utBuilding }

## ScenarioUnitInfoMapping: card identifier -> unit types.
const SCENARIO_UNIT_INFO_MAPPING = {
	"BigCasterGolem": [utUnit, utGround, utRanged, utUtil],
	"BigFlyingGolem": [utUnit, utFlying, utRanged, utDD],
	"BigGolemTower": [utBuilding],
	"BigMeleeGolem": [utUnit, utGround, utMelee, utTank, utSmallBoss],
	"MediumMeleeGolem": [utUnit, utGround, utMelee, utTank],
	"MeleeGolemTower": [utBuilding],
	"SiegeGolem": [utUnit, utGround, utRanged, utSiege],
	"SmallCasterGolem": [utUnit, utGround, utRanged, utUtil],
	"SmallFlyingGolem": [utUnit, utFlying, utRanged, utDD],
	"SmallGolemTower": [utBuilding],
	"SmallMeleeGolem": [utUnit, utGround, utMelee, utCannonFodder],
	"SmallRangedGolem": [utUnit, utGround, utRanged, utDD],
	"BossGolem": [utUnit, utGround, utMelee, utBigBoss],
	"GolemLaneTowerLevel1": [utBuilding],
	"GolemLaneTowerLevel2": [utBuilding],
	"GolemLaneTowerLevel3": [utBuilding],
}

## EnumSquadRow
enum { srFront, srOffTank, srRanged, srArtillery }

const SQUAD_ROW_DISTANCE = 3
const SQUAD_UNIT_SPACE = 3


## A unit the director can drop or build, with its costs normalized to the gold league.
class ScenarioUnit:
	extends RefCounted
	var GoldCost := 0
	var WoodCost := 0
	var SquadSize := 0
	var Types: Array = []
	var Identifier := ""
	var DropFilename := ""
	var SpawnerFileName := ""

	## Null (logged) if the unit has no scenario info.
	static func Make(CardInfo: TCardInfo, Cache: TEntityDataCache) -> ScenarioUnit:
		var Manager := TCardInfoManager.Instance()
		var Result := ScenarioUnit.new()
		# use gold league as normalized card league (as scenarios created for gold league)
		var NormalizedCardInfo := Manager.ResolveCardUID(CardInfo.UID, 4, 1)
		Result.GoldCost = NormalizedCardInfo.GoldCost(Cache)
		Result.SquadSize = NormalizedCardInfo.SquadSize(Cache)
		Result.Identifier = TCardInfoManager.ScriptFilenameToCardIdentifier(CardInfo.Filename)
		if not SCENARIO_UNIT_INFO_MAPPING.has(Result.Identifier):
			push_error('TScenarioDirectorComponent.TUnit.Create: For unit "%s" was no infodata found.' % Result.Identifier)
			return null
		Result.Types = SCENARIO_UNIT_INFO_MAPPING[Result.Identifier]
		Result.DropFilename = CardInfo.Filename.replace("Drop", "")
		for CardUID in Manager.GetAllCardUIDs():
			var SpawnerCardInfo := Manager.TryResolveCardUID(CardUID, CardInfo.League, CardInfo.Level)
			if SpawnerCardInfo != null:
				if DelphiRtl.SameText(TCardInfoManager.ScriptFilenameToCardIdentifier(SpawnerCardInfo.Filename),
						Result.Identifier) and SpawnerCardInfo.IsSpawner():
					NormalizedCardInfo = Manager.ResolveCardUID(SpawnerCardInfo.UID, 4, 1)
					Result.SpawnerFileName = SpawnerCardInfo.Filename
					Result.WoodCost = NormalizedCardInfo.WoodCost(Cache)
					break
		return Result


## TUnitSubset: the units a random pick is made from.
class UnitSubset:
	extends RefCounted
	var FSubset: Array = []

	func AddUnits(Units: Array) -> void:
		FSubset.append_array(Units)

	func Clear() -> void:
		FSubset.clear()

	## Shuffles the subset, then returns its first unit that Filter (Callable(Unit) -> bool, empty = none) accepts,
	## or null.
	func GetRandomUnit(Filter := Callable()) -> ScenarioUnit:
		TScenarioDirectorComponent.Shuffle(FSubset)
		for AUnit in FSubset:
			if not Filter.is_valid() or Filter.call(AUnit):
				return AUnit
		return null


## TUltimateList.Shuffle: for i := Count - 1 downto 0 do Exchange(i, Random(i)); Random(0) = 0.
static func Shuffle(List: Array) -> void:
	for i in range(List.size() - 1, -1, -1):
		var j := randi_range(0, i - 1) if i > 0 else 0
		var Temp = List[i]
		List[i] = List[j]
		List[j] = Temp


## A pattern for a boss wave: fixed units plus random dynamic units for the rest of the gold.
class BossWave:
	extends RefCounted
	var FFixedUnits: Array = []
	var FDynamicUnits: UnitSubset
	var FixedGoldValue := 0
	var Identifier := ""

	func _init(Identifier_: String, FixedUnits: Array, DynamicUnits: UnitSubset) -> void:
		FFixedUnits = FixedUnits
		FDynamicUnits = DynamicUnits
		Identifier = Identifier_
		for AUnit in FFixedUnits:
			FixedGoldValue += AUnit.GoldCost

	## The fixed units, then random dynamic units until the gold does not suffice for any of them.
	func ComputeBossWave(DynamicGoldValue: int) -> Array:
		var Result: Array = FFixedUnits.duplicate()
		var Gold := [DynamicGoldValue]
		while true:
			var AUnit := FDynamicUnits.GetRandomUnit(func(x: ScenarioUnit) -> bool: return x.GoldCost <= Gold[0])
			if AUnit == null:
				break
			Gold[0] -= AUnit.GoldCost
			Result.append(AUnit)
		return Result


## TAction and its descendants: something the director does at GameTick.
class Action:
	extends RefCounted
	var Parent: TScenarioDirectorComponent
	var GameTick := 0

	func _init(GameTick_: int, Parent_: TScenarioDirectorComponent) -> void:
		GameTick = GameTick_
		Parent = Parent_

	func Execute() -> void:
		pass


class EventAction:
	extends Action
	var Eventname := ""

	func Execute() -> void:
		Parent.GlobalEventbus().Trigger(C.eiGameEvent, [Eventname])


## TSetGoldIncomeAction, TSetGoldAction, TSetWoodAction, TSetWoodIncomeAction (Field: the value set).
class ValueAction:
	extends Action
	var Value := 0
	var Field := ""

	func Execute() -> void:
		match Field:
			"GoldIncome":
				Parent.FGoldIncome = Value
			"WoodIncome":
				Parent.FWoodIncome = Value
			"Gold":
				for KIPlayer in Parent.FKIPlayers:
					KIPlayer.Gold = Value
			"Wood":
				for KIPlayer in Parent.FKIPlayers:
					KIPlayer.Wood = Value


class ChangeUnitSubsetAction:
	extends Action
	var Units: Array = []
	var TargetSubset: UnitSubset
	var OverwriteSubset := false

	func Execute() -> void:
		if OverwriteSubset:
			TargetSubset.Clear()
		TargetSubset.AddUnits(Units)


class DropUnitsNowAction:
	extends Action

	func Execute() -> void:
		for KIPlayer in Parent.FKIPlayers:
			KIPlayer.DropUnits()


class SpawnBossWaveAction:
	extends Action
	var DynamicGoldValue := 0
	var Wave: BossWave

	func Execute() -> void:
		for KIPlayer in Parent.FKIPlayers:
			Parent.SpawnUnits(Wave.ComputeBossWave(DynamicGoldValue), KIPlayer.SpawnPoint)


## Per KI player: shuffles the boss wave pool, takes the first wave it can afford and spends the rest dynamically.
class SpawnRandomBossWaveAction:
	extends Action
	var GoldValue := 0

	func Execute() -> void:
		for KIPlayer in Parent.FKIPlayers:
			TScenarioDirectorComponent.Shuffle(Parent.FBossWavePool)
			var Wave: BossWave = null
			for Item in Parent.FBossWavePool:
				if Item.FixedGoldValue <= GoldValue:
					Wave = Item
					break
			if Wave == null:
				push_error("TScenarioDirectorComponent.SpawnRandomBossWave: No bosswave with goldcost <= %d was found."
					% GoldValue)
				return
			Parent.SpawnUnits(Wave.ComputeBossWave(GoldValue - Wave.FixedGoldValue), KIPlayer.SpawnPoint)


class RegisterBossWaveAction:
	extends Action
	var Wave: BossWave

	func Execute() -> void:
		Parent.FBossWavePool.append(Wave)


class UnregisterBossWaveAction:
	extends Action
	var BossWaveIdentifier := ""

	func Execute() -> void:
		for i in Parent.FBossWavePool.size():
			if Parent.FBossWavePool[i].Identifier == BossWaveIdentifier:
				Parent.FBossWavePool.remove_at(i)
				return
		push_error('TScenarioDirectorComponent.TUnregisterBossWaveAction.Execute: No bosswave with identifier "%s" was found.'
			% BossWaveIdentifier)


## A computer player: saves gold for drops at its spawn point and builds spawners on its build grid.
class KIPlayer:
	extends RefCounted
	var Buildgrid := 0
	var SpawnPoint := Vector2.ZERO
	## amount of gold that will saved to spawn units, after spawning units, new value will roled
	var NextGoldSave := 0
	## current gold the director has to spawn units
	var Gold := 0
	var NextSpawner: ScenarioUnit = null
	## current wood the director has to spawn units
	var Wood := 0
	var SpawnerCount := 0
	var Director: TScenarioDirectorComponent

	func _init(Director_: TScenarioDirectorComponent, Buildgrid_: int, SpawnPoint_: Vector2) -> void:
		Director = Director_
		Buildgrid = Buildgrid_
		SpawnPoint = SpawnPoint_

	func DoThink() -> void:
		Gold += Director.FGoldIncome
		Wood += Director.FWoodIncome
		if Gold >= NextGoldSave:
			DropUnits()
			NextGoldSave = 300
		SpawnSpawner()

	## Use all current available gold to spawn units (only units costing exactly NextGoldSave).
	func DropUnits() -> void:
		var UnitList: Array = []
		while true:
			var AUnit := Director.FDropUnitSubset.GetRandomUnit(
				func(x: ScenarioUnit) -> bool: return x.GoldCost <= Gold and x.GoldCost == NextGoldSave)
			if AUnit == null:
				break
			Gold -= AUnit.GoldCost
			UnitList.append(AUnit)
		Director.SpawnUnits(UnitList, SpawnPoint)

	## Fields in build grid order (8 per row), skipping 0, 7 and 16 (blocked corners).
	func GetNextSpawnerPosition() -> Vector2i:
		if SpawnerCount in [0, 7, 16]:
			SpawnerCount += 1
		var Result := Vector2i(SpawnerCount % 8, SpawnerCount / 8)
		SpawnerCount += 1
		return Result

	func SpawnSpawner() -> void:
		if NextSpawner != null:
			# if woodcost can payed, build the spawner; never more spawners than build grid slots
			if Wood >= NextSpawner.WoodCost and BC.BUILDGRID_SLOTS > SpawnerCount:
				Wood -= NextSpawner.WoodCost
				var SpawnerPosition := GetNextSpawnerPosition()
				Director.ServerGame().ServerEntityManager.SpawnSpawner(Buildgrid, SpawnerPosition,
					NextSpawner.SpawnerFileName, Director.FTeamID, -1, null)
				NextSpawner = Director.FSpawnerUnitSubset.GetRandomUnit()
		else:
			# there have to be everytime a spawner
			NextSpawner = Director.FSpawnerUnitSubset.GetRandomUnit()


## all spawned units/buildings will have this team id
var FTeamID := 0
var FLeague := 0
## current income for director gold/sec
var FGoldIncome := 0
## current income for director wood/sec
var FWoodIncome := 0
var FActions: Array = []
var FMirroringEnabled := false
## all available units for director
var FUnitPool: Array = []
var FDropUnitSubset: UnitSubset
var FSpawnerUnitSubset: UnitSubset
var FBossWavePool: Array = []
var FKIPlayers: Array = []
var FLastUnitsSpawned: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGameTick", C.eiGameTick, C.epLast, C.etTrigger, C.esGlobal))


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FActions = []
	FUnitPool = []
	FLastUnitsSpawned = []
	FDropUnitSubset = UnitSubset.new()
	FSpawnerUnitSubset = UnitSubset.new()
	FBossWavePool = []
	FKIPlayers = []
	FLeague = ServerGame().League()
	return self


## Port: also drops the KI players and actions, which point back to the director (reference cycles).
func Destroy() -> void:
	FLastUnitsSpawned.clear()
	FActions.clear()
	FBossWavePool.clear()
	FUnitPool.clear()
	FKIPlayers.clear()
	super()


func ServerGame():
	return GlobalEventbus().Game


# --------------------- setup methods -----------------------------------

func SetTeam(TeamID: int) -> TScenarioDirectorComponent:
	FTeamID = TeamID
	return self


func SetLeague(League: int) -> TScenarioDirectorComponent:
	FLeague = League
	return self


## Set default spawnpoint for drops. Units will spawned around the point.
func AddKIPlayer(GridID: int, PosX: int, PosY: int) -> TScenarioDirectorComponent:
	FKIPlayers.append(KIPlayer.new(self, GridID, Vector2(PosX, PosY)))
	return self


## Builds the unit pool from every card of the faction (at the director's league, level 1): no spawners, no
## 'Golems' files, units only (no buildings); both subsets start with the whole pool.
func ChooseUnitFaction(UnitFaction: int) -> TScenarioDirectorComponent:
	var Manager := TCardInfoManager.Instance()
	for CardUID in Manager.GetAllCardUIDs():
		var CardInfo := Manager.ResolveCardUID(CardUID, FLeague, 1)
		if CardInfo != null and CardInfo.CardColors.has(UnitFaction) and not CardInfo.IsSpawner() and \
				not CardInfo.Filename.contains(BC.FILE_IDENTIFIER_GOLEMS):
			var AUnit := ScenarioUnit.Make(CardInfo, GlobalEventbus().EntityDataCache)
			# only allow units in pool, no buildings
			if AUnit != null and AUnit.Types.has(utUnit):
				FUnitPool.append(AUnit)
	FDropUnitSubset.AddUnits(FUnitPool)
	FSpawnerUnitSubset.AddUnits(FUnitPool)
	return self


## Register a bosswave template by set fixed and dynamic units, later spawned by SpawnBossWave or SpawnRandomBossWave.
func RegisterBossWave(Identifier: String, FixedUnits: Array, DynamicUnits: Array) -> TScenarioDirectorComponent:
	FBossWavePool.append(_MakeBossWave(Identifier, FixedUnits, DynamicUnits))
	return self


## When mirroring is enabled, all units/buildings spawned are also spawned on the other lane (y mirrored).
func EnableMirroring() -> TScenarioDirectorComponent:
	FMirroringEnabled = true
	return self


func DisableMirroring() -> TScenarioDirectorComponent:
	FMirroringEnabled = false
	return self


## Spawns guards (units with overwatch and flee) at the position: the fixed units, then dynamic units for the rest
## of GoldValue; with mirroring once more on the other lane (fixed units shared, dynamic ones rolled again).
func SpawnGuards(PosX: int, PosY: int, FixedUnits: Array, DynamicUnits: Array, GoldValue: int) -> TScenarioDirectorComponent:
	var DynamicGoldValue := GoldValue
	var FixedUnitsArray := GetUnitsByIdentifier(FixedUnits)
	for AUnit in FixedUnitsArray:
		DynamicGoldValue -= AUnit.GoldCost
	var Lanes: Array = [1, -1] if FMirroringEnabled else [1]
	for Lane in Lanes:
		var DynamicUnitsSubset := UnitSubset.new()
		DynamicUnitsSubset.AddUnits(GetUnitsByIdentifier(DynamicUnits))
		var Guards := BossWave.new("", FixedUnitsArray, DynamicUnitsSubset)
		SpawnUnits(Guards.ComputeBossWave(DynamicGoldValue), Vector2(PosX, PosY * Lane), true)
	return self


func SpawnUnit(PositionX: float, PositionY: float, PatternFileName: String) -> TScenarioDirectorComponent:
	ServerGame().ServerEntityManager.SpawnUnit(PositionX, PositionY, PatternFileName, FTeamID)
	if FMirroringEnabled:
		ServerGame().ServerEntityManager.SpawnUnit(PositionX, PositionY * -1, PatternFileName, FTeamID)
	return self


## Mirrored when enabled. The overload with the out parameter SpawnedEntity is never called by the scripts (they use
## SpawnUnitWithoutLimitedLifetimeAndReturnEntity): not ported.
func SpawnUnitWithoutLimitedLifetime(PositionX: float, PositionY: float, PatternFileName: String) -> TScenarioDirectorComponent:
	ServerGame().ServerEntityManager.SpawnUnitWithoutLimitedLifetime(PositionX, PositionY, PatternFileName, FTeamID)
	if FMirroringEnabled:
		ServerGame().ServerEntityManager.SpawnUnitWithoutLimitedLifetime(PositionX, PositionY * -1, PatternFileName,
			FTeamID)
	return self


func SpawnUnitWithoutLimitedLifetimeAndReturnEntity(PositionX: float, PositionY: float, PatternFileName: String):
	assert(not FMirroringEnabled)
	return ServerGame().ServerEntityManager.SpawnUnitWithoutLimitedLifetime(PositionX, PositionY, PatternFileName,
		FTeamID)


func SpawnUnitWithoutLimitedLifetimeWithFront(PositionX: float, PositionY: float, FrontX: float, FrontY: float, PatternFileName: String) -> TScenarioDirectorComponent:
	ServerGame().ServerEntityManager.SpawnUnitWithoutLimitedLifetimeWithFront(PositionX, PositionY, FrontX, FrontY,
		PatternFileName, FTeamID)
	if FMirroringEnabled:
		ServerGame().ServerEntityManager.SpawnUnitWithoutLimitedLifetimeWithFront(PositionX, PositionY * -1, FrontX,
			FrontY, PatternFileName, FTeamID)
	return self


# --------------------- actions methods ---------------------------------

func RegisterBossWaveAtTime(GameTick: int, Identifier: String, FixedUnits: Array, DynamicUnits: Array) -> TScenarioDirectorComponent:
	var NewAction := RegisterBossWaveAction.new(GameTick, self)
	NewAction.Wave = _MakeBossWave(Identifier, FixedUnits, DynamicUnits)
	FActions.append(NewAction)
	return self


func UnregisterBossWaveAtTime(GameTick: int, Identifier: String) -> TScenarioDirectorComponent:
	var NewAction := UnregisterBossWaveAction.new(GameTick, self)
	NewAction.BossWaveIdentifier = Identifier
	FActions.append(NewAction)
	return self


func ChangeGold(GameTick: int, Gold: int) -> TScenarioDirectorComponent:
	return _AddValueAction(GameTick, "Gold", Gold)


func ChangeGoldIncome(GameTick: int, GoldIncome: int) -> TScenarioDirectorComponent:
	return _AddValueAction(GameTick, "GoldIncome", GoldIncome)


func ChangeWoodIncome(GameTick: int, WoodIncome: int) -> TScenarioDirectorComponent:
	return _AddValueAction(GameTick, "WoodIncome", WoodIncome)


func ChangeWood(GameTick: int, Wood: int) -> TScenarioDirectorComponent:
	return _AddValueAction(GameTick, "Wood", Wood)


func ChangeUnitDropSubset(GameTick: int, Subset: Array) -> TScenarioDirectorComponent:
	return _AddSubsetAction(GameTick, Subset, true, FDropUnitSubset)


func AddUnitsToDropSubset(GameTick: int, Subset: Array) -> TScenarioDirectorComponent:
	return _AddSubsetAction(GameTick, Subset, false, FDropUnitSubset)


func ChangeUnitSpawnerSubset(GameTick: int, Subset: Array) -> TScenarioDirectorComponent:
	return _AddSubsetAction(GameTick, Subset, true, FSpawnerUnitSubset)


func AddUnitsToSpawnerSubset(GameTick: int, Subset: Array) -> TScenarioDirectorComponent:
	return _AddSubsetAction(GameTick, Subset, false, FSpawnerUnitSubset)


func SpawnBossWave(GameTick: int, Identifier: String, DynamicGoldValue: int) -> TScenarioDirectorComponent:
	var Wave: BossWave = null
	for Item in FBossWavePool:
		if Item.Identifier == Identifier:
			Wave = Item
			break
	if Wave == null:
		push_error("TAdvancedList<T>.FilterFirst: Item not found.")
		return self
	var NewAction := SpawnBossWaveAction.new(GameTick, self)
	NewAction.Wave = Wave
	NewAction.DynamicGoldValue = DynamicGoldValue
	FActions.append(NewAction)
	return self


func SpawnRandomBossWave(GameTick: int, GoldValue: int) -> TScenarioDirectorComponent:
	var NewAction := SpawnRandomBossWaveAction.new(GameTick, self)
	NewAction.GoldValue = GoldValue
	FActions.append(NewAction)
	return self


## Using all gold currently available to drop units.
func DropUnitsNow(GameTick: int) -> TScenarioDirectorComponent:
	FActions.append(DropUnitsNowAction.new(GameTick, self))
	return self


func AddEvent(GameTick: int, Eventname: String) -> TScenarioDirectorComponent:
	var NewAction := EventAction.new(GameTick, self)
	NewAction.Eventname = Eventname
	FActions.append(NewAction)
	return self


# --------------------- internals ---------------------------------------

func _AddValueAction(GameTick: int, Field: String, Value: int) -> TScenarioDirectorComponent:
	var NewAction := ValueAction.new(GameTick, self)
	NewAction.Field = Field
	NewAction.Value = Value
	FActions.append(NewAction)
	return self


func _AddSubsetAction(GameTick: int, Subset: Array, Overwrite: bool, Target: UnitSubset) -> TScenarioDirectorComponent:
	var NewAction := ChangeUnitSubsetAction.new(GameTick, self)
	NewAction.Units = GetUnitsByIdentifier(Subset)
	NewAction.OverwriteSubset = Overwrite
	NewAction.TargetSubset = Target
	FActions.append(NewAction)
	return self


func _MakeBossWave(Identifier: String, FixedUnits: Array, DynamicUnits: Array) -> BossWave:
	var DynamicUnitsSubset := UnitSubset.new()
	DynamicUnitsSubset.AddUnits(GetUnitsByIdentifier(DynamicUnits))
	return BossWave.new(Identifier, GetUnitsByIdentifier(FixedUnits), DynamicUnitsSubset)


## The pool units of the identifiers (case-sensitive), in order; duplicates give the same unit twice.
func GetUnitsByIdentifier(UnitSubsetIdentifiers: Array) -> Array:
	var Result: Array = []
	for Identifier in UnitSubsetIdentifiers:
		var Found: ScenarioUnit = null
		for Item in FUnitPool:
			if Item.Identifier == Identifier:
				Found = Item
				break
		if Found == null:
			push_error('TScenarioDirectorComponent.GetUnitsByIdentifier: unit "%s" is not in the pool.' % Identifier)
		else:
			Result.append(Found)
	return Result


## The first queued SpawnRandomBossWave action, or null.
func GetNextBossWaveAction() -> SpawnRandomBossWaveAction:
	for QueuedAction in FActions:
		if QueuedAction is SpawnRandomBossWaveAction:
			return QueuedAction
	return null


## Spawns the units in squad rows behind Position (x grows by SQUAD_ROW_DISTANCE per row): cannon fodder in front,
## then tanks and melee, ranged, siege; each row centred on Position.y, SQUAD_UNIT_SPACE apart. A row of more than 7
## starts a new row every 7 units, each centred. Fixed bug of the original: the wrapped units kept the y offset of
## one long row, so the new row sat off to one side (docs/original-bugs.md). Targets are clamped to the walk
## zone; the units face their next lane. WithOverwatch: guards with overwatch and flee (30).
func SpawnUnits(Units: Array, Position: Vector2, WithOverwatch: bool = false) -> void:
	FLastUnitsSpawned.clear()
	var Squad: Array = [[], [], [], []]
	# assign units to categories/rows
	for AUnit in Units:
		var SquadLine: Array
		if AUnit.Types.has(utCannonFodder):
			SquadLine = Squad[srFront]
		elif AUnit.Types.has(utTank):
			SquadLine = Squad[srOffTank]
		elif AUnit.Types.has(utSiege):
			SquadLine = Squad[srArtillery]
		elif AUnit.Types.has(utRanged):
			SquadLine = Squad[srRanged]
		elif AUnit.Types.has(utMelee):
			SquadLine = Squad[srOffTank]
		else:
			push_error('TScenarioDirectorComponent.SpawnUnits: Could not assign unit "%s" to a squad row.' % AUnit.Identifier)
			continue
		for i in AUnit.SquadSize:
			SquadLine.append(AUnit)
	# spawn all units from squad
	var Game = ServerGame()
	var RowOffset := Vector2.ZERO
	for SquadRow in [srFront, srOffTank, srRanged, srArtillery]:
		var SquadLine: Array = Squad[SquadRow]
		if SquadLine.size() > 0:
			var counter := 0
			for i in SquadLine.size():
				if counter > 6:
					RowOffset = RowOffset + Vector2(SQUAD_ROW_DISTANCE, 0)
					counter = 0
				var AUnit: ScenarioUnit = SquadLine[i]
				# the row of up to 7 this unit starts or continues, centred on Position.y
				var RowSize := mini(7, SquadLine.size() - (i - counter))
				var Target := Position + RowOffset + Vector2(0, counter * SQUAD_UNIT_SPACE -
					(RowSize - 1) * SQUAD_UNIT_SPACE / 2.0)
				if Game != null:
					Target = Game.Map.ClampToZone(C.ZONE_WALK, Target)
				var Front: Vector2 = Game.Map.Lanes.GetOrientationOfNextLane(Game, Target, FTeamID)
				if not WithOverwatch:
					Game.ServerEntityManager.SpawnUnit(Target, Front, AUnit.DropFilename,
						TServerEntityManagerComponent.INHERIT_FROM_GAME, TServerEntityManagerComponent.INHERIT_FROM_GAME,
						FTeamID)
				else:
					Game.ServerEntityManager.SpawnUnitWithOverwatchAndFlee(Target, Front, AUnit.DropFilename, FTeamID, 30)
				FLastUnitsSpawned.append(AUnit)
				counter += 1
			RowOffset = RowOffset + Vector2(SQUAD_ROW_DISTANCE, 0)


## Will execute (and drop) all actions where GameTick >= action.GameTick, from the last queued to the first.
func ProcessActions(GameTick: int) -> void:
	for i in range(FActions.size() - 1, -1, -1):
		if FActions[i].GameTick <= GameTick:
			FActions[i].Execute()
			FActions.remove_at(i)


func DoGameTick() -> void:
	var Tick := RParam.AsInteger(GlobalEventbus().Read(C.eiGameTickCounter, []))
	ProcessActions(Tick)
	for Player in FKIPlayers:
		Player.DoThink()


## Check on each game tick, whether something could be build or not.
func OnGameTick() -> bool:
	DoGameTick()
	return true
