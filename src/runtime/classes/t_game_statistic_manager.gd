class_name TGameStatisticManager
extends TObject
## Port of TGameStatisticManager (GameServer/BaseConflict.Classes.Server.pas:20, implementation :111): counts game
## events per commander (spawns, kills, deaths, wela use, played cards) for the game's end statistics. The server
## game owns one as `Game.Statistics`.
## CardPlayed takes the card type and colors from the file name (BC.ScriptFilenameToCard{Type,Colors}); its
## "Unimplemented card type" raise is unreachable (every name is some type).
## BuildStatistics returns the RGameFinishedStatistics record as a Dictionary
## {duration, commander_statistics: [{player_id, game_events: [{identifier, count}]}]}, commanders and events in
## insertion order (the original: TDictionary hash order).

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

# CommanderID -> (GameEventIdentifier -> Count)
var FCommanderStatistics := {}
# CommanderID -> PlayerID
var FPlayer := {}


func Create() -> TGameStatisticManager:
	FCommanderStatistics = {}
	FPlayer = {}
	return self


func Destroy() -> void:
	FCommanderStatistics = {}
	FPlayer = {}
	super()


## The event counts of a commander (created on first use).
func _Events(CommanderID: int) -> Dictionary:
	if not FCommanderStatistics.has(CommanderID):
		FCommanderStatistics[CommanderID] = {}
	return FCommanderStatistics[CommanderID]


func CountEvent(CommanderID: int, Identifier: String, Times: int = 1) -> int:
	var EventDict := _Events(CommanderID)
	var Result: int = EventDict.get(Identifier, 0) + Times
	EventDict[Identifier] = Result
	return Result


func MaxEvent(CommanderID: int, Identifier: String, Times: int = 1) -> int:
	var EventDict := _Events(CommanderID)
	var CurrentCount: int = EventDict.get(Identifier, 0)
	if CurrentCount > Times:
		return CurrentCount
	EventDict[Identifier] = Times
	return Times


## The count of one event of a commander, 0 if never counted (port helper for tests and the end screen).
func GetCount(CommanderID: int, Identifier: String) -> int:
	return FCommanderStatistics.get(CommanderID, {}).get(Identifier, 0)


## Remove alternates for now: drops the color suffixes and '.sps', then the path.
func SanitizeScriptFileName(ScriptFileName: String) -> String:
	var Result := ScriptFileName
	for Pattern in ["_White", "_Green", "_Black", "_Red", "_Blue", ".sps"]:
		Result = Result.replace(Pattern, "")
	var Delimiter := maxi(Result.rfind("/"), Result.rfind("\\"))
	return Result.substr(Delimiter + 1)


## Triggered whenever a commander plays a card: its type's global count, its colors and the per-card count (and
## the highest per-card count as card_play_countoftype).
func CardPlayed(CommanderID: int, ScriptFileName: String) -> void:
	match BC.ScriptFilenameToCardType(ScriptFileName):
		C.ctDrop:
			GlobalDrops(CommanderID)
		C.ctSpell:
			GlobalSpells(CommanderID)
		C.ctBuilding:
			GlobalBuildings(CommanderID)
		C.ctSpawner:
			GlobalSpawners(CommanderID)
	var CardColors := BC.ScriptFilenameToCardColors(ScriptFileName)
	if CardColors.has(C.ecColorless):
		CountEvent(CommanderID, BC.GSE_CARD_PLAY_COLOR_PREFIX + "colorless")
	if CardColors.has(C.ecBlack):
		CountEvent(CommanderID, BC.GSE_CARD_PLAY_COLOR_PREFIX + "black")
	if CardColors.has(C.ecGreen):
		CountEvent(CommanderID, BC.GSE_CARD_PLAY_COLOR_PREFIX + "green")
	if CardColors.has(C.ecRed):
		CountEvent(CommanderID, BC.GSE_CARD_PLAY_COLOR_PREFIX + "red")
	if CardColors.has(C.ecBlue):
		CountEvent(CommanderID, BC.GSE_CARD_PLAY_COLOR_PREFIX + "blue")
	if CardColors.has(C.ecWhite):
		CountEvent(CommanderID, BC.GSE_CARD_PLAY_COLOR_PREFIX + "white")
	var PlayCount := CountEvent(CommanderID, BC.GSE_CARD_PLAY_PREFIX + SanitizeScriptFileName(ScriptFileName))
	MaxEvent(CommanderID, BC.GSE_CARD_PLAY_PREFIX + "countoftype", PlayCount)


func AddCommander(CommanderID: int, PlayerID: int) -> void:
	FPlayer[CommanderID] = PlayerID
	CountEvent(CommanderID, "commander_created")


func BuildStatistics(GlobalEventbus) -> Dictionary:
	var Statistics := {
		"duration": RParam.AsInteger(GlobalEventbus.Read(C.eiGameTickCounter, [])),
		"commander_statistics": [],
	}
	for CommanderID in FCommanderStatistics:
		if FPlayer.has(CommanderID):
			var GameEvents: Array = []
			for Identifier in FCommanderStatistics[CommanderID]:
				GameEvents.append({"identifier": Identifier, "count": FCommanderStatistics[CommanderID][Identifier]})
			Statistics["commander_statistics"].append({"player_id": FPlayer[CommanderID], "game_events": GameEvents})
	return Statistics


