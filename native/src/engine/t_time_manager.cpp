#include "engine/t_time_manager.h"

#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

#include "engine/delphi_math.h"

namespace godot {

bool TTimeManager::FFakeTimeSet = false;
double TTimeManager::FFakeTime = 0.0;

void TTimeManager::_bind_methods() {
	ClassDB::bind_method(D_METHOD("GetZDiff"), &TTimeManager::GetZDiff);
	ClassDB::bind_method(D_METHOD("SetZDiff", "value"), &TTimeManager::SetZDiff);
	ClassDB::bind_method(D_METHOD("GetLastTickTime"), &TTimeManager::GetLastTickTime);
	ClassDB::bind_method(D_METHOD("SetLastTickTime", "value"), &TTimeManager::SetLastTickTime);
	ClassDB::bind_method(D_METHOD("StartTickTack"), &TTimeManager::StartTickTack);
	ClassDB::bind_method(D_METHOD("TickTack"), &TTimeManager::TickTack);
	ClassDB::bind_static_method("TTimeManager", D_METHOD("SetFakeTime", "time"), &TTimeManager::SetFakeTime);
	ClassDB::bind_static_method("TTimeManager", D_METHOD("GetFakeTime"), &TTimeManager::GetFakeTime);
	ClassDB::bind_static_method("TTimeManager", D_METHOD("GetFloatingTimestamp"), &TTimeManager::GetFloatingTimestamp);
	ClassDB::bind_static_method("TTimeManager", D_METHOD("GetTimeStamp"), &TTimeManager::GetTimeStamp);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ZDiff"), "SetZDiff", "GetZDiff");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "LastTickTime"), "SetLastTickTime", "GetLastTickTime");
}

TTimeManager::TTimeManager() {
	StartTickTack();
}

void TTimeManager::SetZDiff(double p_value) {
	FZDiff = double(float(p_value));
}

void TTimeManager::StartTickTack() {
	FLastTickTime = GetFloatingTimestamp();
}

void TTimeManager::TickTack() {
	const double now = GetFloatingTimestamp();
	FZDiff = double(float(now - FLastTickTime));
	FLastTickTime = now;
}

void TTimeManager::SetFakeTime(const Variant &p_time) {
	FFakeTimeSet = p_time.get_type() != Variant::NIL;
	FFakeTime = FFakeTimeSet ? double(p_time) : 0.0;
}

Variant TTimeManager::GetFakeTime() {
	return FFakeTimeSet ? Variant(FFakeTime) : Variant();
}

double TTimeManager::GetFloatingTimestamp() {
	if (FFakeTimeSet) {
		return FFakeTime;
	}
	return double(Time::get_singleton()->get_ticks_usec()) / 1000.0;
}

int64_t TTimeManager::GetTimeStamp() {
	return delphi::Round(GetFloatingTimestamp());
}

} // namespace godot
