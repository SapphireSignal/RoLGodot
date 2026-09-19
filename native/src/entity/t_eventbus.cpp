#include "entity/t_eventbus.h"

#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "engine/t_thread_context.h"
#include "entity/base_conflict_constants.h"
#include "entity/d_set.h"
#include "entity/r_param.h"
#include "entity/t_blackboard.h"
#include "entity/t_entity.h"
#include "entity/t_entity_component.h"
#include "entity/t_remote_subscription.h"

namespace godot {

namespace {

inline int EventKey(int p_event, int p_event_type) {
	return p_event * 3 + p_event_type;
}

// DSet.Make for the calls' usual [] and [g] without a copy (they are sets already).
inline Array MakeGroup(const Array &p_group) {
	const int64_t count = p_group.size();
	if (count == 0 || (count == 1 && p_group[0].get_type() == Variant::INT)) {
		return p_group;
	}
	return DSet::Make(p_group);
}

// The copy of the value array every call makes; script floats become singles (TEventbusScriptSideHelper).
Array ScriptValues(const Array &p_values) {
	if (p_values.is_empty()) {
		return p_values;
	}
	Array copy = p_values.duplicate();
	for (int64_t i = 0; i < copy.size(); i++) {
		if (copy[i].get_type() == Variant::FLOAT) {
			copy[i] = RParam::ToSingle(double(copy[i]));
		}
	}
	return copy;
}

// The Eventstack only restores the outer event when one ends, so Read / Trigger keep the outer event here (no stack
// object per event). The outermost event restores 0 / [] / [].
struct REventScope {
	TThreadContext *Ctx;
	int OuterEvent;
	Array OuterGroup;
	Array OuterParameters;

	REventScope(TThreadContext *p_ctx, int p_event, const Array &p_group, const Array &p_parameters) :
			Ctx(p_ctx), OuterEvent(p_ctx->CurrentEvent_EventIdentifier), OuterGroup(p_ctx->CurrentEvent_CalledToGroup),
			OuterParameters(p_ctx->CurrentParameters) {
		Ctx->CurrentEvent_EventIdentifier = p_event;
		Ctx->CurrentEvent_CalledToGroup = p_group;
		Ctx->CurrentParameters = p_parameters;
	}
	~REventScope() {
		Ctx->CurrentEvent_EventIdentifier = OuterEvent;
		Ctx->CurrentEvent_CalledToGroup = OuterGroup;
		Ctx->CurrentParameters = OuterParameters;
	}
};

// One walk over a handler's subscribers: BeginEvent / EndEvent of its enumerator.
struct RWalk {
	std::shared_ptr<TEventbus::TEventhandler> Handler;
	TEventbus::TEventEnumerator *Enumerator;

