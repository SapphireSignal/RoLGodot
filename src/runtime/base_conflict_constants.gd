extends RefCounted
## Hand port of the functions and set constants of BaseConflict.Constants.pas that the runtime needs.
## (Enum values and the constants the scripts see are generated into src/runtime/dws/dws_const.gd.)
## Preload as `BC`.

const C = preload("res://src/runtime/dws/dws_const.gd")
const L = preload("res://src/runtime/dws/dws_lib.gd")

## APPLICATIONTYPE = {$IFDEF SERVER}nsServer{$ELSE}nsClient{$ENDIF}. The original ran client and server as
## separate programs; the port runs both in one process, so each TEventbus carries its side (ApplicationType).


## RES_INT_RESOURCES : SetResource = [reInteger .. high(EnumResource)]
static func IsIntResource(ResourceType: int) -> bool:
	return ResourceType >= C.reInteger and ResourceType <= C.reCharmCount


## RES_FLOAT_RESOURCES : SetResource = [reFloat .. pred(reInteger)]
static func IsFloatResource(ResourceType: int) -> bool:
	return ResourceType >= C.reFloat and ResourceType < C.reInteger


## RES_IGNORE_CAP : SetResource = [reGadgetCount, reCharmCount]
static func IgnoresCap(ResourceType: int) -> bool:
	return ResourceType == C.reGadgetCount or ResourceType == C.reCharmCount


## ResourceAsSingle (BaseConflict.Types.Shared.pas:168): an int resource's value as a single.
static func ResourceAsSingle(ResourceType: int, Resource) -> float:
	if IsIntResource(ResourceType):
		return float(RParam.AsInteger(Resource))
	return RParam.AsSingle(Resource)


## ResourceAdd (BaseConflict.Types.Shared.pas:156)
static func ResourceAdd(ResourceType: int, Summand, Summand2):
	if IsIntResource(ResourceType):
		return RParam.AsInteger(Summand) + RParam.AsInteger(Summand2)
	return RParam.ToSingle(RParam.AsSingle(Summand) + RParam.AsSingle(Summand2))


## ResourceSubtract (BaseConflict.Types.Shared.pas:150)
static func ResourceSubtract(ResourceType: int, Minuend, Subtrahend):
	if IsIntResource(ResourceType):
		return RParam.AsInteger(Minuend) - RParam.AsInteger(Subtrahend)
	return RParam.ToSingle(RParam.AsSingle(Minuend) - RParam.AsSingle(Subtrahend))


## ResourceCompare(ResourceType, Resource, Comparator, ReferenceValue: RParam, ReferenceFactor) (:125):
## compares with ReferenceValue * ReferenceFactor (not rounded, also for int resources).
static func ResourceCompareParam(ResourceType: int, Resource, Comparator: int, ReferenceValue, ReferenceFactor: float = 1.0) -> bool:
	var Value: float
	var Reference: float
	if IsIntResource(ResourceType):
		Value = RParam.AsInteger(Resource)
		Reference = RParam.AsInteger(ReferenceValue) * RParam.ToSingle(ReferenceFactor)
	else:
		Value = RParam.AsSingle(Resource)
		Reference = RParam.AsSingle(ReferenceValue) * RParam.ToSingle(ReferenceFactor)
	match Comparator:
		C.coLowerEqual:
			return Value <= Reference
		C.coLower:
			return Value < Reference
		C.coGreaterEqual:
			return Value >= Reference
		C.coGreater:
			return Value > Reference
		C.coEqual:
			return Value == Reference
	return false


## ResourcePercentage (BaseConflict.Types.Shared.pas:162): Balance / Cap.
static func ResourcePercentage(ResourceType: int, Balance, Cap) -> float:
	if IsIntResource(ResourceType):
		return RParam.ToSingle(float(RParam.AsInteger(Balance)) / RParam.AsInteger(Cap))
	return RParam.ToSingle(RParam.AsSingle(Balance) / RParam.AsSingle(Cap))


## ResourceCompare(ResourceType, Resource, Comparator, ReferenceValue: single) (BaseConflict.Types.Shared.pas:97).
## Int resources compare with Round(ReferenceValue). An unknown comparator gives false.
static func ResourceCompare(ResourceType: int, Resource, Comparator: int, ReferenceValue: float) -> bool:
	var Value: float
	var Reference: float
	if IsIntResource(ResourceType):
		Value = RParam.AsInteger(Resource)
		Reference = L.Round(ReferenceValue)
	else:
		Value = RParam.AsSingle(Resource)
		Reference = RParam.ToSingle(ReferenceValue)
	match Comparator:
		C.coLowerEqual:
			return Value <= Reference
		C.coLower:
			return Value < Reference
		C.coGreaterEqual:
			return Value >= Reference
		C.coGreater:
			return Value > Reference
		C.coEqual:
			return Value == Reference
	return false


## ARMORY_TYPES_NORMAL = [atUnarmored .. atHeavy] (BaseConflict.Constants.Cards.pas:44)
static func IsNormalArmorType(ArmorType: int) -> bool:
	return ArmorType >= C.atUnarmored and ArmorType <= C.atHeavy


## BaseConflict.Constants.pas:1058
static func EventIdentifierToNetworkSend(Event: int) -> int:
	match Event:
		C.eiTeamID, C.eiMoveTo, C.eiStand, C.eiSyncPosition, C.eiDie, C.eiRemoveComponent, \
		C.eiKillEntity, C.eiResourceBalance, C.eiResourceCap, C.eiResourceCost, C.eiLose, C.eiPreFire, C.eiFire, \
		C.eiCancelFire, C.eiFireWarhead, C.eiGameCommencing, C.eiGameStart, \
		C.eiRemoveComponentGroup, C.eiReplaceEntity, C.eiWelaSetMainTarget, C.eiGameTick, C.eiLinkEstablish, \
		C.eiLinkBreak, C.eiSetGridFieldBlocking, C.eiExiled, C.eiUnitProperties, \
		C.eiWelaUnitProduced, C.eiCooldownStartingTime, C.eiGameEvent, \
		C.eiWelaActive, C.eiWelaSavedTargets, C.eiSyncPath, C.eiWaveSpawn, C.eiWelaCooldownReset:
			return C.nsServer
		C.eiUseAbility, C.eiSurrender, C.eiClientCommand:
			return C.nsClient
	return C.nsNone


## BaseConflict.Constants.pas:1073
static func EventIdentifierToBlackboardEvent(Event: int) -> bool:
	match Event:
		C.eiTeamID, C.eiPosition, C.eiFront, C.eiOwnerCommander, C.eiExiled, C.eiBuildgridBlockedFields:
			return true
	return false
