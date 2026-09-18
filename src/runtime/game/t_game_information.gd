class_name TGameInformation
extends TObject
## Port of TGameInformation (BaseConflict.Game.pas:27, implementation :296): the scenario of a game (UID, its meta
## info), its league (aka difficulty) and mutators.

var ScenarioUID := ""
var Scenario: TScenarioMetaInfo = null
var League := 0
var Mutators: Array = []  # of TMutatorMetaInfo
var IsSandboxOverride := false


func Create() -> TGameInformation:
	Mutators = []
	return self


func IsSandbox() -> bool:
	return HScenario.IsSandbox(ScenarioUID) or IsSandboxOverride


func IsTutorial() -> bool:
	return HScenario.IsTutorial(ScenarioUID)


func IsPvE() -> bool:
	return HScenario.IsPvEScenario(ScenarioUID)


func IsPvP() -> bool:
	return HScenario.IsPvP(ScenarioUID)


func IsSingle() -> bool:
	return HScenario.IsSingle(ScenarioUID)


func IsDuo() -> bool:
	return HScenario.IsDuo(ScenarioUID)


func IsTeamMode() -> bool:
	return HScenario.IsTeamMode(ScenarioUID)
