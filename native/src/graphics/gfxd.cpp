#include "graphics/gfxd.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "engine/t_time_manager.h"

namespace godot {

ObjectID GFXD::FMainScene;
int64_t GFXD::FFrameCount = 0;
int64_t GFXD::FFPSCounter = 0;
int64_t GFXD::FFPSWindowStart = 0;
int64_t GFXD::FCurrentFPS = 0;

void GFXD::_bind_methods() {
	ClassDB::bind_static_method("GFXD", D_METHOD("GetFrameCount"), &GFXD::GetFrameCount);
	ClassDB::bind_static_method("GFXD", D_METHOD("NextFrame"), &GFXD::NextFrame);
	ClassDB::bind_static_method("GFXD", D_METHOD("GetMainScene"), &GFXD::GetMainScene);
	ClassDB::bind_static_method("GFXD", D_METHOD("SetMainScene", "node"), &GFXD::SetMainScene);
	ClassDB::bind_static_method("GFXD", D_METHOD("FPSFrameTick"), &GFXD::FPSFrameTick);
	ClassDB::bind_static_method("GFXD", D_METHOD("FPS"), &GFXD::FPS);
	ClassDB::bind_static_method("GFXD", D_METHOD("AddToScene", "node"), &GFXD::AddToScene);
}

Node *GFXD::GetMainScene() {
	return Object::cast_to<Node>(ObjectDB::get_instance(FMainScene));
}

void GFXD::SetMainScene(Node *p_node) {
	FMainScene = p_node != nullptr ? ObjectID(p_node->get_instance_id()) : ObjectID();
}

void GFXD::FPSFrameTick() {
	FFPSCounter++;
	const int64_t now = TTimeManager::GetTimeStamp();
	const int64_t delta = now - FFPSWindowStart;
	if (delta >= 1000) {
		FCurrentFPS = FFPSCounter * 1000 / delta;
		FFPSCounter = 0;
		FFPSWindowStart = now;
	}
}

void GFXD::AddToScene(Node *p_node) {
	Node *scene = GetMainScene();
	if (scene != nullptr && p_node != nullptr && p_node->get_parent() == nullptr) {
		scene->add_child(p_node);
	}
}

} // namespace godot
