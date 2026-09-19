#include "entity/t_entity_component.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>

#include "dws/dws_const.h"
#include "engine/t_thread_context.h"
#include "entity/d_set.h"
#include "entity/r_param.h"
#include "entity/t_entity.h"
#include "entity/t_eventbus.h"
#include "entity/t_remote_subscription.h"

namespace godot {

namespace {

inline int EventKey(int p_event, int p_event_type) {
	return p_event * 3 + p_event_type;
}

// the method names the class calls through the script (made and freed with the module, see register_types.cpp)
StringName *g_declare_events_name = nullptr;
StringName *g_class_name_name = nullptr;

const StringName &DeclareEventsName() {
	return *g_declare_events_name;
}

const StringName &ClassNameName() {
	return *g_class_name_name;
}

} // namespace

void TEntityComponent::_bind_methods() {
	ClassDB::bind_method(D_METHOD("_CreateGrouped", "Owner", "Group"), &TEntityComponent::_CreateGrouped);
	ClassDB::bind_method(D_METHOD("_Destroy"), &TEntityComponent::_Destroy);
	ClassDB::bind_method(D_METHOD("Eventbus"), &TEntityComponent::Eventbus);
	ClassDB::bind_method(D_METHOD("GlobalEventbus"), &TEntityComponent::GlobalEventbus);
	ClassDB::bind_method(D_METHOD("SetVarParam", "Index", "Value"), &TEntityComponent::SetVarParam);
	ClassDB::bind_method(D_METHOD("BuildExceptionMessage", "ExceptionMessage"), &TEntityComponent::BuildExceptionMessage);
	ClassDB::bind_method(D_METHOD("MakeException", "ExceptionMessage"), &TEntityComponent::MakeException);
	ClassDB::bind_method(D_METHOD("CardLeague"), &TEntityComponent::CardLeague);
	ClassDB::bind_method(D_METHOD("CardLevel"), &TEntityComponent::CardLevel);
	ClassDB::bind_method(D_METHOD("ChangeEventPriority", "Eventname", "EventType", "Priority", "Scope"),
			&TEntityComponent::ChangeEventPriority, DEFVAL(C::esLocal));
	ClassDB::bind_method(D_METHOD("DeferFree"), &TEntityComponent::DeferFree);
	ClassDB::bind_method(D_METHOD("IsLocalCall", "TargetGroup"), &TEntityComponent::IsLocalCall, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("RegisterInOwner"), &TEntityComponent::RegisterInOwner);
	ClassDB::bind_method(D_METHOD("DeregisterInOwner"), &TEntityComponent::DeregisterInOwner);
	ClassDB::bind_method(D_METHOD("SetSetComponentGroup", "Value"), &TEntityComponent::SetSetComponentGroup);
	ClassDB::bind_method(D_METHOD("SubscribeEvent", "Event", "EventType", "EventPriority", "EventHandler", "ParameterCount", "TargetEventbus"),
			&TEntityComponent::SubscribeEvent);
	ClassDB::bind_method(D_METHOD("IsServerSide"), &TEntityComponent::IsServerSide);

	ClassDB::bind_method(D_METHOD("GetOwner"), &TEntityComponent::GetOwner);
	ClassDB::bind_method(D_METHOD("SetOwner", "value"), &TEntityComponent::SetOwner);
	ClassDB::bind_method(D_METHOD("GetComponentGroup"), &TEntityComponent::GetComponentGroup);
	ClassDB::bind_method(D_METHOD("SetFComponentGroup", "value"), &TEntityComponent::SetFComponentGroup);
	ClassDB::bind_method(D_METHOD("GetUniqueID"), &TEntityComponent::GetUniqueID);
	ClassDB::bind_method(D_METHOD("SetUniqueID", "value"), &TEntityComponent::SetUniqueID);
	ClassDB::bind_method(D_METHOD("GetRemoteSubscription"), &TEntityComponent::GetRemoteSubscription);
	ClassDB::bind_method(D_METHOD("SetRemoteSubscription", "value"), &TEntityComponent::SetRemoteSubscription);
	ClassDB::bind_method(D_METHOD("GetSubscribedEvents"), &TEntityComponent::GetSubscribedEvents);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "FOwner", PROPERTY_HINT_RESOURCE_TYPE, "TEntity"), "SetOwner", "GetOwner");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "Owner", PROPERTY_HINT_RESOURCE_TYPE, "TEntity"), "", "GetOwner");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "FComponentGroup"), "SetFComponentGroup", "GetComponentGroup");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "ComponentGroup"), "SetSetComponentGroup", "GetComponentGroup");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "FUniqueID"), "SetUniqueID", "GetUniqueID");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "UniqueID"), "", "GetUniqueID");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "FRemoteSubscription"), "SetRemoteSubscription", "GetRemoteSubscription");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "FSubscribedEvents"), "", "GetSubscribedEvents");
}

