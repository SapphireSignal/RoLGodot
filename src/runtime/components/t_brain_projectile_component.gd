class_name TBrainProjectileComponent
extends TBrainComponent
## Port of TBrainProjectileComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:429,
## implementation :1825), server only. The movement "brain" of a projectile. At eiAfterCreate (epLast) it takes its
## one target from eiWelaSavedTargets (written by the spawning wela; SetNotFollowingTarget turns an entity target
## into the ground where it stands and saves that): an empty or dead target kills the projectile
## (eiDelayedKillEntity), SetInstant fires at once and dies, else it sends eiMoveTo [target, 0] (DieWithTarget: it
## also dies with its target entity, through the target's eiDie). On eiMoveTargetReached it fires (unless
## SetOnlyFollowing): eiFire at the saved targets in its group if the owner is not upProjectileWillMiss and
## (NoTargetChecks or eiIsReady and eiWelaTargetPossible), then eiWelaHitByProjectile [projectile] on every target
## entity. A hit enemy with upProjectileReflector (unless CantBeReflected) sends it back to its creator in the
## reflector's team; Bounces(Group) jumps to the next target the group's targeting finds (not hitting a target
## twice: they are collected in eiWelaSavedTargets of the group) while ready and fewer than eiWelaCount bounces;
## otherwise it dies. Retargeting starts moving on the next server Idle (a delayed event after 0 ms).
## SetOnlyFollowing projectiles re-send eiMoveTo at every chain (epLast) and never fire.
## Port note: without GlobalEventbus().Game.DelayedEvents (tests) a retargeted projectile does not move on.

var FBounceCount := 0
var FNotHoming := false
var FInstant := false
var FOnlyFollowing := false
var FDieWithTarget := false
var FNoTargetChecks := false
var FBounces := false
var FNoReflection := false
var FBounceTargetGroup: Array = []
var FDelayedEvent: TDelayedEventHandler = null


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnMoveTargetReached", C.eiMoveTargetReached, C.epLast, C.etTrigger))
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epLast, C.etTrigger))


func Destroy() -> void:
	if FDelayedEvent != null:
		FDelayedEvent.Free()
		FDelayedEvent = null
	super()


func Bounces(TargetGroup: Array) -> TBrainProjectileComponent:
	FBounces = true
	FBounceTargetGroup = DSet.Make(TargetGroup)
	return self


func CantBeReflected() -> TBrainProjectileComponent:
	FNoReflection = true
	return self


func DieWithTarget() -> TBrainProjectileComponent:
	FDieWithTarget = true
	return self


func NoTargetChecks() -> TBrainProjectileComponent:
	FNoTargetChecks = true
	return self


func SetInstant() -> TBrainProjectileComponent:
	FInstant = true
	return self


func SetNotFollowingTarget() -> TBrainProjectileComponent:
	FNotHoming = true
	return self


func SetOnlyFollowing() -> TBrainProjectileComponent:
	FOnlyFollowing = true
	return self


func _SavedTargets(Group: Array = []) -> Array:
	return ATarget.FromRParam(Eventbus().Read(C.eiWelaSavedTargets, [], Group)).duplicate()


func FireAtTarget(Targets: Array) -> bool:
	# fire only if all tests passes
	var Result: bool = not Owner.UnitProperties().has(C.upProjectileWillMiss) and \
		(FNoTargetChecks or (RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)) and
		_TargetsPossible(ATarget.ToRParam(Targets), ComponentGroup)))
	if Result:
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Targets)], ComponentGroup)
		var game = BrainGame()
		for Target: RTarget in Targets:
			var TargetEntity = Target.TryGetTargetEntity(game)
			if TargetEntity != null:
				TargetEntity.Eventbus.Trigger(C.eiWelaHitByProjectile, [Owner])
	return Result


func InitiateOnSavedTarget() -> void:
	var CurrentTargets := _SavedTargets()
	if CurrentTargets.size() > 0:
		Eventbus().Trigger(C.eiMoveTo, [CurrentTargets[0], 0.0])


## Starts moving to the (new) saved target on the next server Idle.
func _RetargetDelayed() -> void:
	if FDelayedEvent != null:
		FDelayedEvent.Free()
	FDelayedEvent = TDelayedEventHandler.new().Create(InitiateOnSavedTarget)
	var game = BrainGame()
	var Queue = game.get("DelayedEvents") if game != null else null
	if Queue != null:
		FDelayedEvent.RegisterEvent(0, Queue)


