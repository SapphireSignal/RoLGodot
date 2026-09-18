class_name TAutoBrainOnWelaHitByProjectileComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnWelaHitByProjectileComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:582,
## implementation :3087), server only. At every eiWelaHitByProjectile [Projectile] (epLast) fires eiFire at the
## projectile in its group if the brain can think and eiIsReady / eiWelaTargetPossible there allow.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWelaHitByProjectile", C.eiWelaHitByProjectile, C.epLast, C.etTrigger))


func OnWelaHitByProjectile(Projectile) -> bool:
	if not CanThink():
		return true
	var Target := ATarget.Make(Projectile)
	if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)) and \
		_TargetsPossible(ATarget.ToRParam(Target), ComponentGroup):
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Target)], ComponentGroup)
	return true
