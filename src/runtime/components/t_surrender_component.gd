class_name TSurrenderComponent
extends TEntityComponent
## Port of TSurrenderComponent (GameServer/BaseConflict.EntityComponents.Server.pas:316, implementation :2472),
## server only, on the game entity: eiSurrender [TeamID] makes the team lose (in the tutorial always the PvE team):
## the game notes the surrender, then the team's nexus is killed, or eiLose is fired if it has none.
## The ClientCount parameter is unused, as in the original.

var FCanSurrender := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnSurrender", C.eiSurrender, C.epLast, C.etTrigger, C.esGlobal))


func Create(Owner = null, _ClientCount = 0) -> TEntityComponent:
	super(Owner)
	FCanSurrender = true
	return self


func OnSurrender(SurrenderingTeamID) -> bool:
	if FCanSurrender:
		var Game = GlobalEventbus().Game
		var SurrenderingTeam: int
		if Game.IsTutorial():
			SurrenderingTeam = C.PVE_TEAM_ID
		else:
			SurrenderingTeam = RParam.AsInteger(SurrenderingTeamID)
		Game.TeamSurrendered(SurrenderingTeam)
		var Nexus = Game.EntityManager.TryGetNexusByTeamID(SurrenderingTeam)
		if Nexus != null:
			Nexus.Eventbus.Trigger(C.eiKill, [-1, -1])
		else:
			GlobalEventbus().Trigger(C.eiLose, [SurrenderingTeam])
	return true
