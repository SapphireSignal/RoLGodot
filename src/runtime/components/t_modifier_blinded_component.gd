class_name TModifierBlindedComponent
extends TModifierComponent
## Port of TModifierBlindedComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:754, implementation
## :3050), server only. A blinded unit misses half its shots: each eiFire (epFirst) called to a group meeting the value
## group rolls (random <= 0.5 misses; a miss fires eiFire [owner] in SetFireGroup's group); while the last roll
## missed, every eiFireWarhead (epFirst) the component sees is stopped and every projectile it hears of
## (eiWelaShotProjectile, epMiddle) gets upProjectileWillMiss (straight into its blackboard).
## A groupless eiFire never rolls; the last roll stays in force until the next one (also for later warheads).

const BLIND_CHANCE = 0.5

var FWillMiss := false
var FFireGroup: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnFire", C.eiFire, C.epFirst, C.etTrigger))
	e.append(XEvent("OnFireWarhead", C.eiFireWarhead, C.epFirst, C.etTrigger))
	e.append(XEvent("OnWelaShotProjectile", C.eiWelaShotProjectile, C.epMiddle, C.etTrigger))


func SetFireGroup(Group: Array) -> TModifierBlindedComponent:
	FFireGroup = DSet.Make(Group)
	return self


## Roll the miss dice.
func OnFire(_Targets) -> bool:
	if not DSet.Intersects(TEventbus.CurrentEvent_CalledToGroup, FValueGroup):
		return true
	FWillMiss = randf() <= BLIND_CHANCE
	if FWillMiss:
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Owner))], FFireGroup)
	return true


## Consumes the event by a chance.
func OnFireWarhead(_Targets) -> bool:
	return not FWillMiss


## Marks the projectile to miss if the last fire determined to miss.
func OnWelaShotProjectile(Projectile) -> bool:
	if FWillMiss:
		# get/set value direct in blackboard, as we don't want to save temporary properties introduced by components as
		# permanent
		var TargetUnitProperties := RParam.AsSet(Projectile.Blackboard.GetValue(C.eiUnitProperties, []))
		TargetUnitProperties = DSet.Make(TargetUnitProperties + [C.upProjectileWillMiss])
		Projectile.Blackboard.SetValue(C.eiUnitProperties, [], TargetUnitProperties)
	return true
