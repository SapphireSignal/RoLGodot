class_name TWelaTargetConstraintCardNameComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintCardNameComponent (BaseConflict.EntityComponents.Shared.Wela.pas:428,
## implementation :2666). Only entities whose script file name starts with one of the added names (case ignored).

var FCards: Array = []  # of String


func IsPossible(Target: RTarget) -> bool:
	var Result := false
	var Entity = Target.TryGetTargetEntity(TargetGame()) if Target.IsEntity() else null
	if Entity != null:
		var Name: String = Entity.ScriptFileName().to_lower()
		for Card in FCards:
			Result = Result or Name.begins_with(Card.to_lower())
	return Result


func AddCard(ScriptFileName: String) -> TWelaTargetConstraintCardNameComponent:
	FCards.append(ScriptFileName)
	return self
