class_name HScenario
extends RefCounted
## Port of HScenario (BaseConflict.Constants.Scenario.pas:32, implementation :171): what a scenario UID is (PvP,
## PvE, duo, sandbox...), by its name, and the lookups in TScenarioInfoManager.

const BC = preload("res://src/runtime/base_conflict_constants.gd")


static func ResolveScenario(ScenarioUID: String, League: int) -> TScenarioMetaInfo:
	return TScenarioInfoManager.Instance().ResolveScenario(ScenarioUID, League)


static func ResolveMutator(MutatorUID: String) -> TMutatorMetaInfo:
	return TScenarioInfoManager.Instance().ResolveMutator(MutatorUID)


static func IsDuel(ScenarioUID: String) -> bool:
	return ScenarioUID.contains(BC.SCENARIO_PVP_DUEL_PREFIX)


static func IsDuo(ScenarioUID: String) -> bool:
	return ScenarioUID.ends_with(BC.SCENARIO_PVP_2VS2) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_3VS3) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_4VS4) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_DUEL_2VS2) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_DUEL_2VS2_TWO_LANE) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_DUEL_3VS3) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_DUEL_3VS3_TWO_LANE) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_DUEL_4VS4) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_DUEL_4VS4_TWO_LANE) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVE_ATTACK_DUO) or \
		ScenarioUID.ends_with(BC.SCENARIO_SANDBOX_DUO_UID)


static func IsPvEScenario(ScenarioUID: String) -> bool:
	return ScenarioUID.contains(BC.SCENARIO_PVE_DEFAULT_PREFIX) or ScenarioUID.contains(BC.SCENARIO_PVE_TUTORIAL)


static func IsPvP(ScenarioUID: String) -> bool:
	return ScenarioUID.ends_with(BC.SCENARIO_PVP_1VS1) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_2VS2) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_3VS3) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_4VS4) or \
		IsDuel(ScenarioUID) or \
		ScenarioUID.ends_with(BC.SCENARIO_SANDBOX_UID) or \
		ScenarioUID.ends_with(BC.SCENARIO_SANDBOX_DUO_UID) or \
		ScenarioUID.ends_with(BC.SCENARIO_SANDBOX_CLASSIC_UID)


static func IsSandbox(ScenarioUID: String) -> bool:
	return ScenarioUID.contains(BC.SCENARIO_SANDBOX_UID)


static func IsSingle(ScenarioUID: String) -> bool:
	return not IsDuo(ScenarioUID)


static func IsTeamMode(ScenarioUID: String) -> bool:
	return ScenarioUID.ends_with(BC.SCENARIO_PVP_2VS2) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_3VS3) or \
		ScenarioUID.ends_with(BC.SCENARIO_PVP_4VS4) or \
		(ScenarioUID.contains(BC.SCENARIO_PVP_DUEL_PREFIX) and \
		not ScenarioUID.ends_with(BC.SCENARIO_PVP_DUEL_1VS1) and \
		not ScenarioUID.ends_with(BC.SCENARIO_PVP_DUEL_1VS1_TWO_LANE)) or \
		ScenarioUID.ends_with(BC.SCENARIO_SANDBOX_DUO_UID) or \
		ScenarioUID.ends_with(BC.SCENARIO_SANDBOX_CLASSIC_UID)


static func IsTutorial(ScenarioUID: String) -> bool:
	return ScenarioUID.contains(BC.SCENARIO_PVE_TUTORIAL)
