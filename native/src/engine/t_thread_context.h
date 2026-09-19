#pragma once

// The original's threadvars (a game server runs in its own TGameThread): the executing event and its stack
// (BaseConflict.Entity.pas CurrentEvent / Eventstack), the game clock (BaseConflict.Globals.pas GameTimeManager) and
// the per-game NOT_PAYED_RESOURCES (TWelaEffectPayCostComponent class threadvar); the port adds what it keeps per
// thread for the same reasons: the running script's bus stack, the last script error, lazy caches. Game / Map /
// GlobalEventbus / EntityDataCache hang on each side's global bus.
//
// Threads: the main thread's context is swappable (Enter / Leave, e.g. TGameThread running a server frame on the main
// thread in tests or before its thread starts); a started game thread registers its context (RegisterThread, by
// OS.get_thread_caller_id()) during a handshake before it touches any game code. Current() is the calling thread's
// context; C++ code uses TThreadContext::Get() (a thread_local lookup).

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

#include "engine/t_time_manager.h"

namespace godot {

// One [XEvent(...)] of a component class: TEntityComponent.FComponentSubscriptionPatterns' entries.
struct RSubscriptionPattern {
	int Event = 0;
	int EventType = 0;
	int Priority = 0;
	int Scope = 0;
	StringName Method;
	int ParameterCount = 0;
};

class TThreadContext : public RefCounted {
	GDCLASS(TThreadContext, RefCounted)

protected:
	static void _bind_methods();

public:
	// threadvar CurrentEvent : REventInformation, and the port's parameter array of the executing event (SetVarParam)
	int CurrentEvent_EventIdentifier = 0;
	Array CurrentEvent_CalledToGroup;
	Array CurrentParameters;
	// BaseConflict.Globals.pas GameTimeManager: ZDiff of the game's frames
	Ref<TTimeManager> GameTimeManager;
	// the global buses of the scripts running now, innermost last (TEntity.ScriptGame)
	Array ScriptEventbusStack;
	String LastScriptError;
	// TWelaEffectPayCostComponent.DEFAULT_NOT_PAYED_RESOURCES = [reLevel, reTier]
	Array NotPayedResources;
	// lazy caches (filled per thread instead of locked): TEntityComponent.FComponentSubscriptionPatterns (by the
	// class's script, per side: [0] client, [1] server), TEntity's component classes by name, the script index
	std::unordered_map<uint64_t, std::vector<RSubscriptionPattern>> SubscriptionPatterns[2];
	Dictionary ComponentClasses;
	Dictionary ScriptIndex;
	// TEventbus.Prof, the handler profiler (a development aid), and its call stack of child times
	Variant Prof;
	std::vector<int64_t> ProfChildTime;

	TThreadContext();

	// The calling thread's context (C++).
	static TThreadContext *Get();

	static Ref<TThreadContext> Current();
	// Makes p_ctx the calling (main) thread's context; returns the one it replaces, for Leave.
	static Ref<TThreadContext> Enter(const Ref<TThreadContext> &p_ctx);
	static void Leave(const Ref<TThreadContext> &p_previous);
	// Registers a started thread's context (call from the main thread while that thread waits, see TGameThread).
	static void RegisterThread(int64_t p_thread_id, const Ref<TThreadContext> &p_ctx);
	// After the thread has finished.
	static void UnregisterThread(int64_t p_thread_id);
	static bool IsThreadRegistered(int64_t p_thread_id);

	// Module setup / teardown (register_types.cpp): the main thread's context lives between the two.
	static void Initialize();
	static void Finalize();

	int GetCurrentEvent_EventIdentifier() const { return CurrentEvent_EventIdentifier; }
	void SetCurrentEvent_EventIdentifier(int p_value) { CurrentEvent_EventIdentifier = p_value; }
	Array GetCurrentEvent_CalledToGroup() const { return CurrentEvent_CalledToGroup; }
	void SetCurrentEvent_CalledToGroup(const Array &p_value) { CurrentEvent_CalledToGroup = p_value; }
	Array GetCurrentParameters() const { return CurrentParameters; }
	void SetCurrentParameters(const Array &p_value) { CurrentParameters = p_value; }
	Ref<TTimeManager> GetGameTimeManager() const { return GameTimeManager; }
	Array GetNotPayedResources() const { return NotPayedResources; }
	void SetNotPayedResources(const Array &p_value) { NotPayedResources = p_value; }
	String GetLastScriptError() const { return LastScriptError; }
	void SetLastScriptError(const String &p_value) { LastScriptError = p_value; }
	Variant GetProf() const { return Prof; }
	void SetProf(const Variant &p_value) { Prof = p_value; }
};

} // namespace godot