	explicit RWalk(const std::shared_ptr<TEventbus::TEventhandler> &p_handler) :
			Handler(p_handler), Enumerator(&p_handler->GetEnumerator()) {
		DEV_ASSERT(!Enumerator->FCurrentlyActive); // TEventbus.TEventhandler.BeginEvent: Eventhandler has been entered twice!
		Enumerator->FCurrentlyActive = true;
		Enumerator->FActiveIndex = 0;
	}
	~RWalk() {
		DEV_ASSERT(Enumerator->FCurrentlyActive); // TEventbus.TEventhandler.EndEvent: Eventhandler has been entered twice!
		Enumerator->FCurrentlyActive = false;
		Handler->ReleaseEnumerator();
	}
};

constexpr int MAX_STACK_ARGS = 16;

} // namespace

void TEventbus::_bind_methods() {
	ClassDB::bind_method(D_METHOD("Create", "Owner"), &TEventbus::Create, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("Destroy"), &TEventbus::Destroy);
	ClassDB::bind_method(D_METHOD("Free"), &TEventbus::Free);
	ClassDB::bind_method(D_METHOD("ClassName"), &TEventbus::ClassName);
	ClassDB::bind_method(D_METHOD("Read", "Eventname", "Parameters", "Group", "ComponentID"), &TEventbus::Read,
			DEFVAL(Array()), DEFVAL(Array()), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("ReadHierarchic", "Eventname", "Values", "Group"), &TEventbus::ReadHierarchic);
	ClassDB::bind_method(D_METHOD("Subscribe", "Eventname", "EventType", "Priority", "EntityCompononent", "ParameterCount", "MethodName"),
			&TEventbus::Subscribe);
	ClassDB::bind_method(D_METHOD("SubscribeRemote", "Eventname", "EventType", "Priority", "EntityCompononent", "MethodName",
								 "ParameterCount", "NetworkSender"),
			&TEventbus::SubscribeRemote, DEFVAL(C::nsNone));
	ClassDB::bind_method(D_METHOD("Trigger", "Eventname", "Values", "Group", "ComponentID", "Write"), &TEventbus::Trigger,
			DEFVAL(Array()), DEFVAL(Array()), DEFVAL(0), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("Write", "Eventname", "Values", "Group", "ComponentID"), &TEventbus::Write,
			DEFVAL(Array()), DEFVAL(Array()), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("InvokeWithRawData", "Eventname", "Group", "ComponentID", "Values", "WriteEvent"),
			&TEventbus::InvokeWithRawData);
	ClassDB::bind_method(D_METHOD("TriggerGrouped", "Eventname", "Values", "Group"), &TEventbus::TriggerGrouped);
	ClassDB::bind_method(D_METHOD("WriteGrouped", "Eventname", "Values", "Group"), &TEventbus::WriteGrouped);
	ClassDB::bind_method(D_METHOD("Unsubscribe", "Eventname", "EventType", "Priority", "EntityComponent"), &TEventbus::Unsubscribe);
	ClassDB::bind_method(D_METHOD("SubscriberCount", "Eventname", "EventType"), &TEventbus::SubscriberCount);

	ClassDB::bind_method(D_METHOD("GetOwner"), &TEventbus::GetOwner);
	ClassDB::bind_method(D_METHOD("GetApplicationType"), &TEventbus::GetApplicationType);
	ClassDB::bind_method(D_METHOD("SetApplicationType", "value"), &TEventbus::SetApplicationType);
	ClassDB::bind_method(D_METHOD("GetGame"), &TEventbus::GetGame);
	ClassDB::bind_method(D_METHOD("SetGame", "value"), &TEventbus::SetGame);
	ClassDB::bind_method(D_METHOD("GetEntityDataCache"), &TEventbus::GetEntityDataCache);
	ClassDB::bind_method(D_METHOD("SetEntityDataCache", "value"), &TEventbus::SetEntityDataCache);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "Owner"), "", "GetOwner");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "FOwner"), "", "GetOwner");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ApplicationType"), "SetApplicationType", "GetApplicationType");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "Game"), "SetGame", "GetGame");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "EntityDataCache"), "SetEntityDataCache", "GetEntityDataCache");

	ClassDB::bind_static_method("TEventbus", D_METHOD("GetCurrentEvent_EventIdentifier"), &TEventbus::GetCurrentEvent_EventIdentifier);
	ClassDB::bind_static_method("TEventbus", D_METHOD("SetCurrentEvent_EventIdentifier", "value"), &TEventbus::SetCurrentEvent_EventIdentifier);
	ClassDB::bind_static_method("TEventbus", D_METHOD("GetCurrentEvent_CalledToGroup"), &TEventbus::GetCurrentEvent_CalledToGroup);
	ClassDB::bind_static_method("TEventbus", D_METHOD("SetCurrentEvent_CalledToGroup", "value"), &TEventbus::SetCurrentEvent_CalledToGroup);
	ClassDB::bind_static_method("TEventbus", D_METHOD("GetCurrentParameters"), &TEventbus::GetCurrentParameters);
	ClassDB::bind_static_method("TEventbus", D_METHOD("GetProf"), &TEventbus::GetProf);
	ClassDB::bind_static_method("TEventbus", D_METHOD("SetProf", "value"), &TEventbus::SetProf);
}

