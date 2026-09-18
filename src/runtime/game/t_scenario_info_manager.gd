class_name TScenarioInfoManager
extends TObject
## Port of TScenarioInfoManager (BaseConflict.Constants.Scenario.pas:48, implementation :226) and its unit
## initialization (:303): every scenario UID with its scripts and map, per league, and the mutators.
## Port note: the original's global ScenarioInfoManager is Instance() (built on first use).
## Where the original asserts (unknown UID or league), push_error and return null.

const BC = preload("res://src/runtime/base_conflict_constants.gd")
const PVP_SCENARIO_SCRIPTS = ["PvPBase.dws", "PvPRed.dws", "PvPBlue.dws", "Game.dws"]

static var _Instance: TScenarioInfoManager = null

var FServerScenarioMapping := {}  # ScenarioUID -> (League -> TScenarioMetaInfo)
var FServerMutatorMapping := {}  # MutatorUID -> TMutatorMetaInfo


static func Instance() -> TScenarioInfoManager:
	if _Instance == null:
		_Instance = TScenarioInfoManager.new().Create()
		_Instance._RegisterAll()
	return _Instance


func Create() -> TScenarioInfoManager:
	FServerScenarioMapping = {}
	FServerMutatorMapping = {}
	return self


## s(): a scenario from script names (in Scripts\Scenarios\) and a map.
static func s(ScenarioScriptfiles: Array, MapName: String) -> TScenarioMetaInfo:
	var Result := TScenarioMetaInfo.new().Create()
	Result.MapName = MapName
	for ScriptFile: String in ScenarioScriptfiles:
		Result.ScenarioScriptfile.append(BC.PATH_SCRIPT_SCENARIO + ScriptFile)
	return Result


## m(): a mutator from script names (in Scripts\Scenarios\Mutators\).
static func m(MutatorScriptfiles: Array) -> TMutatorMetaInfo:
	var Result := TMutatorMetaInfo.new().Create()
	for ScriptFile: String in MutatorScriptfiles:
		Result.MutatorScriptfile.append(BC.PATH_SCRIPT_SCENARIO_MUTATOR + ScriptFile)
	return Result


func AddMutator(MutatorUID: String, MutatorInfo: TMutatorMetaInfo) -> void:
	FServerMutatorMapping[MutatorUID] = MutatorInfo


## PvP scenarios all share the same files and exist for every league.
func AddPvPScenario(ScenarioUID: String, AdditionalScripts: Array, MapName: String) -> void:
	AddScenarioForAllLeagues(ScenarioUID, s(AdditionalScripts + PVP_SCENARIO_SCRIPTS, MapName))


func AddScenario(ScenarioUID: String, League: int, MetaInfo: TScenarioMetaInfo) -> void:
	if not FServerScenarioMapping.has(ScenarioUID):
		FServerScenarioMapping[ScenarioUID] = {}
	FServerScenarioMapping[ScenarioUID][League] = MetaInfo


func AddScenarioForAllLeagues(ScenarioUID: String, MetaInfo: TScenarioMetaInfo) -> void:
	for i in range(1, BC.MAX_LEAGUE + 1):
		AddScenario(ScenarioUID, i, MetaInfo.Clone())


func ResolveScenario(ScenarioUID: String, League: int) -> TScenarioMetaInfo:
	var Key := ScenarioUID.to_lower()
	if not FServerScenarioMapping.has(Key):
		push_error("HScenario.ResolveScenario: Could not find scenario UID " + ScenarioUID)
		return null
	if not FServerScenarioMapping[Key].has(League):
		push_error("HScenario.ResolveScenario: Could not find league %d in scenario with UID %s" % [League, ScenarioUID])
		return null
	return FServerScenarioMapping[Key][League]


func ResolveMutator(MutatorUID: String) -> TMutatorMetaInfo:
	var Key := MutatorUID.to_lower()
	if not FServerMutatorMapping.has(Key):
		push_error("TScenarioInfoManager.ResolveMutator: unknown mutator " + MutatorUID)
		return null
	return FServerMutatorMapping[Key]


