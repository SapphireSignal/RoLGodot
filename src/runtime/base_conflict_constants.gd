extends RefCounted
## Hand port of the functions and set constants of BaseConflict.Constants.pas that the runtime needs.
## (Enum values and the constants the scripts see are generated into src/runtime/dws/dws_const.gd.)
## Preload as `BC`.

const C = preload("res://src/runtime/dws/dws_const.gd")
const L = preload("res://src/runtime/dws/dws_lib.gd")

## APPLICATIONTYPE = {$IFDEF SERVER}nsServer{$ELSE}nsClient{$ENDIF}. The original ran client and server as
## separate programs; the port runs both in one process, so each TEventbus carries its side (ApplicationType).

## EnumInGameStatus (BaseConflict.Types.Shared.pas:18): the game's `IngameStatus`.
enum { gsLoading, gsWarming, gsPlaying, gsShutdown }

## ALL_BUFF_TYPES = [low(EnumBuffType) .. high(EnumBuffType)] (:306)
const ALL_BUFF_TYPES = [C.btNeutral, C.btPositive, C.btNegative, C.btState, C.btDivine, C.btSummoningSickness]

## THINK_TIME_INTERVAL (:62): ms between two thoughts of a TThinkImpulseTimerComponent.
const THINK_TIME_INTERVAL = 250
## UNIT_PROPERTIES_PREVENT_THINKING / _MOVEMENT (:294-295), sorted like DSet.Make.
static var UNIT_PROPERTIES_PREVENT_THINKING: Array = DSet.Make([C.upSummoningSickness, C.upStunned, C.upFrozen,
	C.upBanished, C.upPetrified])
static var UNIT_PROPERTIES_PREVENT_MOVEMENT: Array = DSet.Make([C.upRooted, C.upGrounded, C.upLifted,
	C.upImmobilized])

## Game statistic identifiers (:73-96), counted by TGameStatisticManager.
const GSE_UNIT_SPAWN_PREFIX = "unit_spawns_"
const GSE_UNIT_KILL_PREFIX = "unit_kills_"
const GSE_UNIT_DEATH_PREFIX = "unit_deaths_"
const GSE_WELA_TRIGGER_PREFIX = "wela_triggers_"
const GSE_WELA_TARGET_PREFIX = "wela_targets_"
const GSE_WELA_SPAWN_PREFIX = "wela_spawns_"
const GSE_WELA_KILL_PREFIX = "wela_kills_"
const GSE_WELA_DEATH_PREFIX = "wela_deaths_"
const GSE_WELA_DURATION_PREFIX = "wela_duration_"
const GSE_WELA_GAIN_DAMAGE_PREFIX = "wela_gain_damage_"
const GSE_WELA_DEALT_DAMAGE_PREFIX = "wela_dealt_damage_"
const GSE_CARD_PLAY_PREFIX = "card_play_"
const GSE_CARD_PLAY_COLOR_PREFIX = "card_play_color_"
const GSE_GLOBAL_KILLS = "global_kills"
const GSE_GLOBAL_INSTAKILLS = "global_instakills"
const GSE_GLOBAL_GAIN_DAMAGE = "global_gain_damage"
const GSE_GLOBAL_DEATHS = "global_deaths"
const GSE_GLOBAL_INSTADEATHS = "global_instadeaths"
const GSE_GLOBAL_SPAWNS = "global_spawns"
const GSE_GLOBAL_SPAWNERS = "global_spawners"
const GSE_GLOBAL_DROPS = "global_drops"
const GSE_GLOBAL_BUILDINGS = "global_buildings"
const GSE_GLOBAL_SPELLS = "global_spells"

## BaseConflict.Constants.Cards.pas:203-216
const MIN_LEAGUE = 1
const MAX_LEAGUE = 5
const MIN_LEVEL = 1
const MAX_LEVEL = 5
const DISABLE_LEAGUE_SYSTEM = false
const DEFAULT_LEAGUE = MAX_LEAGUE - 1
const DEFAULT_LEVEL = MAX_LEVEL
## ALL_COLORS (:199): every EnumEntityColor, sorted like DSet.Make.
const ALL_COLORS = [C.ecColorless, C.ecBlack, C.ecGreen, C.ecRed, C.ecBlue, C.ecWhite]
const FILE_IDENTIFIER_DROP = "Drop"
const FILE_IDENTIFIER_SPAWNER = "Spawner"
const FILE_IDENTIFIER_BUILDING = "Building"
const FILE_IDENTIFIER_GOLEMS = "Golems"
const FILE_IDENTIFIER_SPELL = "Spell"
const FILE_EXTENSION_SPELL = ".sps"