// ---- TEventhandler ---------------------------------------------------------------------------------------------------

void TEventbus::TEventhandler::AddSubscriber(std::unique_ptr<RSubscriber> p_subscriber) {
	for (size_t i = 0; i < Subscribers.size(); i++) {
		if (Subscribers[i]->Priority > p_subscriber->Priority) {
			Subscribers.insert(Subscribers.begin() + i, std::move(p_subscriber));
			// if a subscriber get added before or at current position, the position has to increment as stack grows
			for (TEventEnumerator &e : FEnumerators) {
				if (e.FCurrentlyActive && int64_t(i) <= e.FActiveIndex) {
					e.FActiveIndex++;
				}
			}
			return;
		}
	}
	Subscribers.push_back(std::move(p_subscriber));
}

void TEventbus::TEventhandler::RemoveSubscriber(TEntityComponent *p_component, int p_priority) {
	int64_t index = -1;
	for (size_t i = 0; i < Subscribers.size(); i++) {
		if (Subscribers[i]->EntityComponent == p_component && Subscribers[i]->Priority == p_priority) {
			index = int64_t(i);
			break;
		}
	}
	ERR_FAIL_COND_MSG(index < 0, "TEventbus.TEventhandler.RemoveSubscriber: Trying to remove subscriber of event, but isn't present!");
	std::unique_ptr<RSubscriber> removed = std::move(Subscribers[index]);
	Subscribers.erase(Subscribers.begin() + index);
	// if a subscriber get removed before current position, the position has to decrement as stack shrinks
	for (TEventEnumerator &e : FEnumerators) {
		if (e.FCurrentlyActive && index <= e.FActiveIndex) {
			e.FActiveIndex--;
		}
	}
	if (FEnumeratorIndex > 0) {
		FRemoved.push_back(std::move(removed));
	}
}

TEventbus::TEventEnumerator &TEventbus::TEventhandler::GetEnumerator() {
	while (FEnumeratorIndex >= FEnumerators.size()) {
		FEnumerators.emplace_back();
	}
	DEV_ASSERT(!FEnumerators[FEnumeratorIndex].FCurrentlyActive); // Last enumerator is active, should not happen.
	return FEnumerators[FEnumeratorIndex++];
}

void TEventbus::TEventhandler::ReleaseEnumerator() {
	DEV_ASSERT(FEnumeratorIndex > 0);
	FEnumeratorIndex--;
	if (FEnumeratorIndex == 0 && !FRemoved.empty()) {
		std::vector<std::unique_ptr<RSubscriber>> removed;
		removed.swap(FRemoved);
	}
}

// ---- TEventbus -------------------------------------------------------------------------------------------------------

Ref<TEventbus> TEventbus::Create(const Variant &p_owner) {
	FOwnerRef = p_owner;
	FOwner = Object::cast_to<TEntity>(p_owner);
	return Ref<TEventbus>(this);
}

void TEventbus::Destroy() {
	if (FEntityDataCache.get_type() != Variant::NIL) {
		FEntityDataCache.call("Free");
		FEntityDataCache = Variant();
	}
	const Array subscriptions = FRemoteSubscriptions.duplicate();
	for (int64_t i = 0; i < subscriptions.size(); i++) {
		TRemoteSubscription *sub = Object::cast_to<TRemoteSubscription>(subscriptions[i]);
		sub->FreeEventbus();
	}
	FRemoteSubscriptions.clear();
	// an event walking one of the handlers keeps it (and its enumerators) until it ends
	FEventhandler.clear();
	FOwner = nullptr;
	FOwnerRef = Variant();
	FGame = Variant();
}