## The unit initialization. ATTENTION (original): the order of the scripts is important, they are loaded from right
## to left.
func _RegisterAll() -> void:
	AddPvPScenario(BC.SCENARIO_SANDBOX_UID, ["Sandbox.dws"], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_SANDBOX_DUO_UID, ["Sandbox.dws"], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_SANDBOX_CLASSIC_UID, ["Sandbox.dws"], BC.MAP_DOUBLE)

	AddPvPScenario(BC.SCENARIO_PVP_DUEL_1VS1, [], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PVP_DUEL_1VS1_TWO_LANE, [], BC.MAP_DOUBLE)
	AddPvPScenario(BC.SCENARIO_PVP_DUEL_2VS2, [], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PVP_DUEL_2VS2_TWO_LANE, [], BC.MAP_DOUBLE)
	AddPvPScenario(BC.SCENARIO_PVP_DUEL_3VS3, [], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PVP_DUEL_3VS3_TWO_LANE, [], BC.MAP_DOUBLE)
	AddPvPScenario(BC.SCENARIO_PVP_DUEL_4VS4, [], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PVP_DUEL_4VS4_TWO_LANE, [], BC.MAP_DOUBLE)
	AddPvPScenario(BC.SCENARIO_PVP_1VS1, [], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PVP_1VS1_TWO_LANE, [], BC.MAP_DOUBLE)
	AddPvPScenario(BC.SCENARIO_PVP_2VS2, [], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PVP_2VS2_TWO_LANE, [], BC.MAP_DOUBLE)
	AddPvPScenario(BC.SCENARIO_PVP_3VS3, [], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PVP_3VS3_TWO_LANE, [], BC.MAP_DOUBLE)
	AddPvPScenario(BC.SCENARIO_PVP_4VS4, [], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PVP_4VS4_TWO_LANE, [], BC.MAP_DOUBLE)

	AddPvPScenario(BC.SCENARIO_PVP_1VS1_RANKED, [], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PVP_2VS2_RANKED, [], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PVP_3VS3_RANKED, [], BC.MAP_DOUBLE)
	AddPvPScenario(BC.SCENARIO_PVP_4VS4_RANKED, [], BC.MAP_DOUBLE)

	AddScenario(BC.SCENARIO_PVE_TUTORIAL, 1, s(["TutorialVeryEasy.dws", "Game.dws"], BC.MAP_SINGLE))

	var Difficulties := ["VeryEasy", "Easy", "Medium", "Hard", "VeryHard"]
	for i in 5:
		AddScenario(BC.SCENARIO_PVE_ATTACK_SOLO, i + 1, s(["AttackScenario%s.dws" % Difficulties[i],
			"AttackScenarioBase.dws", "Game.dws"], BC.MAP_SINGLE))
	for i in 5:
		AddScenario(BC.SCENARIO_PVE_ATTACK_DUO, i + 1, s(["AttackDuoScenario%s.dws" % Difficulties[i],
			"AttackDuoScenarioBase.dws", "Game.dws"], BC.MAP_DOUBLE))
	for i in 5:
		AddScenario(BC.SCENARIO_PVE_DEFAULT_PREFIX + BC.SCENARIO_SANDBOX_UID, i + 1, s(["Sandbox.dws",
			"SandboxAttackScenario%s.dws" % Difficulties[i], "SandboxAttackScenarioBase.dws", "Game.dws"], BC.MAP_SINGLE))
	for i in 5:
		AddScenario(BC.SCENARIO_PVE_DEFAULT_PREFIX + BC.SCENARIO_SANDBOX_CLASSIC_UID, i + 1, s(["Sandbox.dws",
			"SandboxAttackDuoScenario%s.dws" % Difficulties[i], "SandboxAttackDuoScenarioBase.dws", "Game.dws"],
			BC.MAP_DOUBLE))

	# debug scenarios
	AddPvPScenario(BC.SCENARIO_DEBUG_UID, ["Debug.dws"], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PVP_TEST_UID, ["PvPBase.dws"], BC.MAP_SINGLE)
	AddPvPScenario(BC.SCENARIO_PERFORMANCE_TEST, ["PerformanceTest.dws"], BC.MAP_SINGLE)
	AddScenario(BC.SCENARIO_PVE_DEFAULT_PREFIX + "core_test_1", 5, s(["CoreTest1.dws", "Game.dws"], BC.MAP_SINGLE))
	AddScenario(BC.SCENARIO_PVE_DEFAULT_PREFIX + "core_test_2", 5, s(["CoreTest2.dws", "Game.dws"], BC.MAP_SINGLE))
	AddScenario(BC.SCENARIO_PVE_DEFAULT_PREFIX + "core_test_3", 5, s(["CoreTest3.dws", "Game.dws"], BC.MAP_SINGLE))

	AddMutator("highly_explosive", m(["HighlyExplosive.dws"]))
	AddMutator("gigantic", m(["Gigantic.dws"]))
