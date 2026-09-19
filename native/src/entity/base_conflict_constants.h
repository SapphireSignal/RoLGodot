#pragma once

// The helpers of BaseConflict.Constants.pas the C++ game code needs (the rest is still in
// src/runtime/base_conflict_constants.gd).

#include "dws/dws_const.h"

namespace godot::BC {

// BaseConflict.Constants.pas:1058: the side whose triggers of the event go over the network.
inline int EventIdentifierToNetworkSend(int p_event) {
	switch (p_event) {
		case C::eiTeamID:
		case C::eiMoveTo:
		case C::eiStand:
		case C::eiSyncPosition:
		case C::eiDie:
		case C::eiRemoveComponent:
		case C::eiKillEntity:
		case C::eiResourceBalance:
		case C::eiResourceCap:
		case C::eiResourceCost:
		case C::eiLose:
		case C::eiPreFire:
		case C::eiFire:
		case C::eiCancelFire:
		case C::eiFireWarhead:
		case C::eiGameCommencing:
		case C::eiGameStart:
		case C::eiRemoveComponentGroup:
		case C::eiReplaceEntity:
		case C::eiWelaSetMainTarget:
		case C::eiGameTick:
		case C::eiLinkEstablish:
		case C::eiLinkBreak:
		case C::eiSetGridFieldBlocking:
		case C::eiExiled:
		case C::eiUnitProperties:
		case C::eiWelaUnitProduced:
		case C::eiCooldownStartingTime:
		case C::eiGameEvent:
		case C::eiWelaActive:
		case C::eiWelaSavedTargets:
		case C::eiSyncPath:
		case C::eiWaveSpawn:
		case C::eiWelaCooldownReset:
			return C::nsServer;
		case C::eiUseAbility:
		case C::eiSurrender:
		case C::eiClientCommand:
			return C::nsClient;
		default:
			return C::nsNone;
	}
}

// BaseConflict.Constants.pas:1073
inline bool EventIdentifierToBlackboardEvent(int p_event) {
	switch (p_event) {
		case C::eiTeamID:
		case C::eiPosition:
		case C::eiFront:
		case C::eiOwnerCommander:
		case C::eiExiled:
		case C::eiBuildgridBlockedFields:
			return true;
		default:
			return false;
	}
}

// RES_INT_RESOURCES : SetResource = [reInteger .. high(EnumResource)] (BaseConflict.Constants.pas:218)
inline bool IsIntResource(int p_resource_type) {
	return p_resource_type >= C::reInteger && p_resource_type <= C::reCharmCount;
}

} // namespace godot::BC
