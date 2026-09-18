class_name TBrainComponent
extends TEntityComponent
## Port of TBrainComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:168, implementation :2057),
## server only. Base of every brain. A think impulse triggers eiThink, then eiThinkChain, in a group: eiThink
## (epMiddle) runs Think in every brain that can think; eiThinkChain runs ThinkChain brain after brain by priority
## until one returns False (it consumed the thought). Passive brains think their chain in eiThink instead, so a
## consumed chain does not stop them. Subclasses subscribe eiThinkChain themselves (each at its own priority) and
## answer it with ThinkChainEvent().

const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FPassiveThinking := false
var FPassiveThinkingIfConscious := false
var FThinkLocal := false
var FThinkInExile := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnThink", C.eiThink, C.epMiddle, C.etTrigger))


## The original's Game global (ServerGame on the server).
func BrainGame():
	return GlobalEventbus().Game


func IsWelaReady() -> bool:
	return RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup))


func CanThink() -> bool:
	var Result := FPassiveThinking or not DSet.Intersects(RParam.AsSet(Eventbus().Read(C.eiUnitProperties, [])),
		BC.UNIT_PROPERTIES_PREVENT_THINKING)
	Result = Result and RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiWelaActive, [], ComponentGroup))
	Result = Result and (not FThinkLocal or IsLocalCall())
	return Result


func CanMove() -> bool:
	return not DSet.Intersects(RParam.AsSet(Eventbus().Read(C.eiUnitProperties, [])),
		BC.UNIT_PROPERTIES_PREVENT_MOVEMENT)


## Should be called in the OnThink event.
func ThinkEvent() -> bool:
	if CanThink():
		Think()
		if FPassiveThinking or FPassiveThinkingIfConscious:
			ThinkChain()
	return true


## Should be called in the OnThinkChain event. Only thinks if allowed and not passive (passive brains think their
## chain in OnThink).
func ThinkChainEvent() -> bool:
	var Result := true
	if CanThink() and not FPassiveThinking and not FPassiveThinkingIfConscious:
		Result = ThinkChain()
	return Result


## Called every time thinking is initiated and the brain can think.
func Think() -> void:
	pass


## Called every time thinking is initiated, if the brain can think and no brain before it consumed the chain.
func ThinkChain() -> bool:
	return true


## Checks whether the weapon is ready and the targets are valid and if so fires at them.
func FireWithChecks(Targets: Array) -> void:
	if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)) and \
		_TargetsPossible(ATarget.ToRParam(Targets), ComponentGroup):
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Targets)], ComponentGroup)


## eiWelaTargetPossible [Targets] of Group .AsRTargetValidity.IsValid.
func _TargetsPossible(Targets, Group: Array) -> bool:
	return RTargetValidity.FromRParam(Eventbus().Read(C.eiWelaTargetPossible, [Targets], Group)).IsValid()


func OnThink() -> bool:
	return ThinkEvent()


## This brain thinks all the time, even if the unit is inactive (e.g. stunned).
func ThinksPassively() -> TBrainComponent:
	FPassiveThinking = true
	return self


## This brain thinks even if the unit is attacking.
func ThinksPassivelyIfConscious() -> TBrainComponent:
	FPassiveThinkingIfConscious = true
	return self


## Thinking is only processed when the think event is a local event.
func ThinksLocal() -> TBrainComponent:
	FThinkLocal = true
	return self


## Thinking is also done in exile.
func ThinksInExile() -> TBrainComponent:
	FThinkInExile = true
	return self