bool TEventbus::Matches(const TEntityComponent *p_component, const Array &p_group, int64_t p_component_id) {
	if (p_component_id != 0 && p_component->FUniqueID != p_component_id) {
		return false;
	}
	const int64_t count = p_group.size();
	if (count == 0 || p_component->InGroup(C::ALLGROUP_INDEX)) {
		return true;
	}
	for (int64_t i = 0; i < count; i++) {
		if (p_component->InGroup(int64_t(p_group[i]))) {
			return true;
		}
	}
	return false;
}

Variant TEventbus::CallHandler(TThreadContext *p_ctx, const RSubscriber &p_subscriber, const Variant **p_args, int p_count) {
	if (p_ctx->Prof.get_type() == Variant::NIL) {
		return p_subscriber.EntityComponent->CallMethod(p_subscriber.Method, p_args, p_count);
	}
	p_ctx->ProfChildTime.push_back(0);
	const int64_t start = int64_t(Time::get_singleton()->get_ticks_usec());
	Variant result = p_subscriber.EntityComponent->CallMethod(p_subscriber.Method, p_args, p_count);
	ProfLeave(p_ctx, p_subscriber, start);
	return result;
}

void TEventbus::ProfLeave(TThreadContext *p_ctx, const RSubscriber &p_subscriber, int64_t p_start) {
	const int64_t total = int64_t(Time::get_singleton()->get_ticks_usec()) - p_start;
	const int64_t children = p_ctx->ProfChildTime.back();
	p_ctx->ProfChildTime.pop_back();
	if (!p_ctx->ProfChildTime.empty()) {
		p_ctx->ProfChildTime.back() += total;
	}
	Dictionary prof = p_ctx->Prof;
	const String key = p_subscriber.EntityComponent->ComponentClassName() + "." + String(p_subscriber.Method);
	Array entry = prof.get(key, Variant());
	if (entry.is_empty()) {
		entry.append(0);
		entry.append(0);
		entry.append(0);
	}
	entry[0] = int64_t(entry[0]) + 1;
	entry[1] = int64_t(entry[1]) + total - children;
	entry[2] = int64_t(entry[2]) + total;
	prof[key] = entry;
}

Variant TEventbus::Read(int p_eventname, const Array &p_parameters, const Array &p_group, int64_t p_component_id) {
	// open array parameter passed by value
	const Array parameters = p_parameters.is_empty() ? p_parameters : p_parameters.duplicate();
	const Array group = MakeGroup(p_group);
	TThreadContext *ctx = TThreadContext::Get();
	REventScope scope(ctx, p_eventname, group, parameters);
	Variant result; // RPARAMEMPTY
	if (FOwner != nullptr) {
		result = FOwner->FBlackboard->GetValue(p_eventname, group);
	}
	auto found = FEventhandler.find(EventKey(p_eventname, C::etRead));
	if (found == FEventhandler.end()) {
		return result;
	}
	RWalk walk(found->second);
	TEventhandler &handler = *walk.Handler;
	TEventEnumerator &enumerator = *walk.Enumerator;
	const int count = int(parameters.size());
	const Variant *args[MAX_STACK_ARGS];
	std::vector<const Variant *> heap_args;
	const Variant **call_args = args;
	if (count + 1 > MAX_STACK_ARGS) {
		heap_args.resize(count + 1);
		call_args = heap_args.data();
	}
	while (enumerator.FActiveIndex < int64_t(handler.Subscribers.size())) {
		const RSubscriber &current = *handler.Subscribers[enumerator.FActiveIndex];
		if (Matches(current.EntityComponent, group, p_component_id)) {
			// the parameters as they are now: a handler before may have assigned a `var` parameter (SetVarParam; the
			// array's storage is copy-on-write, so the pointers are taken per call)
			for (int i = 0; i < count; i++) {
				call_args[i] = &parameters[i];
			}
			// TEntityComponent.OnRead: the previous result is an optional extra last parameter
			if (count + 1 == current.ParameterCount) {
				call_args[count] = &result;
				Variant value = CallHandler(ctx, current, call_args, count + 1);
				result = value;
			} else if (count == current.ParameterCount) {
				result = CallHandler(ctx, current, call_args, count);
			} else {
				UtilityFunctions::push_error(vformat("Parametercount for read event %d in component %s does not match - expected %d[+1], found %d.",
						p_eventname, current.EntityComponent->ComponentClassName(), current.ParameterCount, count));
			}
		}
		enumerator.FActiveIndex++;
	}
	return result;
}

