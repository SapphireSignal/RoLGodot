class_name TServerSandboxComponent
extends TGDEntityComponent
## Port of TServerSandboxComponent (GameServer/BaseConflict.EntityComponents.Server.pas:435, implementation :3462),
## server only. Adds infinite resources to all commanders: at the global eiGameCommencing every commander's gold cap
## grows by 100000 (without filling it), then +100000 gold and +10000 wood; then the tech level 2 and 3 game events.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGameCommencing", C.eiGameCommencing, C.epLast, C.etTrigger, C.esGlobal))


func OnGameCommencing() -> bool:
	var ServerGame = GlobalEventbus().Game
	if ServerGame != null:
		for Commander: TEntity in ServerGame.Commanders:
			Commander.Eventbus.Trigger(C.eiResourceCapTransaction, [C.reGold, 100000.0, true])
			Commander.Eventbus.Trigger(C.eiResourceTransaction, [C.reGold, 100000.0])
			Commander.Eventbus.Trigger(C.eiResourceTransaction, [C.reWood, 10000.0])
	GlobalEventbus().Trigger(C.eiGameEvent, [C.GAME_EVENT_TECH_LEVEL_2])
	GlobalEventbus().Trigger(C.eiGameEvent, [C.GAME_EVENT_TECH_LEVEL_3])
	return true