void TEntityComponent::Initialize() {
	g_declare_events_name = memnew(StringName("_DeclareEvents"));
	g_class_name_name = memnew(StringName("ClassName"));
}

void TEntityComponent::Finalize() {
	memdelete(g_declare_events_name);
	memdelete(g_class_name_name);
	g_declare_events_name = nullptr;
	g_class_name_name = nullptr;
}

// ---- constructor / destructor ------------------------------------------------------------------------------------

void TEntityComponent::_CreateGrouped(const Variant &p_owner, const Variant &p_group) {
	SetOwner(p_owner);
	FRemoteSubscription = Array();
	FUniqueID = FOwner->GetNewComponentID();
	SetFComponentGroup(DSet::Make(p_group));
	RegisterInOwner();
	SubscribeEvents();
}

void TEntityComponent::_Destroy() {
	// the subscriptions may hold the last references: stay alive until the end
	const Variant keep(this);
	DeregisterInOwner();
	UnSubscribeEvents();
	FRemoteSubscription = Array();
	// break the reference cycle (Delphi frees memory by hand)
	FOwner = nullptr;
	FOwnerRef = Variant();
}

// ---- accessors -------------------------------------------------------------------------------------------------------

void TEntityComponent::SetOwner(const Variant &p_value) {
	FOwnerRef = p_value;
	FOwner = Object::cast_to<TEntity>(p_value);
}

void TEntityComponent::SetFComponentGroup(const Variant &p_value) {
	FComponentGroup = p_value;
	FGroupMask[0] = FGroupMask[1] = FGroupMask[2] = FGroupMask[3] = 0;
	for (int64_t i = 0; i < FComponentGroup.size(); i++) {
		const int64_t group = FComponentGroup[i];
		if (group >= 0 && group < 256) {
			FGroupMask[group >> 6] |= uint64_t(1) << (group & 63);
		}
	}
}

bool TEntityComponent::IsAllGroup() const {
	return FComponentGroup.size() == 1 && int64_t(FComponentGroup[0]) == C::ALLGROUP_INDEX;
}

TEventbus *TEntityComponent::EventbusPtr() const {
	DEV_ASSERT(FOwner != nullptr);
	return FOwner->FEventbus.ptr();
}

TEventbus *TEntityComponent::GlobalEventbusPtr() const {
	DEV_ASSERT(FOwner != nullptr);
	return FOwner->FGlobalEventbus.ptr();
}

Ref<TEventbus> TEntityComponent::Eventbus() const {
	ERR_FAIL_NULL_V(FOwner, Ref<TEventbus>());
	return FOwner->FEventbus;
}

Ref<TEventbus> TEntityComponent::GlobalEventbus() const {
	ERR_FAIL_NULL_V(FOwner, Ref<TEventbus>());
	return FOwner->FGlobalEventbus;
}

Ref<TEntity> TEntityComponent::GetOwner() const {
	return Ref<TEntity>(FOwner);
}