Variant TEventbus::ReadHierarchic(int p_eventname, const Array &p_values, const Array &p_group) {
	Variant result = Read(p_eventname, p_values, p_group, 0);
	if (!p_group.is_empty() && result.get_type() == Variant::NIL) {
		result = Read(p_eventname, p_values, Array(), 0);
	}
	return result;
}

void TEventbus::Subscribe(int p_eventname, int p_event_type, int p_priority, const Variant &p_entity_component,
		int p_parameter_count, const StringName &p_method_name) {
	auto subscriber = std::make_unique<RSubscriber>();
	subscriber->EntityComponent = Object::cast_to<TEntityComponent>(p_entity_component);
	ERR_FAIL_NULL_MSG(subscriber->EntityComponent, "TEventbus.Subscribe: not a TEntityComponent");
	subscriber->Keep = p_entity_component;
	subscriber->Priority = p_priority;
	subscriber->Method = p_method_name;
	subscriber->ParameterCount = p_parameter_count;
	std::shared_ptr<TEventhandler> &handler = FEventhandler[EventKey(p_eventname, p_event_type)];
	if (!handler) {
		handler = std::make_shared<TEventhandler>();
		handler->ParameterCount = p_parameter_count;
	}
	handler->AddSubscriber(std::move(subscriber));
}

void TEventbus::SubscribeRemote(int p_eventname, int p_event_type, int p_priority, const Variant &p_entity_component,
		const StringName &p_method_name, int p_parameter_count, int p_network_sender) {
	TEntityComponent *component = Object::cast_to<TEntityComponent>(p_entity_component);
	ERR_FAIL_NULL_MSG(component, "TEventbus.SubscribeRemote: not a TEntityComponent");
	DEV_ASSERT(component->EventbusPtr() != this); // Wrong method for selfregistration, but technically should work.
	if (!component->has_method(p_method_name)) {
		UtilityFunctions::push_error(vformat("TEventbus.SubscribeRemote: Could not find %s in class %s", p_method_name,
				component->ComponentClassName()));
		return;
	}
	Ref<TRemoteSubscription> subscription;
	subscription.instantiate();
	subscription->Create(p_entity_component, Variant(this), p_eventname, p_event_type, p_priority);
	component->FRemoteSubscription.append(subscription);
	FRemoteSubscriptions.append(subscription);
	component->SubscribeEvent(p_eventname, p_event_type, p_priority, p_method_name, p_parameter_count, Variant(this));
}

