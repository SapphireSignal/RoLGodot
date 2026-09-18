class_name TAutoBrainComponent
extends TBrainComponent
## Port of TAutoBrainComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:465, implementation
## :2142), server only. Base of the brains triggered by something else than thinking (they think passively).
## CheckAndFire: if the brain can think, eiIsReady of its group (empty = ready) and not exiled (unless
## ThinksInExile), fires. FireTargets picks the targets: FireAtTarget (the group's targeting, eiWelaUpdateTargets on
## a fresh list; nothing found = no fire), FireAtAllCommanders, FireAtCommander (eiOwnerCommander), FireAtGround
## (own position), FireAtSelf, else the default targets (the owner, or what the event gave); then eiFire in
## FireInGroup (default own group) if eiWelaTargetPossible there allows.
## Port notes: Delphi's two overloads Fire / Fire(DefaultTargets) are Fire() / FireTargets(DefaultTargets) here;
## CheckAndFire always calls FireTargets, so a subclass overriding Fire() is only reached through Fire() itself
## (the original's overload resolution; see TAutoBrainOnDeathComponent). FireAtAllCommanders reads
## GlobalEventbus().Game.Commanders (ServerGame.Commanders; no scripts use it).

var FFireGroup: Array = []
var FFireAtAllCommanders := false
var FFireAtCommander := false
var FFireAtTarget := false
var FFireAtGround := false
var FFireAtSelf := false


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FPassiveThinking = true
	FFireGroup = ComponentGroup
	return self


## CheckAndFire / CheckAndFire(DefaultTargets); DefaultTargets null = the owner.
func CheckAndFire(DefaultTargets = null) -> void:
	if DefaultTargets == null:
		DefaultTargets = ATarget.Make(FOwner)
	if CanThink() and RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)) and \
		(FThinkInExile or not RParam.AsBoolean(Eventbus().Read(C.eiExiled, []))):
		FireTargets(DefaultTargets)


## Fire (no targets given): fires with the owner as default target.
func Fire() -> void:
	FireTargets(ATarget.Make(FOwner))


## Fire(DefaultTargets).
func FireTargets(DefaultTargets: Array) -> void:
	var Target: Array
	if FFireAtTarget:
		var TargetList: Array = []
		Eventbus().Trigger(C.eiWelaUpdateTargets, [TargetList], ComponentGroup)
		Target = TargetList.duplicate()
		if Target.size() <= 0:
			return
	elif FFireAtAllCommanders:
		Target = []
		var game = BrainGame()
		var Commanders: Array = game.get("Commanders") if game != null and game.get("Commanders") != null else []
		for Commander in Commanders:
			Target.append(RTarget.Create(Commander))
	elif FFireAtCommander:
		Target = ATarget.Make(RParam.AsInteger(Eventbus().Read(C.eiOwnerCommander, [])))
	elif FFireAtGround:
		Target = ATarget.Make(FOwner.Position)
	elif FFireAtSelf:
		Target = ATarget.Make(FOwner)
	else:
		Target = DefaultTargets
	if not _TargetsPossible(ATarget.ToRParam(Target), FFireGroup):
		return
	Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Target)], FFireGroup)


func FireInGroup(Group: Array) -> TAutoBrainComponent:
	FFireGroup = DSet.Make(Group)
	return self


## Fires at owner.
func FireAtSelf() -> TAutoBrainComponent:
	FFireAtSelf = true
	return self


## Fires at own position.
func FireAtGround() -> TAutoBrainComponent:
	FFireAtGround = true
	return self


## Uses the targeting component to find targets.
func FireAtTarget() -> TAutoBrainComponent:
	FFireAtTarget = true
	return self


## Fires at the owning commander.
func FireAtCommander() -> TAutoBrainComponent:
	FFireAtCommander = true
	return self


## Fires at all commanders, useful for bounty.
func FireAtAllCommanders() -> TAutoBrainComponent:
	FFireAtAllCommanders = true
	return self