Dictionary TEntityComponent::GetSubscribedEvents() const {
	Dictionary result;
	for (const auto &entry : FSubscribedEvents) {
		if (entry.second.empty()) {
			continue;
		}
		Array handlers;
		for (const TSubscribedEvent &event : entry.second) {
			handlers.append(event.EventHandler);
		}
		result[entry.first] = handlers;
	}
	return result;
}

// ---- calls into the script -------------------------------------------------------------------------------------------

Variant TEntityComponent::CallMethod(const StringName &p_method, const Variant **p_args, int p_count) const {
	GDExtensionCallError error;
	Variant result;
	gdextension_interface::object_call_script_method(_owner, &p_method, reinterpret_cast<const GDExtensionConstVariantPtr *>(p_args),
			p_count, &result, &error);
	if (error.error == GDEXTENSION_CALL_OK) {
		return result;
	}
	if (error.error == GDEXTENSION_CALL_ERROR_INVALID_METHOD) {
		// a method of the C++ class
		Variant self(const_cast<TEntityComponent *>(this));
		self.callp(p_method, p_args, p_count, result, error);
		if (error.error == GDEXTENSION_CALL_OK) {
			return result;
		}
	}
	UtilityFunctions::push_error(vformat("TEntityComponent: calling %s.%s failed (error %d)", ComponentClassName(), p_method,
			int(error.error)));
	return Variant();
}

bool TEntityComponent::HasScriptMethod(const StringName &p_method) const {
	return gdextension_interface::object_has_script_method(_owner, &p_method);
}

String TEntityComponent::ComponentClassName() const {
	if (HasScriptMethod(ClassNameName())) {
		return CallMethod(ClassNameName(), nullptr, 0);
	}
	return get_class();
}

// ---- TEntityComponent ------------------------------------------------------------------------------------------------

void TEntityComponent::SetVarParam(int p_index, const Variant &p_value) {
	TThreadContext::Get()->CurrentParameters[p_index] = p_value;
}

String TEntityComponent::BuildExceptionMessage(const String &p_exception_message) {
	return vformat("%s.%s Group|Called: %s|%s Entity: %s", ComponentClassName(), p_exception_message,
			Variant(FComponentGroup).stringify(), Variant(TThreadContext::Get()->CurrentEvent_CalledToGroup).stringify(),
			FOwner != nullptr ? FOwner->FScriptFile : String());
}

void TEntityComponent::MakeException(const String &p_exception_message) {
	UtilityFunctions::push_error(BuildExceptionMessage(p_exception_message));
}

int64_t TEntityComponent::CardLeague() {
	Array values;
	values.append(C::reCardLeague);
	return RParam::AsInteger(EventbusPtr()->ReadHierarchic(C::eiResourceBalance, values, FComponentGroup));
}

int64_t TEntityComponent::CardLevel() {
	Array values;
	values.append(C::reCardLevel);
	return RParam::AsInteger(EventbusPtr()->ReadHierarchic(C::eiResourceBalance, values, FComponentGroup));
}

void TEntityComponent::ChangeEventPriority(int p_eventname, int p_event_type, int p_priority, int p_scope) {
	const Variant keep(this);
	TEventbus *target_eventbus = p_scope == C::esGlobal ? GlobalEventbusPtr() : EventbusPtr();
	const TSubscribedEvent *found = LookUpSubscribedEvent(target_eventbus, p_eventname, p_event_type);
	ERR_FAIL_NULL_MSG(found, "TEntityComponent.ChangeEventPriority: Could not find event to change!");
	TSubscribedEvent subscribed_event = *found;
	DeleteSubscribedEvent(target_eventbus, p_eventname, p_event_type);
	target_eventbus->UnsubscribeComponent(subscribed_event.Eventname, subscribed_event.EventType, subscribed_event.EventPriority, this);
	subscribed_event.EventPriority = p_priority;
	DeploySubscribedEvent(subscribed_event);
	target_eventbus->Subscribe(subscribed_event.Eventname, subscribed_event.EventType, subscribed_event.EventPriority, keep,
			subscribed_event.ParameterCount, subscribed_event.EventHandler);
}