## BUILDGRID_SIZE / BUILDGRID_SLOTS (:57-58): a build zone has 8 x 3 fields, 20 without the corners.
const BUILDGRID_SIZE = Vector2i(8, 3)
const BUILDGRID_SLOTS = 20
## EnumClientCommand (:312): the sandbox / tutorial commands a client sends (eiClientCommand [Command, Param]).
enum { ccClearUnits, ccClearAllUnits, ccClearSpawners, ccClearLaneTowers, ccClearGolemTowers, ccBaseBuildingsLevel1,
	ccBaseBuildingsLevel2, ccBaseBuildingsLevel3, ccBaseBuildingsIndestructible, ccToggleOverwatch,
	ccToggleOverwatchSandbox, ccClearOverwatch, ccSaveCameraPosition, ccReturnToSavedCameraPosition,
	ccTutorialGameEvent, ccForceGameTick }

## GAME_TICK_DURATION / GAME_WARMING_DURATION (:48-49): ms per game tick, ms from eiGameCommencing to the first tick.
const GAME_TICK_DURATION = 1000
const GAME_WARMING_DURATION = 10000
## PATH_SCRIPT_SCENARIO / _MUTATOR (:24-25).
const PATH_SCRIPT_SCENARIO = "\\Scripts\\Scenarios\\"
const PATH_SCRIPT_SCENARIO_MUTATOR = PATH_SCRIPT_SCENARIO + "Mutators\\"

## Map names and scenario UIDs (BaseConflict.Constants.Scenario.pas:69-107).
const MAP_SINGLE = "Single"
const MAP_DOUBLE = "Classic"
const SCENARIO_DEBUG_UID = "debug"
const SCENARIO_PERFORMANCE_TEST = "performance_test"
const SCENARIO_SANDBOX_UID = "sandbox"
const SCENARIO_SANDBOX_DUO_UID = "sandbox_duo"
const SCENARIO_SANDBOX_CLASSIC_UID = "sandbox_classic"
const SCENARIO_PVP_TEST_UID = "pvp_test"
const SCENARIO_PVE_TUTORIAL = "tutorial"
const SCENARIO_PVP_DUEL_PREFIX = "duel"
const SCENARIO_PVP_DUEL_1VS1 = SCENARIO_PVP_DUEL_PREFIX
const SCENARIO_PVP_DUEL_1VS1_TWO_LANE = "two_lane_" + SCENARIO_PVP_DUEL_1VS1
const SCENARIO_PVP_DUEL_2VS2 = "duel2v2"
const SCENARIO_PVP_DUEL_2VS2_TWO_LANE = "two_lane_" + SCENARIO_PVP_DUEL_2VS2
const SCENARIO_PVP_DUEL_3VS3 = "duel3v3"
const SCENARIO_PVP_DUEL_3VS3_TWO_LANE = "two_lane_" + SCENARIO_PVP_DUEL_3VS3
const SCENARIO_PVP_DUEL_4VS4 = "duel4v4"
const SCENARIO_PVP_DUEL_4VS4_TWO_LANE = "two_lane_" + SCENARIO_PVP_DUEL_4VS4
const SCENARIO_PVP_1VS1 = "1vs1"
const SCENARIO_PVP_1VS1_TWO_LANE = "two_lane_" + SCENARIO_PVP_1VS1
const SCENARIO_PVP_2VS2 = "2vs2"
const SCENARIO_PVP_2VS2_TWO_LANE = "two_lane_" + SCENARIO_PVP_2VS2
const SCENARIO_PVP_3VS3 = "3vs3"
const SCENARIO_PVP_3VS3_TWO_LANE = "two_lane_" + SCENARIO_PVP_3VS3
const SCENARIO_PVP_4VS4 = "4vs4"
const SCENARIO_PVP_4VS4_TWO_LANE = "two_lane_" + SCENARIO_PVP_4VS4
const SCENARIO_PVP_1VS1_RANKED = "ranked" + SCENARIO_PVP_1VS1
const SCENARIO_PVP_2VS2_RANKED = "ranked" + SCENARIO_PVP_2VS2
const SCENARIO_PVP_3VS3_RANKED = "ranked" + SCENARIO_PVP_3VS3
const SCENARIO_PVP_4VS4_RANKED = "ranked" + SCENARIO_PVP_4VS4
const SCENARIO_PVE_DEFAULT_PREFIX = "pve_"
const SCENARIO_PVE_DEFAULT = "pve_attack_solo"
const SCENARIO_PVE_ATTACK_SOLO = SCENARIO_PVE_DEFAULT_PREFIX + "attack_solo"
const SCENARIO_PVE_ATTACK_DUO = SCENARIO_PVE_DEFAULT_PREFIX + "attack"
## The scenario the test server creates (vars in the original, :111-112): the sandbox, league 1.
const TESTSERVER_SCENARIO_UID = SCENARIO_SANDBOX_UID
const TESTSERVER_SENARIO_LEAGUE = 1

