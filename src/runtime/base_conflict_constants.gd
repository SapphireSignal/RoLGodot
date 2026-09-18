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
