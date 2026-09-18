class_name TMutatorMetaInfo
extends TObject
## Port of TMutatorMetaInfo (BaseConflict.Constants.Scenario.pas:25, implementation :159): a mutator's scripts.

var MutatorScriptfile: Array = []  # of String


func Create() -> TMutatorMetaInfo:
	MutatorScriptfile = []
	return self
