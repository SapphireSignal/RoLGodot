class_name TGameDirectorComponent
extends TEntityComponent
## Port of TGameDirectorComponent (BaseConflict.EntityComponents.Shared.pas:59, implementation :2370), on the game
## entity (Game.GameDirector): named game events at game ticks (the scenario scripts add them, e.g. tech level 2 at
## tick 180). On the server each eiGameTick fires eiGameEvent [Name] for every due action, last added first, and
## drops it. eiGameEventTimeTo [Name] answers the ticks until the first pending action of that name, or -1.
## Event names are stored lower case.

var FActions: Array = []  # of [GameTick, Eventname]


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGameEventTimeTo", C.eiGameEventTimeTo, C.epFirst, C.etRead, C.esGlobal))
	if IsServerSide():
		e.append(XEvent("OnGameTick", C.eiGameTick, C.epHigh, C.etTrigger, C.esGlobal))


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	FActions = []
	super(Owner, Group)
	return self


func AddEvent(GameTick: int, Eventname: String) -> TGameDirectorComponent:
	FActions.append([GameTick, Eventname.to_lower()])
	return self


func AddEventIf(Condition: bool, GameTick: int, Eventname: String) -> TGameDirectorComponent:
	if Condition:
		AddEvent(GameTick, Eventname)
	return self


func ClearEvents() -> TGameDirectorComponent:
	FActions.clear()
	return self


func OnGameEventTimeTo(Eventname, _Previous):
	var Name := RParam.AsString(Eventname)
	var currentTick := RParam.AsInteger(GlobalEventbus().Read(C.eiGameTickCounter, []))
	for Action: Array in FActions:
		if Action[1] == Name and Action[0] >= currentTick:
			return Action[0] - currentTick
	return -1


func OnGameTick() -> bool:
	var Tick := RParam.AsInteger(GlobalEventbus().Read(C.eiGameTickCounter, []))
	for i in range(FActions.size() - 1, -1, -1):
		if Tick >= FActions[i][0]:
			var Action: Array = FActions[i]
			FActions.remove_at(i)
			GlobalEventbus().Trigger(C.eiGameEvent, [Action[1]])
	return true
