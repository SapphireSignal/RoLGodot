class_name TWelaHelperInitActiveAfterGameStartComponent
extends TEntityComponent
## Port of TWelaHelperInitActiveAfterGameStartComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:794,
## implementation :2742), server only. Created before the game runs (and its group active or unset), it writes
## eiWelaActive := False to its group, then at the first global eiGameTick := True (unless
## DisableOnReachResourceCap's resource is at its cap in the check group) and frees itself. Created while the
## game is playing, or with the group already inactive, it does nothing but free itself at the first game tick.
## Port: without a Game (tests) the game counts as not playing.

const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FDisableOnReachResourceCap := C.reNone
var FCheckGroup: Array = []
var FDisabled := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGameTick", C.eiGameTick, C.epLast, C.etTrigger, C.esGlobal))


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	var game = GlobalEventbus().Game
	var state: bool = game != null and game.IngameStatus == BC.gsPlaying
	if state or not RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiWelaActive, [], ComponentGroup)):
		FDisabled = true
	else:
		Eventbus().Write(C.eiWelaActive, [false], ComponentGroup)
	return self


func DisableOnReachResourceCap(Resource: int = 0, Group = []) -> TWelaHelperInitActiveAfterGameStartComponent:
	FDisableOnReachResourceCap = Resource
	FCheckGroup = DSet.Make(Group)
	return self


## Activate this weapon.
func OnGameTick() -> bool:
	if not FDisabled:
		var Condition := true
		if FDisableOnReachResourceCap != C.reNone:
			var Balance = Eventbus().Read(C.eiResourceBalance, [FDisableOnReachResourceCap], FCheckGroup)
			var Cap = Eventbus().Read(C.eiResourceCap, [FDisableOnReachResourceCap], FCheckGroup)
			Condition = Condition and not RParam.Equal(Balance, Cap)
		if Condition:
			Eventbus().Write(C.eiWelaActive, [true], ComponentGroup)
	Free()
	return true
