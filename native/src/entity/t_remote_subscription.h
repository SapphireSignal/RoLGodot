#pragma once

// TRemoteSubscription (BaseConflict.Entity.pas:123, implementation :2672): a component subscribed on another eventbus.
// Whichever of the two is freed first tells the other side; both must be freed eventually.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class TEntityComponent;
class TEventbus;

class TRemoteSubscription : public RefCounted {
	GDCLASS(TRemoteSubscription, RefCounted)

	Variant FTargetEventbusRef;
	Variant FTargetComponentRef;
	TEventbus *FTargetEventbus = nullptr;
	TEntityComponent *FTargetComponent = nullptr;
	bool FComponentFreed = false;
	bool FEventbusFreed = false;
	int FEvent = 0;
	int FEventType = 0;
	int FEventPriotity = 0;
	int FRefCounter = 0;

protected:
	static void _bind_methods();

public:
	Ref<TRemoteSubscription> Create(const Variant &p_target_component, const Variant &p_target_eventbus, int p_event,
			int p_event_type, int p_event_priority);
	void Destroy();
	void Free() { Destroy(); }
	void DecRefCounter();
	void FreeComponent();
	void FreeEventbus();
};

} // namespace godot
