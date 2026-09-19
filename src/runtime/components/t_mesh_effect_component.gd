class_name TMeshEffectComponent
extends TEntityComponent
## Port of TMeshEffectComponent (BaseConflict.EntityComponents.Client.Visuals.pas:989, implementation :5751): gives
## its effects (clones, one per mesh) to the meshes of its target group when triggered: on die, fire, pre-fire, lose
## (its team), a produced unit (to that unit), at once otherwise. As written, SetEffect applies the effect at once
## unless the component waits for die or fire: ActivateOnLose / OnPreFire / OnWelaUnitProduced effects run at
## creation too. Effects it gave are managed (removed from the meshes when it is freed); fire-target effects are not.

## TMeshComponent -> Array of the effects given to it
var FEffects := {}
var FTargetGroup: Array = []
var FDelayedEffects: Array = []
var FOnDie := false
var FOnFire := false
var FOnPreFire := false
var FOnLose := false
var FAtTarget := false
var FOnWelaUnitProduced := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))
	e.append(XEvent("OnFire", C.eiFire, C.epLast, C.etTrigger))
	e.append(XEvent("OnPreFire", C.eiPreFire, C.epLast, C.etTrigger))
	e.append(XEvent("OnLose", C.eiLose, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnWelaUnitProduced", C.eiWelaUnitProduced, C.epLast, C.etTrigger))


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FEffects = {}
	FTargetGroup = ComponentGroup.duplicate()
	FDelayedEffects = []
	return self


func Destroy() -> void:
	FDelayedEffects.clear()
	var effects := FEffects
	Owner.Eventbus.Trigger(C.eiEnumerateComponents, [func(Component) -> void:
		if Component is TMeshComponent and effects.has(Component):
			for Effect: TMeshEffect in effects[Component]:
				Component.RemoveMeshEffect(Effect)], FTargetGroup)
	FEffects.clear()
	super()


func ActivateOnDie() -> TMeshEffectComponent:
	FOnDie = true
	return self


func ActivateOnFire() -> TMeshEffectComponent:
	FOnFire = true
	return self


func ActivateOnLose() -> TMeshEffectComponent:
	FOnLose = true
	return self


func ActivateOnPreFire() -> TMeshEffectComponent:
	FOnPreFire = true
	return self


func ActivateOnWelaUnitProduced() -> TMeshEffectComponent:
	FOnWelaUnitProduced = true
	return self


func ApplyToFireTarget() -> TMeshEffectComponent:
	FAtTarget = true
	return self


func TargetGroup(Group = null) -> TMeshEffectComponent:
	FTargetGroup = DSet.Make(Group)
	return self


func SetEffect(Effect = null) -> TMeshEffectComponent:
	FDelayedEffects.append(Effect)
	if not FOnDie and not FOnFire:
		ApplyEffects([Owner])
	return self


func ApplyEffects(Targets: Array) -> void:
	for Entity in Targets:
		for i in range(FDelayedEffects.size() - 1, -1, -1):
			var Effect: TMeshEffect = FDelayedEffects[i]
			Effect.Reset()
			Effect.InitOnEntity(Entity)
			var effects := FEffects
			var at_target := FAtTarget
			Entity.Eventbus.Trigger(C.eiEnumerateComponents, [func(Component) -> void:
				if Component is TMeshComponent:
					var GivenEffect := Effect.Clone(null)
					if not at_target:
						GivenEffect.Managed = true
						if not effects.has(Component):
							effects[Component] = []
						effects[Component].append(GivenEffect)
					Component.AddMeshEffect(GivenEffect)], FTargetGroup)


func _target_entities(Targets) -> Array:
	var result := []
	var game = GlobalEventbus().Game if GlobalEventbus() != null else null
	var TargetsRaw := ATarget.FromRParam(Targets)
	for Target: RTarget in TargetsRaw:
		var ent = Target.TryGetTargetEntity(game)
		if ent != null:
			result.append(ent)
	return result


func OnDie(_KillerID, _KillerCommanderID) -> bool:
	if FOnDie:
		ApplyEffects([Owner])
	return true


func OnFire(Targets) -> bool:
	if FOnFire:
		ApplyEffects(_target_entities(Targets) if FAtTarget else [Owner])
	return true


func OnPreFire(Targets) -> bool:
	if FOnPreFire:
		ApplyEffects(_target_entities(Targets) if FAtTarget else [Owner])
	return true


func OnLose(TeamID) -> bool:
	if FOnLose and Owner.TeamID() == RParam.AsInteger(TeamID):
		ApplyEffects([Owner])
	return true


func OnWelaUnitProduced(EntityID) -> bool:
	var game = GlobalEventbus().Game if GlobalEventbus() != null else null
	if FOnWelaUnitProduced and game != null:
		var Entity = game.EntityManager.TryGetEntityByID(RParam.AsInteger(EntityID))
		if Entity != null:
			ApplyEffects([Entity])
	return true
