class_name TWelaEffectActivationAbilityComponent
extends TWelaEffectComponent
## Port of TWelaEffectActivationAbilityComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:353,
## implementation :2675), server only. On fire writes eiWelaActive := FActivationState (default false; SetsActive:
## true) to the activation group (default: its own group) if that changes it (an empty value counts as active).
## Conditions: OnlyAfterGameStart (the global eiGameTickTimeToFirstTick <= 0); TriggerOnReachResourceCap: balance =
## cap of the resource in the check group (default []); CheckNotFull: balance <> cap. Balance and cap compare as
## RParams (same type and value).

var FOnCap := false
var FActivationState := false
var FOnlyAfterGameStart := false
var FInvertOnCap := false
var FCheckGroup: Array = []
var FActivationGroup: Array = []
var FResType := 0


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FActivationGroup = ComponentGroup
	return self


func Fire(_Targets: Array) -> void:
	var Condition := true
	Condition = Condition and (not FOnlyAfterGameStart or RParam.AsInteger(GlobalEventbus().Read(C.eiGameTickTimeToFirstTick, [])) <= 0)
	if FOnCap:
		var Balance = Eventbus().Read(C.eiResourceBalance, [FResType], FCheckGroup)
		var Cap = Eventbus().Read(C.eiResourceCap, [FResType], FCheckGroup)
		Condition = Condition and ((not FInvertOnCap and RParam.Equal(Balance, Cap)) or (FInvertOnCap and not RParam.Equal(Balance, Cap)))
	# only throw event if it would change the targets status
	if Condition and RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiWelaActive, [FActivationState], FActivationGroup)) != FActivationState:
		Eventbus().Write(C.eiWelaActive, [FActivationState], FActivationGroup)


func OnlyAfterGameStart() -> TWelaEffectActivationAbilityComponent:
	FOnlyAfterGameStart = true
	return self


func TriggerOnReachResourceCap(ResType: int = 0) -> TWelaEffectActivationAbilityComponent:
	FOnCap = true
	FResType = ResType
	return self


func CheckNotFull(ResType: int = 0) -> TWelaEffectActivationAbilityComponent:
	FOnCap = true
	FResType = ResType
	FInvertOnCap = true
	return self


func SetCheckGroup(CheckGroup = []) -> TWelaEffectActivationAbilityComponent:
	FCheckGroup = DSet.Make(CheckGroup)
	return self


func SetsActive() -> TWelaEffectActivationAbilityComponent:
	FActivationState = true
	return self


func SetActivationGroup(ActivationGroup = []) -> TWelaEffectActivationAbilityComponent:
	FActivationGroup = DSet.Make(ActivationGroup)
	return self
