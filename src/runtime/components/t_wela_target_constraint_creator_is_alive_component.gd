class_name TWelaTargetConstraintCreatorIsAliveComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintCreatorIsAliveComponent (BaseConflict.EntityComponents.Shared.Wela.pas:439,
## implementation :3185). Only entities whose creator (eiCreator) still exists.


func IsPossible(Target: RTarget) -> bool:
	var game = TargetGame()
	var TargetEntity = Target.GetTargetEntity(game)
	if TargetEntity == null:
		return false
	return game.EntityManager.HasEntityByID(RParam.AsInteger(TargetEntity.Eventbus.Read(C.eiCreator, [])))
