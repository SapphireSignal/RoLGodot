class_name TAutoBrainOnCreateComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnCreateComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:606,
## implementation :2950), server only. At eiAfterCreate (epLast) runs CheckAndFire (default target: the owner);
## OnlyAfterGameStart / OnlyBeforeGameStart: only if the global eiGameTickTimeToFirstTick is <= 0 / > 0 (the game's
## tick component answers it; empty reads 0 = started).

var FOnlyAfterGameStart := false
var FOnlyBeforeGameStart := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))


func OnAfterCreate() -> bool:
	if (not FOnlyAfterGameStart or RParam.AsInteger(GlobalEventbus().Read(C.eiGameTickTimeToFirstTick, [])) <= 0) and \
		(not FOnlyBeforeGameStart or RParam.AsInteger(GlobalEventbus().Read(C.eiGameTickTimeToFirstTick, [])) > 0):
		CheckAndFire()
	return true


func OnlyAfterGameStart() -> TAutoBrainOnCreateComponent:
	FOnlyAfterGameStart = true
	return self


func OnlyBeforeGameStart() -> TAutoBrainOnCreateComponent:
	FOnlyBeforeGameStart = true
	return self
