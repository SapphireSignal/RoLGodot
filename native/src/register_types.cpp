// The GDExtension entry point: registers the game's classes with Godot.

#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "engine/delphi_dictionary.h"
#include "engine/delphi_hash.h"
#include "engine/delphi_random.h"
#include "engine/delphi_rtl.h"
#include "engine/delphi_sort.h"
#include "engine/t_2d_grid.h"
#include "engine/t_priority_queue.h"
#include "engine/t_ring_buffer.h"
#include "engine/t_thread_context.h"
#include "engine/t_time_manager.h"
#include "engine/t_timer.h"
#include "entity/d_set.h"
#include "entity/r_param.h"
#include "entity/t_blackboard.h"
#include "entity/t_entity.h"
#include "entity/t_entity_component.h"
#include "entity/t_entity_stream.h"
#include "entity/t_eventbus.h"
#include "entity/t_remote_subscription.h"
#include "graphics/gfxd.h"
#include "graphics/t_skinned_mesh_animation_driver.h"
#include "math/r_cubic_bezier.h"
#include "math/r_line_2d.h"
#include "math/r_matrix.h"
#include "math/r_ray_2d.h"
#include "math/t_multipolygon.h"
#include "math/t_polygon.h"

using namespace godot;

void initialize_rol_native_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(DSet);
	GDREGISTER_CLASS(RParam);
	GDREGISTER_CLASS(DelphiRandom);
	GDREGISTER_CLASS(DelphiHash);
	GDREGISTER_CLASS(DelphiSort);
	GDREGISTER_CLASS(DelphiRtl);
	GDREGISTER_CLASS(DelphiDictionary);
	GDREGISTER_CLASS(TTimeManager);
	GDREGISTER_CLASS(TTimer);
	GDREGISTER_CLASS(TGameTimer);
	GDREGISTER_CLASS(TPriorityQueue);
	GDREGISTER_CLASS(TIntPriorityQueue);
	GDREGISTER_CLASS(TRingBuffer);
	GDREGISTER_CLASS(T2DGrid);
	GDREGISTER_CLASS(RMatrix);
	GDREGISTER_CLASS(RRay2D);
	GDREGISTER_CLASS(RLine2D);
	GDREGISTER_CLASS(RCubicBezier);
	GDREGISTER_CLASS(TPolygon);
	GDREGISTER_CLASS(TMultipolygon);
	GDREGISTER_CLASS(TThreadContext);
	GDREGISTER_CLASS(TEntityStream);
	GDREGISTER_CLASS(TBlackboard);
	GDREGISTER_CLASS(TEventbus);
	GDREGISTER_CLASS(TEntityComponent);
	GDREGISTER_CLASS(TRemoteSubscription);
	GDREGISTER_CLASS(TEntity);
	GDREGISTER_CLASS(GFXD);
	GDREGISTER_CLASS(TSkinnedMeshAnimationDriver);
	TThreadContext::Initialize();
	TEntityComponent::Initialize();
}

void uninitialize_rol_native_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	TEntityComponent::Finalize();
	TThreadContext::Finalize();
}

extern "C" {
GDExtensionBool GDE_EXPORT rol_native_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_rol_native_module);
	init_obj.register_terminator(uninitialize_rol_native_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
