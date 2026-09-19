class_name TAutoBrainOnTakeDamageComponent
extends TAutoBrainBilateralComponent
## Port of TAutoBrainOnTakeDamageComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:654,
## implementation :2595), server only. On eiTakeDamage [var Amount, DamageType, InflictorID] (read, epFirst;
## TriggersAfterDamage: epLast; groupless reads only), if the brain can think and eiIsReady of its group allows:
## resolves a projectile / link inflictor to its creator, asks eiWelaTriggerCheck [Amount, DamageType, inflictor]
## of its group (empty = pass), then (ModifiesAmount: Amount × eiWelaModifier first) runs the bilateral Fire with
## the inflictor as target. Answers the previous value.


var FModifiesAmount := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnTakeDamage", C.eiTakeDamage, C.epFirst, C.etRead))


func ModifiesAmount() -> TAutoBrainOnTakeDamageComponent:
	FModifiesAmount = true
	return self


func TriggersAfterDamage() -> TAutoBrainOnTakeDamageComponent:
	ChangeEventPriority(C.eiTakeDamage, C.etRead, C.epLast)
	return self


func OnTakeDamage(Amount, DamageType, InflictorID, Previous):
	var Result = Previous
	if not CanThink() or not TEventbus.GetCurrentEvent_CalledToGroup().is_empty():
		return Result
	var Ready := RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup))
	if Ready:
		var TargetEntityID := RParam.AsInteger(InflictorID)
		# resolve projectile owner
		var game = BrainGame()
		var Entity = game.EntityManager.TryGetEntityByID(RParam.AsInteger(InflictorID)) if game != null else null
		if Entity != null:
			if DSet.Intersects(Entity.UnitProperties(), DSet.Make([C.upProjectile, C.upLink])):
				var Creator = game.EntityManager.TryGetEntityByID(RParam.AsInteger(Entity.Eventbus.Read(C.eiCreator, [])))
				if Creator != null:
					TargetEntityID = Creator.ID
		if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiWelaTriggerCheck, [Amount, DamageType, TargetEntityID],
			ComponentGroup)):
			if FModifiesAmount:
				SetVarParam(0, RParam.ToSingle(RParam.AsSingle(Amount)
					* RParam.AsSingle(Eventbus().Read(C.eiWelaModifier, [], ComponentGroup))))
			Fire(ATarget.Make(TargetEntityID))
	return Result
