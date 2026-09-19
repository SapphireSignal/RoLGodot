#pragma once

// TEventbus (BaseConflict.Entity.pas:141, implementation :990). Every entity has one; the game has a global one
// (Owner = nil). Subscribers are TEntityComponents, ordered by priority, then by subscription order. The script side
// (TEventbusScriptSideHelper, :2034) is folded in: Trigger / Write take the script's value array (floats become
// singles), TriggerGrouped / WriteGrouped add the group.
// - `var` event parameters: Delphi hands every handler the same parameter array by reference, so a handler that
//   assigns a `var` parameter changes what later handlers (and the blackboard write) see. Handlers written in GDScript
//   get copies; they call TEntityComponent.SetVarParam, which writes into the thread's CurrentParameters.
// - ApplicationType replaces the per-process APPLICATIONTYPE; Game the per-process Game global; EntityDataCache the
//   EntityDataCache global (per game thread, the client's per process: the global bus carries it and frees it).
// - The threadvar CurrentEvent and the Eventstack live in TThreadContext; an event keeps the outer event in locals and
//   restores it when it ends.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <deque>
#include <memory>
#include <unordered_map>
#include <vector>

#include "dws/dws_const.h"

namespace godot {

class TEntity;
class TEntityComponent;
class TThreadContext;

class TEventbus : public RefCounted {
	GDCLASS(TEventbus, RefCounted)

public:
	// TEventbus.RSubscriber. It also carries the handler and its parameter count (the original's
	// TEntityComponent.OnRead / OnTrigger look the handler up per call).
	struct RSubscriber {
		TEntityComponent *EntityComponent = nullptr;
		int Priority = 0;
		StringName Method;
		int ParameterCount = 0;
		// the subscription keeps the component alive (it lives as long as it is subscribed somewhere)
		Variant Keep;
	};

	// TEventbus.TEventEnumerator: one per nesting level of the same event, kept in step with inserts / removals.
	struct TEventEnumerator {
		bool FCurrentlyActive = false;
		int64_t FActiveIndex = 0;
	};

	// TEventbus.TEventhandler: the subscriber list of one event and event type.
	struct TEventhandler {
		int ParameterCount = 0;
		std::deque<TEventEnumerator> FEnumerators;
		size_t FEnumeratorIndex = 0;
		// (on the heap: a running handler's subscriber stays where it is while the list changes)
		std::vector<std::unique_ptr<RSubscriber>> Subscribers;
		// removed subscribers wait here while an event walks the list: a handler may unsubscribe (and so free) its
		// own component while it runs
		std::vector<std::unique_ptr<RSubscriber>> FRemoved;

		void AddSubscriber(std::unique_ptr<RSubscriber> p_subscriber);
		void RemoveSubscriber(TEntityComponent *p_component, int p_priority);
		TEventEnumerator &GetEnumerator();
		void ReleaseEnumerator();
	};

private:
	Variant FOwnerRef;
	// [EnumEventIdentifier * 3 + EnumEventType] -> TEventhandler
	std::unordered_map<int, std::shared_ptr<TEventhandler>> FEventhandler;
	Array FRemoteSubscriptions;
	Variant FGame;
	Variant FEntityDataCache;

	static bool Matches(const TEntityComponent *p_component, const Array &p_group, int64_t p_component_id);
	static Variant CallHandler(TThreadContext *p_ctx, const RSubscriber &p_subscriber, const Variant **p_args, int p_count);
	static void ProfLeave(TThreadContext *p_ctx, const RSubscriber &p_subscriber, int64_t p_start);

protected:
	static void _bind_methods();

public:
	TEntity *FOwner = nullptr;
	// nsServer or nsClient, the side this bus lives on (APPLICATIONTYPE of the original process)
	int ApplicationType = C::nsServer;

	Ref<TEventbus> Create(const Variant &p_owner);
	void Destroy();
	void Free() { Destroy(); }
	String ClassName() const { return "TEventbus"; }

	Variant Read(int p_eventname, const Array &p_parameters, const Array &p_group, int64_t p_component_id);
	// Reads a value in the local group and if empty is returned, read in the global group.
	Variant ReadHierarchic(int p_eventname, const Array &p_values, const Array &p_group);
	// MethodName and ParameterCount are the handler the subscriber calls.
	void Subscribe(int p_eventname, int p_event_type, int p_priority, const Variant &p_entity_component, int p_parameter_count,
			const StringName &p_method_name);
	// Subscribe one remote eventbus (a component listening on another entity's or the global bus).
	void SubscribeRemote(int p_eventname, int p_event_type, int p_priority, const Variant &p_entity_component,
			const StringName &p_method_name, int p_parameter_count, int p_network_sender);
	// Values: `array of RParam`. Script side Trigger(Eventname, Values) goes here too.
	void Trigger(int p_eventname, const Array &p_values, const Array &p_group, int64_t p_component_id, bool p_write);
	void Write(int p_eventname, const Array &p_values, const Array &p_group, int64_t p_component_id) {
		Trigger(p_eventname, p_values, p_group, p_component_id, true);
	}
	// An event received over the network (TNetworkComponent.NewData): Values are the sender's parameters as they came
	// off the wire (empty ones are nil). Write or Trigger here.
	void InvokeWithRawData(int p_eventname, const Array &p_group, int64_t p_component_id, const Array &p_values, bool p_write_event);
	// Script side TriggerGrouped / WriteGrouped(Eventname, Values, Group)
	void TriggerGrouped(int p_eventname, const Array &p_values, const Array &p_group) { Trigger(p_eventname, p_values, p_group, 0, false); }
	void WriteGrouped(int p_eventname, const Array &p_values, const Array &p_group) { Trigger(p_eventname, p_values, p_group, 0, true); }
	void Unsubscribe(int p_eventname, int p_event_type, int p_priority, const Variant &p_entity_component);
	void UnsubscribeComponent(int p_eventname, int p_event_type, int p_priority, TEntityComponent *p_component);
	void AddRemoteSubscription(const Variant &p_subscription) { FRemoteSubscriptions.append(p_subscription); }

	// Development aid: the subscriber count of one event and type (tests/bench_eventbus.gd).
	int64_t SubscriberCount(int p_eventname, int p_event_type) const;

	Variant GetOwner() const { return FOwnerRef; }
	int GetApplicationType() const { return ApplicationType; }
	void SetApplicationType(int p_value) { ApplicationType = p_value; }
	Variant GetGame() const { return FGame; }
	void SetGame(const Variant &p_value) { FGame = p_value; }
	Variant GetEntityDataCache() const { return FEntityDataCache; }
	void SetEntityDataCache(const Variant &p_value) { FEntityDataCache = p_value; }

	// the threadvar CurrentEvent of the calling thread
	static int GetCurrentEvent_EventIdentifier();
	static void SetCurrentEvent_EventIdentifier(int p_value);
	static Array GetCurrentEvent_CalledToGroup();
	static void SetCurrentEvent_CalledToGroup(const Array &p_value);
	static Array GetCurrentParameters();
	// Development aid: SetProf({}) times every handler call ("Class.Method" -> [calls, self us, inclusive us]; self time
	// leaves out the handlers it calls through the buses), per thread. tests/profile_sandbox.gd uses it.
	static Variant GetProf();
	static void SetProf(const Variant &p_value);
};

} // namespace godot
