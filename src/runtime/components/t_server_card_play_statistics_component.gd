class_name TServerCardPlayStatisticsComponent
extends TEntityComponent
## Port of TServerCardPlayStatisticsComponent (GameServer/BaseConflict.EntityComponents.Server.pas:330,
## implementation :3307), server only. Sits on the commander with a card's group and counts every play of that
## card (eiUseAbility in its group, epLast): Game.Statistics.CardPlayed(commander, card script file).

var FScriptFile := ""


func CreateGrouped(Owner = null, Group = [], ScriptFile = "") -> TEntityComponent:
	super(Owner, Group)
	FScriptFile = ScriptFile
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnUseAbility", C.eiUseAbility, C.epLast, C.etTrigger))


func OnUseAbility(_Targets) -> bool:
	# cards are components of the commander so: Owner = Commander
	GlobalEventbus().Game.Statistics.CardPlayed(Owner.ID, FScriptFile)
	return true
