#include "entity/t_remote_subscription.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "entity/t_entity_component.h"
#include "entity/t_eventbus.h"

namespace godot {

void TRemoteSubscription::_bind_methods() {
	ClassDB::bind_method(D_METHOD("Create", "TargetComponent", "TargetEventbus", "Event", "EventType", "EventPriority"),
			&TRemoteSubscription::Create, DEFVAL(Variant()), DEFVAL(Variant()), DEFVAL(0), DEFVAL(0), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("Destroy"), &TRemoteSubscription::Destroy);
	ClassDB::bind_method(D_METHOD("Free"), &TRemoteSubscription::Free);
	ClassDB::bind_method(D_METHOD("FreeComponent"), &TRemoteSubscription::FreeComponent);
	ClassDB::bind_method(D_METHOD("FreeEventbus"), &TRemoteSubscription::FreeEventbus);
}

Ref<TRemoteSubscription> TRemoteSubscription::Create(const Variant &p_target_component, const Variant &p_target_eventbus,
		int p_event, int p_event_type, int p_event_priority) {
	FComponentFreed = false;
	FEventbusFreed = false;
	FTargetEventbusRef = p_target_eventbus;
	FTargetEventbus = Object::cast_to<TEventbus>(p_target_eventbus);
	FTargetComponentRef = p_target_component;
	FTargetComponent = Object::cast_to<TEntityComponent>(p_target_component);
	FEvent = p_event;
	FEventPriotity = p_event_priority;
	FEventType = p_event_type;
	FRefCounter = 2;
	return Ref<TRemoteSubscription>(this);
}

void TRemoteSubscription::DecRefCounter() {
	FRefCounter--;
	// eventbus and component are freed, free me too ;)
	if (FRefCounter <= 0) {
		Free();
	}
}

void TRemoteSubscription::Destroy() {
	if (!FComponentFreed) {
		UtilityFunctions::push_error(vformat("TRemoteSubscription.Destroy: Component(%s) has not been freed!",
				FTargetComponent != nullptr ? FTargetComponent->ComponentClassName() : String()));
	}
	if (!FEventbusFreed) {
		UtilityFunctions::push_error("TRemoteSubscription.Destroy: Eventbus has not been freed!");
	}
	FTargetEventbus = nullptr;
	FTargetEventbusRef = Variant();
	FTargetComponent = nullptr;
	FTargetComponentRef = Variant();
}

void TRemoteSubscription::FreeComponent() {
	DEV_ASSERT(!FComponentFreed);
	FComponentFreed = true;
	// keep the component alive until this is done: its subscription may be its last reference
	const Variant component = FTargetComponentRef;
	// if TargetEventbus exist, unsubscribe!
	if (!FEventbusFreed) {
		FTargetEventbus->UnsubscribeComponent(FEvent, FEventType, FEventPriotity, FTargetComponent);
	}
	// delete manually to prevent auto unsubscribe on eventbus
	FTargetComponent->DeleteSubscribedEvent(FTargetEventbus, FEvent, FEventType);
	DecRefCounter();
}

void TRemoteSubscription::FreeEventbus() {
	DEV_ASSERT(!FEventbusFreed);
	FEventbusFreed = true;
	DecRefCounter();
}

} // namespace godot