void TEventbus::Trigger(int p_eventname, const Array &p_values, const Array &p_group, int64_t p_component_id, bool p_write) {
	// open array parameter passed by value
	const Array values = ScriptValues(p_values);
	const Array group = MakeGroup(p_group);
	TThreadContext *ctx = TThreadContext::Get();
	REventScope scope(ctx, p_eventname, group, values);
	auto found = FEventhandler.find(EventKey(p_eventname, p_write ? C::etWrite : C::etTrigger));
	if (found != FEventhandler.end()) {
		RWalk walk(found->second);
		TEventhandler &handler = *walk.Handler;
		TEventEnumerator &enumerator = *walk.Enumerator;
		const int count = int(values.size());
		const Variant *args[MAX_STACK_ARGS];
		std::vector<const Variant *> heap_args;
		const Variant **call_args = args;
		if (count > MAX_STACK_ARGS) {
			heap_args.resize(count);
			call_args = heap_args.data();
		}
		while (enumerator.FActiveIndex < int64_t(handler.Subscribers.size())) {
			const RSubscriber &current = *handler.Subscribers[enumerator.FActiveIndex];
			if (Matches(current.EntityComponent, group, p_component_id)) {
				// the parameters as they are now (see Read)
				for (int i = 0; i < count; i++) {
					call_args[i] = &values[i];
				}
				// TEntityComponent.OnTrigger
				bool continue_event = true;
				if (count != current.ParameterCount) {
					UtilityFunctions::push_error(vformat("Parametercount for trigger event %d in component %s does not match - expected %d, found %d.",
							p_eventname, current.EntityComponent->ComponentClassName(), current.ParameterCount, count));
				} else {
					continue_event = CallHandler(ctx, current, call_args, count).booleanize();
				}
				if (!continue_event) {
					return;
				}
			}
			enumerator.FActiveIndex++;
		}
	}
	if (BC::EventIdentifierToNetworkSend(p_eventname) == ApplicationType) {
		const Array parameters = values.duplicate();
		// only the globaleventbus has no owner
		TEventbus *global_eventbus = FOwner != nullptr ? FOwner->FGlobalEventbus.ptr() : this;
		const int64_t send_id = FOwner != nullptr ? FOwner->FID : 0;
		if (global_eventbus != nullptr) {
			Array send;
			send.append(send_id);
			send.append(p_eventname);
			send.append(group);
			send.append(p_component_id);
			send.append(parameters);
			send.append(p_write);
			global_eventbus->Trigger(C::eiNetworkSend, send, Array(), 0, false);
		}
	}
	if (FOwner != nullptr && p_write && values.size() > 0) {
		FOwner->FBlackboard->SetValue(p_eventname, group, values[0]);
	}
}

void TEventbus::InvokeWithRawData(int p_eventname, const Array &p_group, int64_t p_component_id, const Array &p_values, bool p_write_event) {
	Trigger(p_eventname, p_values, p_group, p_component_id, p_write_event);
}

void TEventbus::Unsubscribe(int p_eventname, int p_event_type, int p_priority, const Variant &p_entity_component) {
	UnsubscribeComponent(p_eventname, p_event_type, p_priority, Object::cast_to<TEntityComponent>(p_entity_component));
}

void TEventbus::UnsubscribeComponent(int p_eventname, int p_event_type, int p_priority, TEntityComponent *p_component) {
	auto found = FEventhandler.find(EventKey(p_eventname, p_event_type));
	ERR_FAIL_COND_MSG(found == FEventhandler.end(), "TEventbus.Unsubscribe: no handler for the event");
	// the handler outlives the removal even if an event is walking it right now
	std::shared_ptr<TEventhandler> handler = found->second;
	handler->RemoveSubscriber(p_component, p_priority);
}

int64_t TEventbus::SubscriberCount(int p_eventname, int p_event_type) const {
	auto found = FEventhandler.find(EventKey(p_eventname, p_event_type));
	return found == FEventhandler.end() ? 0 : int64_t(found->second->Subscribers.size());
}

int TEventbus::GetCurrentEvent_EventIdentifier() {
	return TThreadContext::Get()->CurrentEvent_EventIdentifier;
}

void TEventbus::SetCurrentEvent_EventIdentifier(int p_value) {
	TThreadContext::Get()->CurrentEvent_EventIdentifier = p_value;
}

Array TEventbus::GetCurrentEvent_CalledToGroup() {
	return TThreadContext::Get()->CurrentEvent_CalledToGroup;
}

void TEventbus::SetCurrentEvent_CalledToGroup(const Array &p_value) {
	TThreadContext::Get()->CurrentEvent_CalledToGroup = p_value;
}

Array TEventbus::GetCurrentParameters() {
	return TThreadContext::Get()->CurrentParameters;
}

Variant TEventbus::GetProf() {
	return TThreadContext::Get()->Prof;
}

void TEventbus::SetProf(const Variant &p_value) {
	TThreadContext::Get()->Prof = p_value;
}

} // namespace godot
