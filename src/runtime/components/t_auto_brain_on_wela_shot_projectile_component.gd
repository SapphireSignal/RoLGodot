class_name TAutoBrainOnWelaShotProjectileComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnWelaShotProjectileComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:572,
## implementation :2856), server only. At every eiWelaShotProjectile [Projectile] (epLast) fires eiFire at the shot
## projectile in its group if the brain can think and eiIsReady / eiWelaTargetPossible there allow.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWelaShotProjectile", C.eiWelaShotProjectile, C.epLast, C.etTrigger))


func OnWelaShotProjectile(Projectile) -> bool:
	if not CanThink():
		return true
	var Target := ATarget.Make(Projectile)
	if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)) and \
		_TargetsPossible(ATarget.ToRParam(Target), ComponentGroup):
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Target)], ComponentGroup)
	return true