# --- Unit related events -----------------------------------------------------------------

## Triggered whenever a unit is spawned.
func UnitSpawned(CommanderID: int, ScriptFileName: String) -> void:
	CountEvent(CommanderID, BC.GSE_UNIT_SPAWN_PREFIX + SanitizeScriptFileName(ScriptFileName))
	if ScriptFileName.contains("Building"):
		CountEvent(CommanderID, BC.GSE_UNIT_SPAWN_PREFIX + "building")
	if ScriptFileName.contains("Units\\") and not (ScriptFileName.contains(BC.FILE_IDENTIFIER_DROP)
			or ScriptFileName.contains(BC.FILE_IDENTIFIER_SPAWNER) or ScriptFileName.contains(BC.FILE_IDENTIFIER_BUILDING)):
		GlobalSpawns(CommanderID)


## Triggered whenever a unit has killed another unit.
func UnitKills(CommanderID: int, ScriptFileName: String) -> void:
	CountEvent(CommanderID, BC.GSE_UNIT_KILL_PREFIX + SanitizeScriptFileName(ScriptFileName))
	GlobalKills(CommanderID)


## Triggered whenever a unit died.
func UnitDeaths(CommanderID: int, ScriptFileName: String) -> void:
	CountEvent(CommanderID, BC.GSE_UNIT_DEATH_PREFIX + SanitizeScriptFileName(ScriptFileName))
	GlobalDeaths(CommanderID)


# --- Wela related events -----------------------------------------------------------------

func WelaSpawns(CommanderID: int, AbilityName: String, Times: int) -> void:
	CountEvent(CommanderID, BC.GSE_WELA_SPAWN_PREFIX + AbilityName, Times)


func WelaDeaths(CommanderID: int, AbilityName: String, Times: int) -> void:
	CountEvent(CommanderID, BC.GSE_WELA_DEATH_PREFIX + AbilityName, Times)


func WelaKills(CommanderID: int, AbilityName: String, Times: int) -> void:
	CountEvent(CommanderID, BC.GSE_WELA_KILL_PREFIX + AbilityName, Times)


func WelaTriggers(CommanderID: int, AbilityName: String, Times: int) -> void:
	CountEvent(CommanderID, BC.GSE_WELA_TRIGGER_PREFIX + AbilityName, Times)


func WelaTargets(CommanderID: int, AbilityName: String, Times: int) -> void:
	CountEvent(CommanderID, BC.GSE_WELA_TARGET_PREFIX + AbilityName, Times)


func WelaDamage(CommanderID: int, AbilityName: String, Times: int) -> void:
	CountEvent(CommanderID, BC.GSE_WELA_GAIN_DAMAGE_PREFIX + AbilityName, Times)


func WelaDamageMax(CommanderID: int, AbilityName: String, Times: int) -> void:
	MaxEvent(CommanderID, BC.GSE_WELA_GAIN_DAMAGE_PREFIX + AbilityName, Times)


func WelaDealtDamage(CommanderID: int, AbilityName: String, Times: int) -> void:
	CountEvent(CommanderID, BC.GSE_WELA_DEALT_DAMAGE_PREFIX + AbilityName, Times)


func WelaDuration(CommanderID: int, AbilityName: String, Times: int) -> void:
	CountEvent(CommanderID, BC.GSE_WELA_DURATION_PREFIX + AbilityName, Times)


# --- Global events -----------------------------------------------------------------------

func GlobalSpawners(CommanderID: int) -> void:
	CountEvent(CommanderID, BC.GSE_GLOBAL_SPAWNERS)


func GlobalDrops(CommanderID: int) -> void:
	CountEvent(CommanderID, BC.GSE_GLOBAL_DROPS)


func GlobalBuildings(CommanderID: int) -> void:
	CountEvent(CommanderID, BC.GSE_GLOBAL_BUILDINGS)


func GlobalSpells(CommanderID: int) -> void:
	CountEvent(CommanderID, BC.GSE_GLOBAL_SPELLS)


func GlobalSpawns(CommanderID: int) -> void:
	CountEvent(CommanderID, BC.GSE_GLOBAL_SPAWNS)


func GlobalKills(CommanderID: int) -> void:
	CountEvent(CommanderID, BC.GSE_GLOBAL_KILLS)


func GlobalDeaths(CommanderID: int) -> void:
	CountEvent(CommanderID, BC.GSE_GLOBAL_DEATHS)


func GlobalInstaDeaths(CommanderID: int) -> void:
	CountEvent(CommanderID, BC.GSE_GLOBAL_INSTADEATHS)


func GlobalInstaKills(CommanderID: int) -> void:
	CountEvent(CommanderID, BC.GSE_GLOBAL_INSTAKILLS)


func GlobalDamage(CommanderID: int, Times: int) -> void:
	CountEvent(CommanderID, BC.GSE_GLOBAL_GAIN_DAMAGE, Times)
