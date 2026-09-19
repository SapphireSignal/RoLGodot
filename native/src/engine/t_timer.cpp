#include "engine/t_timer.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>

#include "engine/delphi_math.h"
#include "engine/t_time_manager.h"

namespace godot {

static inline double to_single(double p_x) {
	return double(float(p_x));
}

void TTimer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("Create", "NewInterval"), &TTimer::Create, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("CreateAndStart", "NewInterval"), &TTimer::CreateAndStart);
	ClassDB::bind_method(D_METHOD("CreatePaused", "NewInterval"), &TTimer::CreatePaused);
	ClassDB::bind_method(D_METHOD("Free"), &TTimer::Free);
	ClassDB::bind_method(D_METHOD("Clone"), &TTimer::Clone);
	ClassDB::bind_method(D_METHOD("Delay", "DelayMs"), &TTimer::Delay);
	ClassDB::bind_method(D_METHOD("Expire"), &TTimer::Expire);
	ClassDB::bind_method(D_METHOD("getExpired"), &TTimer::getExpired);
	ClassDB::bind_method(D_METHOD("GetTimeStamp"), &TTimer::GetTimeStamp);
	ClassDB::bind_method(D_METHOD("HasStarted"), &TTimer::HasStarted);
	ClassDB::bind_method(D_METHOD("setExpired", "IsExpired"), &TTimer::setExpired);
	ClassDB::bind_method(D_METHOD("ZeitDiffProzent", "ClampZeroOne"), &TTimer::ZeitDiffProzent, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("ZeitDiffProzentInverted", "ClampZeroOne"), &TTimer::ZeitDiffProzentInverted, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("Start", "NewInterval"), &TTimer::Start, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("StartAndPause"), &TTimer::StartAndPause);
	ClassDB::bind_method(D_METHOD("StartWithRest"), &TTimer::StartWithRest);
	ClassDB::bind_method(D_METHOD("StartWithFrac"), &TTimer::StartWithFrac);
	ClassDB::bind_method(D_METHOD("TimesExpired", "Maximum"), &TTimer::TimesExpired, DEFVAL(-1));
	ClassDB::bind_method(D_METHOD("TimeSinceStart"), &TTimer::TimeSinceStart);
	ClassDB::bind_method(D_METHOD("TimeToExpired"), &TTimer::TimeToExpired);
	ClassDB::bind_method(D_METHOD("Pause"), &TTimer::Pause);
	ClassDB::bind_method(D_METHOD("Progress"), &TTimer::Progress);
	ClassDB::bind_method(D_METHOD("ProgressInverted"), &TTimer::ProgressInverted);
	ClassDB::bind_method(D_METHOD("Reset"), &TTimer::Reset);
	ClassDB::bind_method(D_METHOD("Weiter"), &TTimer::Weiter);
	ClassDB::bind_method(D_METHOD("GetInterval"), &TTimer::GetInterval);
	ClassDB::bind_method(D_METHOD("SetInterval", "NewInterval"), &TTimer::SetInterval);
	ClassDB::bind_method(D_METHOD("SetIntervalAndStart", "NewInterval"), &TTimer::SetIntervalAndStart);
	ClassDB::bind_method(D_METHOD("getPaused"), &TTimer::getPaused);
	ClassDB::bind_method(D_METHOD("setPaused", "IsExpired"), &TTimer::setPaused);
	ClassDB::bind_method(D_METHOD("SetZeitDiffProzent", "Wert"), &TTimer::SetZeitDiffProzent);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "Interval"), "SetInterval", "GetInterval");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "Paused"), "setPaused", "getPaused");
	// whether the interval has passed since the last Start
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "Expired"), "setExpired", "getExpired");
}

Ref<TTimer> TTimer::Create(const Variant &p_new_interval) {
	SetInterval(p_new_interval.get_type() == Variant::NIL ? 1 : int64_t(p_new_interval));
	return Ref<TTimer>(this);
}

Ref<TTimer> TTimer::CreateAndStart(int64_t p_new_interval) {
	Create(p_new_interval);
	Start();
	return Ref<TTimer>(this);
}

Ref<TTimer> TTimer::CreatePaused(int64_t p_new_interval) {
	CreateAndStart(p_new_interval);
	Pause();
	return Ref<TTimer>(this);
}

Ref<TTimer> TTimer::Clone() const {
	Ref<TTimer> result;
	result.instantiate();
	result->FInterval = FInterval;
	result->FLastTime = FLastTime;
	result->FPauseTime = FPauseTime;
	result->FPaused = FPaused;
	return result;
}

