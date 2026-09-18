class_name TCommanderAbility
extends TEntityComponent
## Port of TCommanderAbility (GameServer/BaseConflict.EntityComponents.Server.pas:473, implementation :4786-4861),
## server only. One playable card of a commander (in the card's group): it answers eiEnumerateCommanderAbilities
## (epLast) by adding itself to the list, and is what the bot plays. Use / CanUse go to the card's group, or with
## IsMultiMode to the group of the chosen mode. Its charges are the commander's reCharge in the card's group.
## Kept: ModeCount is Min(1, length(modes)), so it is 0 or 1 (the original most likely meant Max).

var FCardInfo: TCardInfo = null
var FChargeGroup: Array = []
## one single-group set per mode
var FMultiModes: Array = []

var GetCardInfo: TCardInfo:
	get:
		return FCardInfo
var GetChargeGroup: Array:
	get:
		return FChargeGroup


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnEnumerateCommanderAbilities", C.eiEnumerateCommanderAbilities, C.epLast, C.etRead))


func CardInfo(CardInfo_ = null) -> TCommanderAbility:
	FCardInfo = CardInfo_
	return self


func ChargeGroup(ChargeGroup_ = []) -> TCommanderAbility:
	FChargeGroup = DSet.Make(ChargeGroup_)
	return self


func IsMultiMode(MultiModes = []) -> TCommanderAbility:
	FMultiModes = []
	for Mode in MultiModes:
		FMultiModes.append([Mode])
	return self


func _TargetGroup(Mode: int) -> Array:
	if FMultiModes.size() > Mode:
		return FMultiModes[Mode]
	return ComponentGroup


## Targets: an ACommanderAbilityTarget (Array of RCommanderAbilityTarget).
func CanUseAbility(Targets: Array, Mode: int = 0) -> bool:
	return RParam.AsBoolean(Eventbus().Read(C.eiCanUseAbility, [RCommanderAbilityTarget.ArrayToRParam(Targets)],
		_TargetGroup(Mode)))


func UseAbility(Targets: Array, Mode: int = 0) -> void:
	Eventbus().Trigger(C.eiUseAbility, [RCommanderAbilityTarget.ArrayToRParam(Targets)], _TargetGroup(Mode))


func CurrentCharges() -> int:
	return RParam.AsInteger(Owner.Balance(C.reCharge, ComponentGroup))


func MaxCharges() -> int:
	return RParam.AsInteger(Owner.Cap(C.reCharge, ComponentGroup))


func ModeCount() -> int:
	return mini(1, FMultiModes.size())


func IsReady() -> bool:
	return RParam.AsBoolean(Eventbus().Read(C.eiIsReady, [], ComponentGroup))


## The list (an Array) of the commander's abilities; each one appends itself.
func OnEnumerateCommanderAbilities(Previous):
	var List = Previous
	if List == null:
		List = []
	List.append(self)
	return List
