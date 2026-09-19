#pragma once

// TEntityComponent (BaseConflict.Entity.pas:211, implementation :1230). A component lives in its owner entity, belongs
// to component groups and handles events.
//
// Components still written in GDScript extend the GDScript layer TGDEntityComponent (src/runtime/entity/), which holds
// what they override: the constructors, Destroy, _DeclareEvents (the XEvent list) and the base handlers. GDScript
// cannot override a method a C++ class binds (typed and self calls go straight to the C++ one), so this class binds none
// of those; it calls them through the script (docs/native.md, "GDScript subclasses of C++ classes").

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

class TEntity;
class TEventbus;
struct RSubscriptionPattern;

class TEntityComponent : public RefCounted {
	GDCLASS(TEntityComponent, RefCounted)

public:
	// TEntityComponent.TSubscribedEvent
	struct TSubscribedEvent {
		int Eventname = 0;
		int EventType = 0;
		int EventPriority = 0;
		StringName EventHandler;
		int ParameterCount = 0;
		TEventbus *TargetEventbus = nullptr;
		Variant TargetEventbusRef;
	};

private:
	Variant FOwnerRef;
	Array FComponentGroup;
	// FComponentGroup as bits, for the event bus's group test
	uint64_t FGroupMask[4] = { 0, 0, 0, 0 };

	TSubscribedEvent *LookUpSubscribedEventPtr(const TEventbus *p_caller, int p_ei, int p_et);
	const std::vector<RSubscriptionPattern> &SubscriptionPatterns();

protected:
	static void _bind_methods();

public:
	TEntity *FOwner = nullptr;
	// Unique ID for component related to owner entity NOT global.
	int64_t FUniqueID = 0;
	// [Event * 3 + EventType] -> the subscriptions
	std::unordered_map<int, std::vector<TSubscribedEvent>> FSubscribedEvents;
	Array FRemoteSubscription;

	// Module setup / teardown (register_types.cpp).
	static void Initialize();
	static void Finalize();

	// The body of TEntityComponent.CreateGrouped and Destroy (the GDScript layer's constructors / destructor call them).
	void _CreateGrouped(const Variant &p_owner, const Variant &p_group);
	void _Destroy();

	TEventbus *EventbusPtr() const;
	TEventbus *GlobalEventbusPtr() const;
	Ref<TEventbus> Eventbus() const;
	Ref<TEventbus> GlobalEventbus() const;
	// Assigns a `var` parameter of the executing event (see TEventbus). Index is the parameter position.
	void SetVarParam(int p_index, const Variant &p_value);
	String BuildExceptionMessage(const String &p_exception_message);
	void MakeException(const String &p_exception_message);
	int64_t CardLeague();
	int64_t CardLevel();
	void ChangeEventPriority(int p_eventname, int p_event_type, int p_priority, int p_scope);
	// Use to free component in an event stack.
	void DeferFree();
	// Returns whether the caller belongs to my own group. Prevents execution of groupless events in local groups.
	// IsLocalCall() uses the own ComponentGroup, IsLocalCall(TargetGroup) the given one.
	bool IsLocalCall(const Variant &p_target_group);
	void RegisterInOwner();
	void DeregisterInOwner();
	void SetSetComponentGroup(const Variant &p_value);
	void SubscribeEvent(int p_event, int p_event_type, int p_event_priority, const StringName &p_event_handler,
			int p_parameter_count, const Variant &p_target_eventbus);
	// The side the component is built for, so _DeclareEvents can list {$IFDEF SERVER} handlers only
	// `if IsServerSide():`. The owner decides (FOwner is set before SubscribeEvents).
	bool IsServerSide() const;
	void SubscribeEvents();
	void UnSubscribeEvents();
	const TSubscribedEvent *LookUpSubscribedEvent(const TEventbus *p_caller, int p_ei, int p_et);
	void DeploySubscribedEvent(const TSubscribedEvent &p_event);
	void DeleteSubscribedEvent(const TEventbus *p_caller, int p_ei, int p_et);

	// FComponentGroup is a set of bytes; the bus tests it by bit.
	bool InGroup(int64_t p_group) const {
		return p_group >= 0 && p_group < 256 && (FGroupMask[p_group >> 6] >> (p_group & 63) & 1) != 0;
	}
	bool IsAllGroup() const;

	// Calls a method of the component's script (a GDScript handler or override); falls back to a bound method.
	Variant CallMethod(const StringName &p_method, const Variant **p_args, int p_count) const;
	bool HasScriptMethod(const StringName &p_method) const;
	// TObject.ClassName: the script's class, else the C++ class.
	String ComponentClassName() const;

	Ref<TEntity> GetOwner() const;
	void SetOwner(const Variant &p_value);
	Array GetComponentGroup() const { return FComponentGroup; }
	// the raw field (no re-registration; ComponentGroup's setter is SetSetComponentGroup)
	void SetFComponentGroup(const Variant &p_value);
	int64_t GetUniqueID() const { return FUniqueID; }
	void SetUniqueID(int64_t p_value) { FUniqueID = p_value; }
	Array GetRemoteSubscription() const { return FRemoteSubscription; }
	void SetRemoteSubscription(const Array &p_value) { FRemoteSubscription = p_value; }
	// the subscriptions by key, their handler names (tests)
	Dictionary GetSubscribedEvents() const;
};

} // namespace godot