void TTimer::Delay(int64_t p_delay_ms) {
	FLastTime = FLastTime + p_delay_ms;
}

void TTimer::Expire() {
	setExpired(true);
}

bool TTimer::getExpired() const {
	if (FPaused) {
		return FPauseTime >= FInterval;
	}
	return GetTimeStamp() - FLastTime >= FInterval;
}

double TTimer::GetTimeStamp() const {
	return TTimeManager::GetFloatingTimestamp();
}

bool TTimer::HasStarted() const {
	return FLastTime >= GetTimeStamp();
}

void TTimer::setExpired(bool p_is_expired) {
	const double EPSILON = 1E-7;
	if (p_is_expired) {
		if (FPaused) {
			FPauseTime = FInterval;
		} else {
			FLastTime = GetTimeStamp() - FInterval - EPSILON; // due to rounding errors we go slightly beyond expired
		}
	} else {
		const bool was_paused = FPaused;
		Start();
		if (was_paused) {
			Pause();
		}
	}
}

double TTimer::ZeitDiffProzent(bool p_clamp_zero_one) const {
	double result = FInterval == 0 ? 1.0 : to_single(TimeSinceStart() / FInterval);
	if (p_clamp_zero_one) {
		result = std::clamp(result, 0.0, 1.0);
	}
	return result;
}

double TTimer::ZeitDiffProzentInverted(bool p_clamp_zero_one) const {
	return to_single(1 - ZeitDiffProzent(p_clamp_zero_one));
}

void TTimer::Start(const Variant &p_new_interval) {
	if (p_new_interval.get_type() != Variant::NIL) {
		SetInterval(int64_t(p_new_interval));
	}
	FLastTime = GetTimeStamp();
	FPaused = false;
}

void TTimer::StartAndPause() {
	Start();
	Pause();
}

void TTimer::StartWithRest() {
	const int64_t whole = std::min<int64_t>(0, int64_t(ZeitDiffProzent()) - 1);
	FLastTime = GetTimeStamp() - delphi::Round((whole + delphi::Frac(ZeitDiffProzent())) * FInterval);
	FPaused = false;
}

void TTimer::StartWithFrac() {
	FLastTime = GetTimeStamp() - delphi::Round(delphi::Frac(ZeitDiffProzent()) * FInterval);
	FPaused = false;
}

int64_t TTimer::TimesExpired(int64_t p_maximum) const {
	int64_t result = int64_t(ZeitDiffProzent());
	if (p_maximum > 0) {
		result = std::min(result, p_maximum);
	}
	return result;
}

double TTimer::TimeSinceStart() const {
	const double result = FPaused ? FPauseTime : GetTimeStamp() - FLastTime;
	return std::max(0.0, result);
}

double TTimer::TimeToExpired() const {
	return to_single(std::max(0.0, (1 - ZeitDiffProzent()) * FInterval));
}

void TTimer::Pause() {
	FPaused = true;
	FPauseTime = GetTimeStamp() - FLastTime;
}

double TTimer::Progress() const {
	const double result = FInterval == 0 ? 1.0 : to_single(TimeSinceStart() / FInterval);
	return std::clamp(result, 0.0, 1.0);
}

double TTimer::ProgressInverted() const {
	return to_single(1 - Progress());
}

void TTimer::Reset() {
	SetZeitDiffProzent(0);
}

void TTimer::Weiter() {
	if (FPaused) {
		FPaused = false;
		FLastTime = GetTimeStamp() - FPauseTime;
	}
}

void TTimer::SetInterval(int64_t p_new_interval) {
	FInterval = std::max<int64_t>(1, p_new_interval);
}

void TTimer::SetIntervalAndStart(int64_t p_new_interval) {
	SetInterval(p_new_interval);
	Start();
}

void TTimer::setPaused(bool p_is_expired) {
	if (FPaused != p_is_expired) {
		if (p_is_expired) {
			Weiter();
		} else {
			Pause();
		}
	}
}

void TTimer::SetZeitDiffProzent(double p_wert) {
	if (FPaused) {
		FPauseTime = p_wert * FInterval;
	} else {
		FLastTime = GetTimeStamp() - p_wert * FInterval;
	}
}

void TGameTimer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("GetStartingTime"), &TGameTimer::GetStartingTime);
	ClassDB::bind_method(D_METHOD("SetStartingTime", "value"), &TGameTimer::SetStartingTime);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "StartingTime"), "SetStartingTime", "GetStartingTime");
}

} // namespace godot
