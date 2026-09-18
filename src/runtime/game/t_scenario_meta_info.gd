class_name TScenarioMetaInfo
extends TObject
## Port of TScenarioMetaInfo (BaseConflict.Constants.Scenario.pas:15, implementation :140): a scenario's scripts
## and map. The scripts are applied last to first (TGame.Initialize).

var ScenarioScriptfile: Array = []  # of String
var MapName := ""


func Create() -> TScenarioMetaInfo:
	ScenarioScriptfile = []
	return self


func Clone() -> TScenarioMetaInfo:
	var Result := TScenarioMetaInfo.new().Create()
	Result.ScenarioScriptfile.append_array(ScenarioScriptfile)
	Result.MapName = MapName
	return Result
