#include "engine/t_thread_context.h"

#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#include <atomic>
#include <mutex>
#include <thread>

#include "dws/dws_const.h"

namespace godot {

namespace {

std::thread::id g_main_thread;
// the main thread's current context (a heap Ref, so nothing is left for the static destructors after Godot is gone)
Ref<TThreadContext> *g_main = nullptr;
std::mutex g_registry_mutex;
std::unordered_map<uint64_t, Ref<TThreadContext>> *g_by_thread = nullptr;
// bumped on every (un)registration: threads re-resolve their cached context
std::atomic<uint32_t> g_generation{ 1 };

enum : int8_t {
	KIND_UNKNOWN,
	KIND_MAIN,
	KIND_REGISTERED,
};

thread_local int8_t t_kind = KIND_UNKNOWN;
thread_local uint32_t t_generation = 0;
thread_local TThreadContext *t_ctx = nullptr;

} // namespace

void TThreadContext::_bind_methods() {
	ClassDB::bind_static_method("TThreadContext", D_METHOD("Current"), &TThreadContext::Current);
	ClassDB::bind_static_method("TThreadContext", D_METHOD("Enter", "ctx"), &TThreadContext::Enter);
	ClassDB::bind_static_method("TThreadContext", D_METHOD("Leave", "previous"), &TThreadContext::Leave);
	ClassDB::bind_static_method("TThreadContext", D_METHOD("RegisterThread", "thread_id", "ctx"), &TThreadContext::RegisterThread);
	ClassDB::bind_static_method("TThreadContext", D_METHOD("UnregisterThread", "thread_id"), &TThreadContext::UnregisterThread);
	ClassDB::bind_static_method("TThreadContext", D_METHOD("IsThreadRegistered", "thread_id"), &TThreadContext::IsThreadRegistered);

	ClassDB::bind_method(D_METHOD("GetCurrentEvent_EventIdentifier"), &TThreadContext::GetCurrentEvent_EventIdentifier);
	ClassDB::bind_method(D_METHOD("SetCurrentEvent_EventIdentifier", "value"), &TThreadContext::SetCurrentEvent_EventIdentifier);
	ClassDB::bind_method(D_METHOD("GetCurrentEvent_CalledToGroup"), &TThreadContext::GetCurrentEvent_CalledToGroup);
	ClassDB::bind_method(D_METHOD("SetCurrentEvent_CalledToGroup", "value"), &TThreadContext::SetCurrentEvent_CalledToGroup);
	ClassDB::bind_method(D_METHOD("GetCurrentParameters"), &TThreadContext::GetCurrentParameters);
	ClassDB::bind_method(D_METHOD("SetCurrentParameters", "value"), &TThreadContext::SetCurrentParameters);
	ClassDB::bind_method(D_METHOD("GetGameTimeManager"), &TThreadContext::GetGameTimeManager);
	ClassDB::bind_method(D_METHOD("GetNotPayedResources"), &TThreadContext::GetNotPayedResources);
	ClassDB::bind_method(D_METHOD("SetNotPayedResources", "value"), &TThreadContext::SetNotPayedResources);
	ClassDB::bind_method(D_METHOD("GetLastScriptError"), &TThreadContext::GetLastScriptError);
	ClassDB::bind_method(D_METHOD("SetLastScriptError", "value"), &TThreadContext::SetLastScriptError);
	ClassDB::bind_method(D_METHOD("GetProf"), &TThreadContext::GetProf);
	ClassDB::bind_method(D_METHOD("SetProf", "value"), &TThreadContext::SetProf);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "CurrentEvent_EventIdentifier"), "SetCurrentEvent_EventIdentifier", "GetCurrentEvent_EventIdentifier");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "CurrentEvent_CalledToGroup"), "SetCurrentEvent_CalledToGroup", "GetCurrentEvent_CalledToGroup");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "CurrentParameters"), "SetCurrentParameters", "GetCurrentParameters");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "GameTimeManager", PROPERTY_HINT_RESOURCE_TYPE, "TTimeManager"), "", "GetGameTimeManager");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "NotPayedResources"), "SetNotPayedResources", "GetNotPayedResources");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "LastScriptError"), "SetLastScriptError", "GetLastScriptError");
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "Prof", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT), "SetProf", "GetProf");
}

TThreadContext::TThreadContext() {
	GameTimeManager.instantiate();
	NotPayedResources.append(C::reLevel);
	NotPayedResources.append(C::reTier);
}

void TThreadContext::Initialize() {
	g_main_thread = std::this_thread::get_id();
	g_main = memnew(Ref<TThreadContext>);
	g_main->instantiate();
	g_by_thread = new std::unordered_map<uint64_t, Ref<TThreadContext>>();
}

void TThreadContext::Finalize() {
	delete g_by_thread;
	g_by_thread = nullptr;
	memdelete(g_main);
	g_main = nullptr;
}

TThreadContext *TThreadContext::Get() {
	if (t_kind == KIND_MAIN) {
		return g_main->ptr();
	}
	const uint32_t generation = g_generation.load(std::memory_order_acquire);
	if (t_kind == KIND_REGISTERED && t_generation == generation) {
		return t_ctx;
	}
	if (std::this_thread::get_id() == g_main_thread) {
		t_kind = KIND_MAIN;
		return g_main->ptr();
	}
	const uint64_t id = OS::get_singleton()->get_thread_caller_id();
	std::lock_guard<std::mutex> lock(g_registry_mutex);
	auto found = g_by_thread->find(id);
	if (found == g_by_thread->end()) {
		// not (or no longer) registered: the main context, like the original's default
		t_kind = KIND_UNKNOWN;
		return g_main->ptr();
	}
	t_kind = KIND_REGISTERED;
	t_generation = generation;
	t_ctx = found->second.ptr();
	return t_ctx;
}

Ref<TThreadContext> TThreadContext::Current() {
	return Ref<TThreadContext>(Get());
}

Ref<TThreadContext> TThreadContext::Enter(const Ref<TThreadContext> &p_ctx) {
	ERR_FAIL_COND_V_MSG(std::this_thread::get_id() != g_main_thread, Ref<TThreadContext>(),
			"TThreadContext.Enter: only the main thread swaps its context");
	Ref<TThreadContext> previous = *g_main;
	*g_main = p_ctx;
	return previous;
}

void TThreadContext::Leave(const Ref<TThreadContext> &p_previous) {
	*g_main = p_previous;
}

void TThreadContext::RegisterThread(int64_t p_thread_id, const Ref<TThreadContext> &p_ctx) {
	std::lock_guard<std::mutex> lock(g_registry_mutex);
	(*g_by_thread)[uint64_t(p_thread_id)] = p_ctx;
	g_generation.fetch_add(1, std::memory_order_release);
}

void TThreadContext::UnregisterThread(int64_t p_thread_id) {
	std::lock_guard<std::mutex> lock(g_registry_mutex);
	g_by_thread->erase(uint64_t(p_thread_id));
	g_generation.fetch_add(1, std::memory_order_release);
}

bool TThreadContext::IsThreadRegistered(int64_t p_thread_id) {
	std::lock_guard<std::mutex> lock(g_registry_mutex);
	return g_by_thread->count(uint64_t(p_thread_id)) > 0;
}

} // namespace godot
