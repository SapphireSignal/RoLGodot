class_name TLinkBrainComponent
extends TGDEntityComponent
## Port of TLinkBrainComponent (GameServer/BaseConflict.EntityComponents.Server.pas:150, implementation :1500),
## server only. The wela "brain" of a link: on each global eiIdle (epMiddle) it fires its warheads whenever the
## link's eiCooldown expires. The first idle (timer interval still <= 1 ms) fetches the cooldown and starts the timer;
## FiresAtCreate then fires its group at eiLinkDest if the own and that group are ready and the target is possible.
## Later, once expired and ready: fires eiFire [eiLinkDest] TimesExpired (max 50) times in its group if the target is
## possible there (FiresAtSources: as often at eiLinkSource in that group), then restarts with the fraction and
## refetches the cooldown. Not ready: the timer restarts with the fraction too (no shots are saved up).
## A cooldown of 0 or 1 ms keeps the brain in its first-idle branch.

var FFiresAtSources := false
var FFiresAtCreate := false
var FSourceTargetGroup: Array = []
var FFiresAtCreateGroup: Array = []
var FTimer: TTimer = null


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FTimer = TTimer.new().Create(0)
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnIdle", C.eiIdle, C.epMiddle, C.etTrigger, C.esGlobal))


func Destroy() -> void:
	FTimer = null
	super()


func FetchCooldown() -> void:
	FTimer.Interval = RParam.AsInteger(Eventbus().Read(C.eiCooldown, [], ComponentGroup))


func FiresAtCreate(Group: Array) -> TLinkBrainComponent:
	FFiresAtCreate = true
	FFiresAtCreateGroup = DSet.Make(Group)
	return self


func FiresAtSources(Group: Array) -> TLinkBrainComponent:
	FFiresAtSources = true
	FSourceTargetGroup = DSet.Make(Group)
	return self


## Fires the warheads whenever the timer expires.
func OnIdle() -> bool:
	var Targets: Array
	if FTimer.Interval <= 1:
		FetchCooldown()
		FTimer.Start()
		if FFiresAtCreate \
			and RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)) \
			and RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], FFiresAtCreateGroup)):
			Targets = ATarget.FromRParam(Eventbus().Read(C.eiLinkDest, []))
			if _Possible(Targets, FFiresAtCreateGroup):
				Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Targets)], FFiresAtCreateGroup)
	elif FTimer.Expired:
		Targets = ATarget.FromRParam(Eventbus().Read(C.eiLinkDest, []))
		if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)):
			# compute the times the brain has to fire, for lag safety at max 50 times
			var fireTimes := FTimer.TimesExpired(50)
			FTimer.StartWithFrac()
			if _Possible(Targets, ComponentGroup):
				for i in fireTimes:
					Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Targets)], ComponentGroup)
			if FFiresAtSources:
				Targets = ATarget.FromRParam(Eventbus().Read(C.eiLinkSource, []))
				if _Possible(Targets, FSourceTargetGroup):
					for i in fireTimes:
						Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Targets)], FSourceTargetGroup)
		FTimer.StartWithFrac()
		FetchCooldown()
	return true


func _Possible(Targets: Array, Group: Array) -> bool:
	return RTargetValidity.FromRParam(Eventbus().Read(C.eiWelaTargetPossible, [ATarget.ToRParam(Targets)], Group)).IsValid()