## UNIT_PROPERTIES_STATE_EFFECTS (:293), sorted like DSet.Make.
static var UNIT_PROPERTIES_STATE_EFFECTS: Array = DSet.Make([C.upStunned, C.upRooted, C.upBlinded, C.upFrozen,
	C.upSoulless, C.upGrounded, C.upLifted, C.upPetrified])


## TCardInfoManager.ScriptFilenameToCardType (BaseConflict.Constants.Cards.pas:322): by the (case-insensitive)
## file identifiers; everything else is a drop.
static func ScriptFilenameToCardType(ScriptFile: String) -> int:
	if ScriptFile.containsn(FILE_IDENTIFIER_SPAWNER):
		return C.ctSpawner
	if ScriptFile.containsn(FILE_IDENTIFIER_BUILDING):
		return C.ctBuilding
	if ScriptFile.containsn(FILE_EXTENSION_SPELL) or ScriptFile.containsn(FILE_IDENTIFIER_SPELL):
		return C.ctSpell
	return C.ctDrop


## TCardInfoManager.ScriptFilenameToCardColors (BaseConflict.Constants.Cards.pas:249): the card's colors by its
## folder, as a set. Kept: the single colors are tested first, so 'greenwhite\' gives [ecWhite], 'blackwhite\'
## [ecWhite] and 'blackgreen\' [ecGreen]; the two-color branches never match.
static func ScriptFilenameToCardColors(ScriptFile: String) -> Array:
	var lowerScriptFile := ScriptFile.to_lower()
	if lowerScriptFile.contains("green\\"):
		return [C.ecGreen]
	if lowerScriptFile.contains("white\\"):
		return [C.ecWhite]
	if lowerScriptFile.contains("black\\"):
		return [C.ecBlack]
	if lowerScriptFile.contains("red\\"):
		return [C.ecRed]
	if lowerScriptFile.contains("blue\\"):
		return [C.ecBlue]
	if lowerScriptFile.contains("colorless\\") or lowerScriptFile.contains("golems\\") \
			or lowerScriptFile.contains("neutral\\") or lowerScriptFile.contains("scenario\\"):
		return [C.ecColorless]
	if lowerScriptFile.contains("greenwhite\\"):
		return DSet.Make([C.ecGreen, C.ecWhite])
	if lowerScriptFile.contains("blackwhite\\"):
		return DSet.Make([C.ecBlack, C.ecWhite])
	if lowerScriptFile.contains("blackgreen\\"):
		return DSet.Make([C.ecBlack, C.ecGreen])
	return []


## RES_INT_RESOURCES : SetResource = [reInteger .. high(EnumResource)]
static func IsIntResource(ResourceType: int) -> bool:
	return ResourceType >= C.reInteger and ResourceType <= C.reCharmCount


## RES_FLOAT_RESOURCES : SetResource = [reFloat .. pred(reInteger)]
static func IsFloatResource(ResourceType: int) -> bool:
	return ResourceType >= C.reFloat and ResourceType < C.reInteger


## RES_IGNORE_CAP : SetResource = [reGadgetCount, reCharmCount]
static func IgnoresCap(ResourceType: int) -> bool:
	return ResourceType == C.reGadgetCount or ResourceType == C.reCharmCount


## ResourceAsSingle (BaseConflict.Types.Shared.pas:168): an int resource's value as a single.
static func ResourceAsSingle(ResourceType: int, Resource) -> float:
	if IsIntResource(ResourceType):
		return float(RParam.AsInteger(Resource))
	return RParam.AsSingle(Resource)


## ResourceAdd (BaseConflict.Types.Shared.pas:156)
static func ResourceAdd(ResourceType: int, Summand, Summand2):
	if IsIntResource(ResourceType):
		return RParam.AsInteger(Summand) + RParam.AsInteger(Summand2)
	return RParam.ToSingle(RParam.AsSingle(Summand) + RParam.AsSingle(Summand2))


