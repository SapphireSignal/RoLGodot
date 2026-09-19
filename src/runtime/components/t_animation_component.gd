class_name TAnimationComponent
extends TGDEntityComponent
## Port of TAnimationComponent (BaseConflict.EntityComponents.Client.Visuals.pas:1022, implementation :1525).
## Turns what the entity does (created, attacks, links, stands, walks) into eiPlayAnimation for its mesh group.

const AnimationController = preload("res://src/runtime/graphics/t_animation_controller.gd")

var FSecondAttackGroup: Array = []
var FSecondAttack: Array = []
var FOpenLinkCount := 0
var FLoopFire := false
var FIsLink := false
var FAlternatingAttack := false
var FAlternateAttack := false
var FHasAntiAirAttack := false
var FAnimationLength := {}  # EnumEventIdentifier -> ms
var FAbilityGroup: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnPreFire", C.eiPreFire, C.epLast, C.etTrigger))
	e.append(XEvent("OnFire", C.eiFire, C.epLast, C.etTrigger))
	e.append(XEvent("OnLinkEstablish", C.eiLinkEstablish, C.epLast, C.etTrigger))
	e.append(XEvent("OnLinkBreak", C.eiLinkBreak, C.epLast, C.etTrigger))
	e.append(XEvent("OnStand", C.eiStand, C.epLast, C.etTrigger))
	e.append(XEvent("OnMoveTo", C.eiMoveTo, C.epLast, C.etTrigger))


func _play(Animation_: String, PlayMode: int, Length: int) -> void:
	Eventbus().Trigger(C.eiPlayAnimation, [Animation_, PlayMode, Length], ComponentGroup)


func _fire_mode() -> int:
	return AnimationController.alLoop if FLoopFire else AnimationController.alSingle


## Play spawnanimation.
func OnAfterCreate() -> bool:
	_play(C.ANIMATION_SPAWN, AnimationController.alSingle, 0)
	return true


func PlayAttack(Target: Array) -> void:
	if FIsLink:
		return
	var called: Array = TEventbus.GetCurrentEvent_CalledToGroup()
	if DSet.Intersects(called, FAbilityGroup):
		_play(C.ANIMATION_ABILITY_1, _fire_mode(), 0)
		return
	var attack := C.ANIMATION_ATTACK
	if FAlternatingAttack:
		if FAlternateAttack:
			attack = C.ANIMATION_ATTACK2
		FAlternateAttack = not FAlternateAttack
	var game = GlobalEventbus().Game if GlobalEventbus() != null else null
	var TargetEntity = null
	if ATarget.Count(Target) > 0 and ATarget.First(Target).IsEntity():
		TargetEntity = ATarget.First(Target).TryGetTargetEntity(game)
	if FHasAntiAirAttack and TargetEntity != null \
			and DSet.IsSubset(DSet.Intersection([C.upGround, C.upFlying], Owner.UnitProperties()), TargetEntity.UnitProperties()):
		if attack == C.ANIMATION_ATTACK:
			attack = C.ANIMATION_ATTACK_AIR
		elif attack == C.ANIMATION_ATTACK2:
			attack = C.ANIMATION_ATTACK_AIR2
	if (not FSecondAttackGroup.is_empty() and DSet.Intersects(FSecondAttackGroup, called)) \
			or (not FSecondAttack.is_empty() and TargetEntity != null and DSet.Intersects(TargetEntity.UnitProperties(), FSecondAttack)):
		attack = C.ANIMATION_ATTACK2
	_play(attack, _fire_mode(), 0)


func OnPreFire(Targets) -> bool:
	if RParam.AsInteger(Eventbus().Read(C.eiWelaActionpoint, [], TEventbus.GetCurrentEvent_CalledToGroup())) > 0:
		PlayAttack(ATarget.FromRParam(Targets))
	return true


func OnFire(Targets) -> bool:
	if RParam.AsInteger(Eventbus().Read(C.eiWelaActionpoint, [], TEventbus.GetCurrentEvent_CalledToGroup())) <= 0:
		PlayAttack(ATarget.FromRParam(Targets))
	return true


func OnLinkBreak(_Dest) -> bool:
	if FIsLink:
		FOpenLinkCount -= 1
		if FOpenLinkCount <= 0:
			_play(C.ANIMATION_STAND, AnimationController.alSingle, 0)
	return true


func OnLinkEstablish(_Source, _Dest) -> bool:
	if FIsLink:
		FOpenLinkCount += 1
		_play(C.ANIMATION_ATTACK, _fire_mode(), 0)
	return true


func OnMoveTo(_Target, _Range) -> bool:
	_play(C.ANIMATION_WALK, AnimationController.alLoop, FAnimationLength.get(C.eiMoveTo, 0))
	return true


func OnStand() -> bool:
	if not FIsLink or not Owner.UnitProperties().has(C.upBuilding):
		_play(C.ANIMATION_STAND, AnimationController.alSingle, 0)
	return true


func SetAnimationSpeed(identifier = null, AnimationLength = null) -> TAnimationComponent:
	FAnimationLength[identifier] = AnimationLength
	return self


func LoopFire() -> TAnimationComponent:
	FLoopFire = true
	return self


func IsLink() -> TAnimationComponent:
	FIsLink = true
	return self


func HasAntiAirAttack() -> TAnimationComponent:
	FHasAntiAirAttack = true
	return self


func SecondAttackAgainst(Properties = null) -> TAnimationComponent:
	FSecondAttack = DSet.Make(Properties)
	return self


func SecondAttackGroup(Group = null) -> TAnimationComponent:
	FSecondAttackGroup = DSet.Make(Group)
	return self


func AlternatingAttack() -> TAnimationComponent:
	FAlternatingAttack = true
	return self


func AbilityGroup(Group = null) -> TAnimationComponent:
	FAbilityGroup = DSet.Make(Group)
	return self
