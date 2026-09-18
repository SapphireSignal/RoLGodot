extends RefCounted
## Hand port of the functions and set constants of BaseConflict.Constants.pas that the runtime needs.
## (Enum values and the constants the scripts see are generated into src/runtime/dws/dws_const.gd.)
## Preload as `BC`.

const C = preload("res://src/runtime/dws/dws_const.gd")

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