void TEntityComponent::DeferFree() {
	if (FOwner == nullptr || GlobalEventbusPtr() == nullptr) {
		return;
	}
	const Variant game = GlobalEventbusPtr()->GetGame();
	if (game.get_type() == Variant::NIL) {
		return;
	}
	bool valid = false;
	Variant entity_manager = game.get_named("EntityManager", valid);
	entity_manager.call("FreeComponent", Variant(this));
}

bool TEntityComponent::IsLocalCall(const Variant &p_target_group) {
	const Array target = p_target_group.get_type() == Variant::NIL ? FComponentGroup : DSet::Make(p_target_group);
	return DSet::Intersects(TThreadContext::Get()->CurrentEvent_CalledToGroup, target) || target.is_empty();
}

void TEntityComponent::RegisterInOwner() {
	if (FOwner != nullptr) {
		FOwner->RegisterComponent(this);
	}
}

void TEntityComponent::DeregisterInOwner() {
	if (FOwner != nullptr) {
		FOwner->DeregisterComponent(this);
	}
}

void TEntityComponent::SetSetComponentGroup(const Variant &p_value) {
	DeregisterInOwner();
	SetFComponentGroup(DSet::Make(p_value));
	RegisterInOwner();
}

void TEntityComponent::SubscribeEvent(int p_event, int p_event_type, int p_event_priority, const StringName &p_event_handler,
		int p_parameter_count, const Variant &p_target_eventbus) {
	TEventbus *target_eventbus = Object::cast_to<TEventbus>(p_target_eventbus);
	ERR_FAIL_NULL_MSG(target_eventbus, vformat("TEntityComponent.SubscribeEvent: %s has no eventbus for %s", ComponentClassName(), p_event_handler));
	// subscribe event
	target_eventbus->Subscribe(p_event, p_event_type, p_event_priority, Variant(this), p_parameter_count, p_event_handler);
	TSubscribedEvent subscribed_event;
	subscribed_event.Eventname = p_event;
	subscribed_event.EventType = p_event_type;
	subscribed_event.EventPriority = p_event_priority;
	subscribed_event.EventHandler = p_event_handler;
	subscribed_event.ParameterCount = p_parameter_count;
	subscribed_event.TargetEventbus = target_eventbus;
	subscribed_event.TargetEventbusRef = p_target_eventbus;
	DeploySubscribedEvent(subscribed_event);
}

bool TEntityComponent::IsServerSide() const {
	return FOwner != nullptr && FOwner->IsServer();
}

// The class's subscription patterns, built once per class and side from _DeclareEvents: [XEvent(MethodName, Event,
// EventPriotity, EventType, EventScope)] entries; a later entry for the same event and event type replaces the earlier
// one (the derived class wins: "prevent double subscription by inheritance").
const std::vector<RSubscriptionPattern> &TEntityComponent::SubscriptionPatterns() {
	TThreadContext *ctx = TThreadContext::Get();
	const Object *script = get_script();
	const uint64_t key = script != nullptr ? uint64_t(script->get_instance_id()) : 0;
	std::unordered_map<uint64_t, std::vector<RSubscriptionPattern>> &cache = ctx->SubscriptionPatterns[IsServerSide() ? 1 : 0];
	auto found = cache.find(key);
	if (found != cache.end()) {
		return found->second;
	}
	std::vector<RSubscriptionPattern> patterns;
	if (HasScriptMethod(DeclareEventsName())) {
		Array declared;
		const Variant declared_arg = declared;
		const Variant *args[1] = { &declared_arg };
		CallMethod(DeclareEventsName(), args, 1);
		for (int64_t i = 0; i < declared.size(); i++) {
			const Array d = declared[i];
			RSubscriptionPattern pattern;
			pattern.Method = d[0];
			pattern.Event = int64_t(d[1]);
			pattern.Priority = int64_t(d[2]);
			pattern.EventType = int64_t(d[3]);
			pattern.Scope = int64_t(d[4]);
			if (!has_method(pattern.Method)) {
				UtilityFunctions::push_error(vformat("TEntityComponent.SubscribeEvents: %s has no method %s", ComponentClassName(), pattern.Method));
				continue;
			}
			pattern.ParameterCount = get_method_argument_count(pattern.Method);
			bool replaced = false;
			for (RSubscriptionPattern &existing : patterns) {
				if (existing.Event == pattern.Event && existing.EventType == pattern.EventType) {
					existing = pattern;
					replaced = true;
					break;
				}
			}
			if (!replaced) {
				patterns.push_back(pattern);
			}
		}
	}
	return cache.emplace(key, std::move(patterns)).first->second;
}

