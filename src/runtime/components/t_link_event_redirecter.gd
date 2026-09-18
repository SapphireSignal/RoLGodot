class_name TLinkEventRedirecter
extends TEntityComponent
## Port of TLinkEventRedirecter (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:677, implementation :893),
## server only. TWelaLinkEffectComponent adds it (ALLGROUP) to every link it spawns. A link fetches data from its
## source if it has none: empty eiCooldown, eiWelaDamage and eiDamageType reads (epFirst) are read from the source
## (eiLinkSource[0]) in the group of the source's link effect; eiDamageDone and eiYouHaveKilledMeShameOnYou are passed
## on to the source. A gone source answers empty.

var FGroup: Array = []
var FSourceIndex := 0


func CreateGrouped(Owner = null, ComponentGroup_ = [], SourceGroup = []) -> TEntityComponent:
	super(Owner, ComponentGroup_)
	FGroup = DSet.Make(SourceGroup)
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnEvent", C.eiCooldown, C.epFirst, C.etRead))
	e.append(XEvent("OnEvent", C.eiWelaDamage, C.epFirst, C.etRead))
	e.append(XEvent("OnEvent", C.eiDamageType, C.epFirst, C.etRead))
	e.append(XEvent("OnDamageDone", C.eiDamageDone, C.epLast, C.etTrigger))
	e.append(XEvent("OnYouHaveKilledMeShameOnYou", C.eiYouHaveKilledMeShameOnYou, C.epLast, C.etTrigger))


func GetSource():
	var temp := ATarget.FromRParam(Eventbus().Read(C.eiLinkSource, []))
	if not ATarget.HasIndex(temp, FSourceIndex):
		push_error(BuildExceptionMessage("GetSource: Couldn't find source index %d!" % FSourceIndex))
		return null
	if temp[FSourceIndex].IsEntity():
		return temp[FSourceIndex].GetTargetEntity(GlobalEventbus().Game)
	return null


func OnDamageDone(Amount, DamageType, TargetEntity) -> bool:
	var Source = GetSource()
	if Source != null:
		Source.Eventbus.Trigger(C.eiDamageDone, [Amount, DamageType, TargetEntity])
	return true


## Redirect events.
func OnEvent(Previous):
	if RParam.IsEmpty(Previous):
		var Event := TEventbus.CurrentEvent_EventIdentifier
		var Source = GetSource()
		if Source != null:
			return Source.Eventbus.Read(Event, [], FGroup)
		return null  # uninitialised in the original
	return Previous


func OnYouHaveKilledMeShameOnYou(KilledUnitID) -> bool:
	var Source = GetSource()
	if Source != null:
		Source.Eventbus.Trigger(C.eiYouHaveKilledMeShameOnYou, [KilledUnitID])
	return true