func OnMoveTargetReached() -> bool:
	if not FOnlyFollowing:
		var CurrentTargets := _SavedTargets()
		var Hit := FireAtTarget(CurrentTargets)
		var game = BrainGame()

		# if target reflects projectiles apply it here
		if Hit and not FNoReflection:
			for Target: RTarget in CurrentTargets:
				var ReflectingEntity = Target.TryGetTargetEntity(game)
				if ReflectingEntity != null and ReflectingEntity.TeamID() != Owner.TeamID() and \
					ReflectingEntity.HasUnitProperty(C.upProjectileReflector):
					# reflect projectile to creator, it changes team id to the reflectors one
					var Creator = game.EntityManager.TryGetEntityByID(
						RParam.AsInteger(Eventbus().Read(C.eiCreator, [])))
					if Creator != null:
						FNoReflection = true
						Owner.Eventbus.Write(C.eiTeamID, [ReflectingEntity.TeamID()])
						CurrentTargets = ATarget.Make(Creator)
						Eventbus().Write(C.eiWelaSavedTargets, [ATarget.ToRParam(CurrentTargets)])
						_RetargetDelayed()
					else:
						SelfDestruct()
					return true

		# apply bouncing
		if Hit and FBounces and IsWelaReady() and \
			FBounceCount < RParam.AsInteger(Eventbus().Read(C.eiWelaCount, [], ComponentGroup)):
			# add all targets hit to the blacklist, so it won't bounce to them again
			var HitTargets := _SavedTargets(FBounceTargetGroup)
			ATarget.Append(HitTargets, CurrentTargets)
			Eventbus().Write(C.eiWelaSavedTargets, [ATarget.ToRParam(HitTargets)], FBounceTargetGroup)
			# now search for targets
			var TargetList: Array = []
			Eventbus().Trigger(C.eiWelaUpdateTargets, [TargetList], FBounceTargetGroup)
			# if targets found, set new target, else kill projectile
			if TargetList.size() > 0:
				CurrentTargets = ATarget.Make(TargetList[0])
				Eventbus().Write(C.eiWelaSavedTargets, [ATarget.ToRParam(CurrentTargets)])
				FBounceCount += 1
				_RetargetDelayed()
			else:
				SelfDestruct()
		else:
			SelfDestruct()
	return true


func OnAfterCreate() -> bool:
	var game = BrainGame()
	var Targets := _SavedTargets()
	if Targets.size() != 1:
		MakeException(".OnSetTarget: Projectiles expect exactly one target!")
	var Targeti: RTarget = Targets[0].Clone() if Targets.size() > 0 else RTarget.CreateEmpty()
	if Targeti.IsEntity() and FNotHoming:
		Targeti = RTarget.Create(Targeti.GetTargetPosition(game))
		Targets[0] = Targeti
		# save targets as we changed the first to a ground target
		Eventbus().Write(C.eiWelaSavedTargets, [ATarget.ToRParam(Targets)])
	# if target is empty or not valid, we stifle the projectile as it would be never spawned
	if Targeti.IsEmpty() or (Targeti.IsEntity() and not Targeti.IsEntityValid(game)):
		SelfDestruct()
	elif FInstant:
		# if spell should explode instant, don't move to target
		FireAtTarget(Targets)
		SelfDestruct()
	else:
		# fill RTarget position cache, if unit dies in this frame
		Targeti.GetTargetPosition(game)
		Eventbus().Trigger(C.eiMoveTo, [Targeti, 0.0])
		if FDieWithTarget and Targeti.IsEntity():
			var TargetEntity = Targeti.TryGetTargetEntity(game)
			if TargetEntity != null:
				TargetEntity.Eventbus.SubscribeRemote(C.eiDie, C.etTrigger, C.epLast, self, "TargetOnDie", 2)
	return true


func OnThinkChain() -> bool:
	return ThinkChainEvent()


func SelfDestruct() -> void:
	GlobalEventbus().Trigger(C.eiDelayedKillEntity, [FOwner.ID])


func TargetOnDie(_KillerID, _KillerCommanderID) -> bool:
	Eventbus().Trigger(C.eiDie, [-1, -1])
	return true


func ThinkChain() -> bool:
	if FOnlyFollowing:
		Eventbus().Trigger(C.eiMoveTo, [ATarget.First(_SavedTargets()), 0.0])
	return true
