class_name TBrainApproachComponent
extends TBrainComponent
## Port of TBrainApproachComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:237,
## implementation :1565), server only. Approaches the next target its group's targeting finds: when the wela is
## ready, every chain (epLow) triggers eiWelaUpdateTargets on a fresh list; with a target it consumes the thought
## and, if it can move and the target is farther than range = eiWelaRange + own radius (+ the target entity's
## radius) - 0.1, sends eiMoveTo [target, range]; within range it stands (if it was approaching). No target or
## weapon not ready: stands if it was approaching, the chain goes on.

const ERROR_EPSILON = 0.1

var FApproaching := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epLow, C.etTrigger))


func OnThinkChain() -> bool:
	return ThinkChainEvent()


func ThinkChain() -> bool:
	var Result := true
	if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)):
		var TargetList: Array = []
		# look for an enemy to approach, done every think, because other entities can pass the current target
		Eventbus().Trigger(C.eiWelaUpdateTargets, [TargetList], ComponentGroup)
		# approach to enemy in weaponrange
		if TargetList.size() > 0:
			Result = false
			var game = BrainGame()
			var First: RTarget = TargetList[0]
			# approach correctly to the border of the enemy (+0.1 rounding fix)
			var MoveRange := RParam.ToSingle(RParam.AsSingle(Eventbus().Read(C.eiWelaRange, [], ComponentGroup))
				+ Owner.CollisionRadius)
			if First.IsEntity():
				MoveRange = RParam.ToSingle(MoveRange + First.GetTargetEntity(game).CollisionRadius)
			MoveRange = RParam.ToSingle(MoveRange - ERROR_EPSILON)
			if CanMove():
				if MoveRange < First.GetTargetPosition(game).distance_to(Owner.Position):
					Eventbus().Trigger(C.eiMoveTo, [First, MoveRange])
					FApproaching = true
				else:
					if FApproaching:
						Eventbus().Trigger(C.eiStand, [])
					FApproaching = false
		else:
			if FApproaching:
				Eventbus().Trigger(C.eiStand, [])
			FApproaching = false
	else:
		if FApproaching:
			Eventbus().Trigger(C.eiStand, [])
		FApproaching = false
	return Result