void TEntityComponent::SubscribeEvents() {
	const std::vector<RSubscriptionPattern> &patterns = SubscriptionPatterns();
	for (const RSubscriptionPattern &p : patterns) {
		const Variant target_eventbus = p.Scope == C::esLocal ? FOwner->FEventbus : FOwner->FGlobalEventbus;
		SubscribeEvent(p.Event, p.EventType, p.Priority, p.Method, p.ParameterCount, target_eventbus);
	}
}

void TEntityComponent::UnSubscribeEvents() {
	const Array remote = FRemoteSubscription.duplicate();
	for (int64_t i = 0; i < remote.size(); i++) {
		Object::cast_to<TRemoteSubscription>(remote[i])->FreeComponent();
	}
	std::unordered_map<int, std::vector<TSubscribedEvent>> subscribed;
	subscribed.swap(FSubscribedEvents);
	std::vector<int> keys;
	keys.reserve(subscribed.size());
	for (const auto &entry : subscribed) {
		keys.push_back(entry.first);
	}
	std::sort(keys.begin(), keys.end());
	for (int key : keys) {
		for (const TSubscribedEvent &event : subscribed[key]) {
			event.TargetEventbus->UnsubscribeComponent(event.Eventname, event.EventType, event.EventPriority, this);
		}
	}
}

TEntityComponent::TSubscribedEvent *TEntityComponent::LookUpSubscribedEventPtr(const TEventbus *p_caller, int p_ei, int p_et) {
	auto found = FSubscribedEvents.find(EventKey(p_ei, p_et));
	if (found == FSubscribedEvents.end()) {
		return nullptr;
	}
	for (TSubscribedEvent &event : found->second) {
		if (event.TargetEventbus == p_caller) {
			return &event;
		}
	}
	return nullptr;
}

const TEntityComponent::TSubscribedEvent *TEntityComponent::LookUpSubscribedEvent(const TEventbus *p_caller, int p_ei, int p_et) {
	return LookUpSubscribedEventPtr(p_caller, p_ei, p_et);
}

void TEntityComponent::DeploySubscribedEvent(const TSubscribedEvent &p_event) {
	DEV_ASSERT(LookUpSubscribedEvent(p_event.TargetEventbus, p_event.Eventname, p_event.EventType) == nullptr); // Double subscription!
	FSubscribedEvents[EventKey(p_event.Eventname, p_event.EventType)].push_back(p_event);
}

void TEntityComponent::DeleteSubscribedEvent(const TEventbus *p_caller, int p_ei, int p_et) {
	auto found = FSubscribedEvents.find(EventKey(p_ei, p_et));
	if (found == FSubscribedEvents.end()) {
		return;
	}
	std::vector<TSubscribedEvent> &list = found->second;
	for (auto it = list.begin(); it != list.end(); ++it) {
		if (it->TargetEventbus == p_caller) {
			list.erase(it);
			return;
		}
	}
}

} // namespace godot
