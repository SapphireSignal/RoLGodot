class_name TServerPrimaryTargetComponent
extends TPrimaryTargetComponent
## Port of TServerPrimaryTargetComponent (GameServer/BaseConflict.EntityComponents.Server.pas:139, implementation
## :1072), server only. When its owner (the nexus) dies (eiDie, epFirst) the owning team loses: global eiLose
## [TeamID]. Before that, when the owner is a base (upBase), every enemy commander with upHasEchoesOfTheFuture
## counts wela_kills_basebuildingwhileeotfactive (counted here because the game shuts down after eiLose).
## Returns false: the rest of the eiDie handlers never run for a nexus.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnDie", C.eiDie, C.epFirst, C.etTrigger))


func OnDie(_KillerID, _KillerCommanderID) -> bool:
	var Game = GlobalEventbus().Game
	# have to be triggered manually as after eiLose the game is shut down
	for Commander in Game.Commanders:
		if Owner.HasUnitProperty(C.upBase) and Commander.TeamID() != Owner.TeamID() \
				and Commander.HasUnitProperty(C.upHasEchoesOfTheFuture):
			Game.Statistics.WelaKills(Commander.ID, "basebuildingwhileeotfactive", 1)
	# finish
	GlobalEventbus().Trigger(C.eiLose, [Owner.TeamID()])
	return false