## ResourceSubtract (BaseConflict.Types.Shared.pas:150)
static func ResourceSubtract(ResourceType: int, Minuend, Subtrahend):
	if IsIntResource(ResourceType):
		return RParam.AsInteger(Minuend) - RParam.AsInteger(Subtrahend)
	return RParam.ToSingle(RParam.AsSingle(Minuend) - RParam.AsSingle(Subtrahend))


## ResourceCompare(ResourceType, Resource, Comparator, ReferenceValue: RParam, ReferenceFactor) (:125):
## compares with ReferenceValue * ReferenceFactor (not rounded, also for int resources).
static func ResourceCompareParam(ResourceType: int, Resource, Comparator: int, ReferenceValue, ReferenceFactor: float = 1.0) -> bool:
	var Value: float
	var Reference: float
	if IsIntResource(ResourceType):
		Value = RParam.AsInteger(Resource)
		Reference = RParam.AsInteger(ReferenceValue) * RParam.ToSingle(ReferenceFactor)
	else:
		Value = RParam.AsSingle(Resource)
		Reference = RParam.AsSingle(ReferenceValue) * RParam.ToSingle(ReferenceFactor)
	match Comparator:
		C.coLowerEqual:
			return Value <= Reference
		C.coLower:
			return Value < Reference
		C.coGreaterEqual:
			return Value >= Reference
		C.coGreater:
			return Value > Reference
		C.coEqual:
			return Value == Reference
	return false


## ResourcePercentage (BaseConflict.Types.Shared.pas:162): Balance / Cap.
static func ResourcePercentage(ResourceType: int, Balance, Cap) -> float:
	if IsIntResource(ResourceType):
		return RParam.ToSingle(float(RParam.AsInteger(Balance)) / RParam.AsInteger(Cap))
	return RParam.ToSingle(RParam.AsSingle(Balance) / RParam.AsSingle(Cap))


## ResourceCompare(ResourceType, Resource, Comparator, ReferenceValue: single) (BaseConflict.Types.Shared.pas:97).
## Int resources compare with Round(ReferenceValue). An unknown comparator gives false.
static func ResourceCompare(ResourceType: int, Resource, Comparator: int, ReferenceValue: float) -> bool:
	var Value: float
	var Reference: float
	if IsIntResource(ResourceType):
		Value = RParam.AsInteger(Resource)
		Reference = L.Round(ReferenceValue)
	else:
		Value = RParam.AsSingle(Resource)
		Reference = RParam.ToSingle(ReferenceValue)
	match Comparator:
		C.coLowerEqual:
			return Value <= Reference
		C.coLower:
			return Value < Reference
		C.coGreaterEqual:
			return Value >= Reference
		C.coGreater:
			return Value > Reference
		C.coEqual:
			return Value == Reference
	return false


## ARMORY_TYPES_NORMAL = [atUnarmored .. atHeavy] (BaseConflict.Constants.Cards.pas:44)
static func IsNormalArmorType(ArmorType: int) -> bool:
	return ArmorType >= C.atUnarmored and ArmorType <= C.atHeavy


## BaseConflict.Constants.pas:1058
static func EventIdentifierToNetworkSend(Event: int) -> int:
	match Event:
		C.eiTeamID, C.eiMoveTo, C.eiStand, C.eiSyncPosition, C.eiDie, C.eiRemoveComponent, \
		C.eiKillEntity, C.eiResourceBalance, C.eiResourceCap, C.eiResourceCost, C.eiLose, C.eiPreFire, C.eiFire, \
		C.eiCancelFire, C.eiFireWarhead, C.eiGameCommencing, C.eiGameStart, \
		C.eiRemoveComponentGroup, C.eiReplaceEntity, C.eiWelaSetMainTarget, C.eiGameTick, C.eiLinkEstablish, \
		C.eiLinkBreak, C.eiSetGridFieldBlocking, C.eiExiled, C.eiUnitProperties, \
		C.eiWelaUnitProduced, C.eiCooldownStartingTime, C.eiGameEvent, \
		C.eiWelaActive, C.eiWelaSavedTargets, C.eiSyncPath, C.eiWaveSpawn, C.eiWelaCooldownReset:
			return C.nsServer
		C.eiUseAbility, C.eiSurrender, C.eiClientCommand:
			return C.nsClient
	return C.nsNone


## BaseConflict.Constants.pas:1073
static func EventIdentifierToBlackboardEvent(Event: int) -> bool:
	match Event:
		C.eiTeamID, C.eiPosition, C.eiFront, C.eiOwnerCommander, C.eiExiled, C.eiBuildgridBlockedFields:
			return true
	return false
